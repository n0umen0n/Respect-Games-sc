// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

interface ICommunityGovernanceContributions {
    struct Group {
        address[] members;
    }
    function getGroupsForWeek(uint256 _communityId, uint256 _weekNumber) external view returns (Group[] memory);
    function updateRespectData(uint256 _communityId, address _user, uint256 _weekNumber, uint256 _respect) external;
}

interface ICommunityGovernanceRankings {
    function determineConsensusForAllGroups(uint256 _communityId, uint256 _weekNumber) external;
}


interface ICommunityGovernanceProfiles {
    enum CommunityState { ContributionSubmission, ContributionRanking }

    function getUserProfile(address _user) external view returns (string memory, string memory, string memory);
    function getUserCommunityData(address _user, uint256 _communityId) external view returns (uint256, bool, address[] memory);
    function getCommunityProfile(uint256 _communityId) external view returns (string memory, string memory, string memory, address, uint256, CommunityState, uint256, address);
    function getRespectToDistribute(uint256 _communityId) external view returns (uint256);

}

/**
 * @title CommunityGovernance
 * @dev Manages community creation, membership, and contributions
 * @custom:dev-run-script /script/threetogethermerged.js
*/
contract CommunityGovernanceRankings is ERC1155, Ownable {
    ICommunityGovernanceContributions public contributionsContract;
    ICommunityGovernanceProfiles public profilesContract;

    uint256 constant SCALE = 1e18;

    struct Ranking {
        uint256[] rankedScores;
    }

    struct ConsensusRanking {
        uint256[] rankedScores;
        uint256[] transientScores;
        uint256 timestamp;
    }

    struct ClaimableTokens {
        uint256 amount;
        bool claimed;
    }

    mapping(uint256 => mapping(uint256 => mapping(uint256 => mapping(address => Ranking)))) private rankings;
    mapping(uint256 => mapping(uint256 => mapping(uint256 => ConsensusRanking))) private consensusRankings;
    mapping(uint256 => bool) public communityExists;
    mapping(uint256 => mapping(address => ClaimableTokens)) public userClaimableTokens;


    uint256[] private respectValues = [21, 13, 8, 5, 3, 2];

    event RankingSubmitted(uint256 indexed communityId, uint256 weekNumber, uint256 groupId, address indexed submitter);
    event ConsensusReached(uint256 indexed communityId, uint256 weekNumber, uint256 groupId, uint256[] consensusRanking);
    event RespectIssued(uint256 indexed communityId, uint256 weekNumber, uint256 groupId, address indexed recipient, uint256 amount);
    event DebugLog(string message, uint256 value);
    event RespectIssueFailed(uint256 indexed communityId, uint256 weekNumber, uint256 groupId, address indexed recipient, uint256 amount, string reason);
    event TokensClaimed(uint256 indexed communityId, address indexed user, uint256 amount);

    constructor(address _contributionsContractAddress, address _profilesContractAddress) ERC1155("") Ownable(msg.sender) {
        contributionsContract = ICommunityGovernanceContributions(_contributionsContractAddress);
        profilesContract = ICommunityGovernanceProfiles(_profilesContractAddress);
        console.log("Contract is being deployed!");
    }

    function createCommunityToken(uint256 communityId) external onlyOwner {
        require(!communityExists[communityId], "Community token already exists");
        communityExists[communityId] = true;
    }

    function submitRanking(uint256 _communityId, uint256 _weekNumber, uint256 _groupId, uint256[] memory _ranking) public {

        (, , , , , ICommunityGovernanceProfiles.CommunityState state, uint256 currentWeek, ) = profilesContract.getCommunityProfile(_communityId);
        require(state == ICommunityGovernanceProfiles.CommunityState.ContributionRanking, "Not in ranking phase");
        require(_weekNumber == currentWeek, "Can only submit rankings for the current week");

        ICommunityGovernanceContributions.Group[] memory groups = contributionsContract.getGroupsForWeek(_communityId, _weekNumber);
        require(_groupId < groups.length, "Invalid group ID");
        ICommunityGovernanceContributions.Group memory group = groups[_groupId];
        require(_ranking.length == group.members.length, "Ranking must include all group members");
        require(isPartOfGroup(group, msg.sender), "Sender not part of the group");
        require(rankings[_communityId][_weekNumber][_groupId][msg.sender].rankedScores.length == 0, "Ranking already submitted");

        rankings[_communityId][_weekNumber][_groupId][msg.sender] = Ranking(_ranking);
        emit RankingSubmitted(_communityId, _weekNumber, _groupId, msg.sender);
    }

function determineConsensus(uint256 _communityId, uint256 _weekNumber, uint256 _groupId) public {
    console.log("Determining consensus for community %s, week %s, group %s", _communityId, _weekNumber, _groupId);

    (, , , , , ICommunityGovernanceProfiles.CommunityState state, uint256 currentWeek, ) = profilesContract.getCommunityProfile(_communityId);
    console.log("Current week from profile: %s, Current state: %s", currentWeek, uint(state));


    ICommunityGovernanceContributions.Group[] memory groups = contributionsContract.getGroupsForWeek(_communityId, _weekNumber);
    require(_groupId < groups.length, "Invalid group ID");
    ICommunityGovernanceContributions.Group memory group = groups[_groupId];
    require(group.members.length > 0, "Group does not exist");
    
    //no need for that
    console.log("Checking if all members submitted rankings");
    bool allSubmitted = allMembersSubmitted(_communityId, _weekNumber, _groupId, group);
    console.log("All members submitted: %s", allSubmitted);
    require(allSubmitted, "Not all members have submitted rankings");

        uint256 groupSize = group.members.length;
        uint256[] memory transientScores = new uint256[](groupSize);

        for (uint256 i = 0; i < groupSize; i++) {
            transientScores[i] = calculateTransientScore(_communityId, _weekNumber, _groupId, i, group);
            emit DebugLog("Transient score for member", transientScores[i]);
        }

        uint256[] memory consensusRanking = sortByScore(transientScores);
        consensusRankings[_communityId][_weekNumber][_groupId] = ConsensusRanking(consensusRanking, transientScores, block.timestamp);
        emit ConsensusReached(_communityId, _weekNumber, _groupId, consensusRanking);

   console.log("Issuing RESPECT tokens for group %s", _groupId);
    issueRespectTokens(_communityId, _weekNumber, _groupId, group);
    }



    function fib(uint8 n) internal pure returns (uint256) {
        if (n <= 1) return n;
        uint256 a = 0;
        uint256 b = 1;
        for (uint8 i = 2; i <= n; i++) {
            uint256 c = a + b;
            a = b;
            b = c;
        }
        return b;
    }

    function distributeRespect(uint256 totalRespect, uint256[][] memory groupRankings) internal pure returns (uint256[] memory) {
        uint256 totalParticipants = 0;
        for (uint256 i = 0; i < groupRankings.length; i++) {
            totalParticipants += groupRankings[i].length;
        }
        
        uint256[] memory distribution = new uint256[](totalParticipants);
        uint256 totalWeight = 0;
        uint256 currentIndex = 0;

        for (uint256 i = 0; i < groupRankings.length; i++) {
            for (uint256 j = 0; j < groupRankings[i].length; j++) {
                uint256 weight = fib(uint8(6 - j)); // 6 is used as the starting point, adjust if needed
                totalWeight += weight;
                distribution[currentIndex] = weight;
                currentIndex++;
            }
        }

        for (uint256 i = 0; i < distribution.length; i++) {
            distribution[i] = (distribution[i] * totalRespect) / totalWeight;
        }

        return distribution;
    }




    function determineConsensusForAllGroups(uint256 _communityId, uint256 _weekNumber) external {
        uint256 totalRespectToDistribute = profilesContract.getRespectToDistribute(_communityId);
        ICommunityGovernanceContributions.Group[] memory groups = contributionsContract.getGroupsForWeek(_communityId, _weekNumber);
        
        uint256[][] memory allGroupRankings = new uint256[][](groups.length);
        
        for (uint256 i = 0; i < groups.length; i++) {
            determineConsensus(_communityId, _weekNumber, i);
            ConsensusRanking storage consensusRanking = consensusRankings[_communityId][_weekNumber][i];
            allGroupRankings[i] = consensusRanking.rankedScores;
        }
        
        uint256[] memory distribution = distributeRespect(totalRespectToDistribute, allGroupRankings);
        
        uint256 currentIndex = 0;
        for (uint256 i = 0; i < groups.length; i++) {
            for (uint256 j = 0; j < groups[i].members.length; j++) {
                address member = groups[i].members[j];
                uint256 respectAmount = distribution[currentIndex];
                
                // Update claimable tokens
                userClaimableTokens[_communityId][member].amount += respectAmount;
                
                // Update respect data in contributions contract
                contributionsContract.updateRespectData(_communityId, member, _weekNumber, respectAmount);
                
                emit RespectIssued(_communityId, _weekNumber, i, member, respectAmount);
                currentIndex++;
            }
        }
    }

    function calculateTransientScore(uint256 _communityId, uint256 _weekNumber, uint256 _groupId, uint256 memberIndex, ICommunityGovernanceContributions.Group memory group) private view returns (uint256) {
        uint256[] memory memberRankings = new uint256[](group.members.length);
        for (uint256 i = 0; i < group.members.length; i++) {
            memberRankings[i] = rankings[_communityId][_weekNumber][_groupId][group.members[i]].rankedScores[memberIndex];
        }

        uint256 meanRanking = calculateMean(memberRankings);
        uint256 variance = calculateVariance(memberRankings);
        uint256 maxVariance = calculateMaxVariance(group.members.length);

        uint256 consensusTerm;
        if (maxVariance == 0) {
            consensusTerm = SCALE;
        } else {
            consensusTerm = SCALE - ((variance * SCALE) / maxVariance);
        }

        return (meanRanking * consensusTerm) / SCALE;
    }

    function calculateMean(uint256[] memory values) private pure returns (uint256) {
        uint256 sum = 0;
        for (uint256 i = 0; i < values.length; i++) {
            sum += values[i];
        }
        return (sum * SCALE) / values.length;
    }

    function calculateVariance(uint256[] memory values) private pure returns (uint256) {
        uint256 mean = calculateMean(values);
        uint256 sumSquaredDiff = 0;
        for (uint256 i = 0; i < values.length; i++) {
            int256 diff = int256(values[i] * SCALE) - int256(mean);
            sumSquaredDiff += uint256(diff * diff) / SCALE;
        }
        return sumSquaredDiff / values.length;
    }

    function calculateMaxVariance(uint256 groupSize) private pure returns (uint256) {
        uint256 sum = 0;
        for (uint256 x = 1; x < groupSize; x++) {
            sum += x * SCALE / 2;
        }
        return (groupSize * sum) / (groupSize - 1);
    }

    function sortByScore(uint256[] memory _scores) private pure returns (uint256[] memory) {
        uint256[] memory indices = new uint256[](_scores.length);
        for (uint256 i = 0; i < indices.length; i++) {
            indices[i] = i;
        }

        for (uint256 i = 0; i < _scores.length - 1; i++) {
            for (uint256 j = i + 1; j < _scores.length; j++) {
                if (_scores[indices[i]] < _scores[indices[j]]) {
                    (indices[i], indices[j]) = (indices[j], indices[i]);
                }
            }
        }

        uint256[] memory finalRanking = new uint256[](_scores.length);
        for (uint256 i = 0; i < finalRanking.length; i++) {
            finalRanking[indices[i]] = _scores.length - i;
        }

        return finalRanking;
    }

    function isPartOfGroup(ICommunityGovernanceContributions.Group memory group, address _member) private pure returns (bool) {
        for (uint256 i = 0; i < group.members.length; i++) {
            if (group.members[i] == _member) return true;
        }
        return false;
    }

    function allMembersSubmitted(uint256 _communityId, uint256 _weekNumber, uint256 _groupId, ICommunityGovernanceContributions.Group memory group) private view returns (bool) {
        for (uint256 i = 0; i < group.members.length; i++) {
            if (rankings[_communityId][_weekNumber][_groupId][group.members[i]].rankedScores.length == 0) {
                return false;
            }
        }
        return true;
    }

   function issueRespectTokens(uint256 _communityId, uint256 _weekNumber, uint256 _groupId, ICommunityGovernanceContributions.Group memory group) private {
        uint256[] memory ranking = consensusRankings[_communityId][_weekNumber][_groupId].rankedScores;
        uint256 membersCount = group.members.length;

        require(ranking.length == membersCount, "Ranking length mismatch");

        for (uint256 i = 0; i < membersCount && i < respectValues.length; i++) {
            require(ranking[i] > 0 && ranking[i] <= membersCount, "Invalid ranking");
            address recipient = group.members[ranking[i] - 1];
            uint256 respectAmount = respectValues[i];

            require(recipient != address(0), "Invalid recipient address");

            // Directly mint tokens instead of calling an external function
            _mint(recipient, _communityId, respectAmount, "");
            contributionsContract.updateRespectData(_communityId, recipient, _weekNumber, respectAmount);
            emit RespectIssued(_communityId, _weekNumber, _groupId, recipient, respectAmount);
        }
    }
    // Getter functions
    function getConsensusRanking(uint256 _communityId, uint256 _weekNumber, uint256 _groupId) public view returns (uint256[] memory rankedScores, uint256[] memory transientScores, uint256 timestamp) {
        ConsensusRanking storage consensusRanking = consensusRankings[_communityId][_weekNumber][_groupId];
        return (consensusRanking.rankedScores, consensusRanking.transientScores, consensusRanking.timestamp);
    }

    function getRanking(uint256 _communityId, uint256 _weekNumber, uint256 _groupId, address _user) public view returns (uint256[] memory) {
        return rankings[_communityId][_weekNumber][_groupId][_user].rankedScores;
    }

    function getTransientScores(uint256 _communityId, uint256 _weekNumber, uint256 _groupId) public view returns (address[] memory, uint256[] memory) {
        ICommunityGovernanceContributions.Group[] memory groups = contributionsContract.getGroupsForWeek(_communityId, _weekNumber);
        require(_groupId < groups.length, "Invalid group ID");
        ICommunityGovernanceContributions.Group memory group = groups[_groupId];
        uint256 groupSize = group.members.length;
        address[] memory members = new address[](groupSize);
        uint256[] memory scores = new uint256[](groupSize);

        for (uint256 i = 0; i < groupSize; i++) {
            members[i] = group.members[i];
            scores[i] = calculateTransientScore(_communityId, _weekNumber, _groupId, i, group);
        }

        return (members, scores);
    }

    function claimTokens(uint256 _communityId) external {
        ClaimableTokens storage claimable = userClaimableTokens[_communityId][msg.sender];
        require(claimable.amount > 0, "No tokens to claim");
        require(!claimable.claimed, "Tokens already claimed");

        // Here you would typically transfer the tokens to the user
        // For this example, we'll just mark them as claimed
        claimable.claimed = true;

        emit TokensClaimed(_communityId, msg.sender, claimable.amount);
    }

    function getClaimableTokens(uint256 _communityId, address _user) external view returns (uint256 amount, bool claimed) {
        ClaimableTokens storage claimable = userClaimableTokens[_communityId][_user];
        return (claimable.amount, claimable.claimed);
    }


}
