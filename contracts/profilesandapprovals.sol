// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "hardhat/console.sol";
import "./CommunityToken.sol"; // Import the new CommunityToken contract

interface ICommunityGovernanceProfiles {
    enum CommunityState { ContributionSubmission, ContributionRanking }

    function getUserProfile(address _user) external view returns (string memory, string memory, string memory);
    function getUserCommunityData(address _user, uint256 _communityId) external view returns (uint256, bool, address[] memory);
    function getCommunityProfile(uint256 _communityId) external view returns (string memory, string memory, string memory, address, uint256, CommunityState, uint256, address);
}
// Add this interface at the top of the file
interface ICommunityGovernanceContributions {
    function createGroupsForCurrentWeek(uint256 _communityId) external;
    function getWeeklyContributors(uint256 _communityId, uint256 _week) external view returns (address[] memory);

}

interface ICommunityGovernanceRankings {
    function determineConsensusForAllGroups(uint256 _communityId, uint256 _weekNumber) external;
}

contract CommunityGovernanceProfiles is ICommunityGovernanceProfiles, Ownable {

    ICommunityGovernanceRankings public rankingsContract;
    ICommunityGovernanceContributions public contributionsContract;

    constructor() Ownable(msg.sender) {}

    function setRankingsContract(address _rankingsContractAddress) public onlyOwner {
        rankingsContract = ICommunityGovernanceRankings(_rankingsContractAddress);
    }

    // Add this function to set the contributions contract address
    function setContributionsContract(address _contributionsContractAddress) public onlyOwner {
        contributionsContract = ICommunityGovernanceContributions(_contributionsContractAddress);
    }


    struct CommunityData {
        uint256 communityId;
        bool isApproved;
        address[] approvers;
    }

    struct UserProfile {
        string username;
        string description;
        string profilePicUrl;
        mapping(uint256 => CommunityData) communityData;
    }

    struct Community {
        string name;
        string description;
        string imageUrl;
        address creator;
        uint256 memberCount;
        address[] members;
        CommunityState state;
        uint256 eventCount;
        uint256 nextStateTransitionTime;
        address tokenContractAddress;
        uint256 respectToDistribute;
    }

    mapping(address => UserProfile) public users;
    mapping(uint256 => Community) public communities;
    uint256 public nextCommunityId = 1;

    event ProfileCreated(address indexed user, string username, bool isNewProfile);
    event CommunityJoined(address indexed user, uint256 indexed communityId, bool isApproved);
    event UserApproved(address indexed user, uint256 indexed communityId, address indexed approver);
    event CommunityCreated(uint256 indexed communityId, string name, address indexed creator, address tokenAddress);
    event CommunityStateChanged(uint256 indexed communityId, CommunityState newState);

    function createCommunity(string memory _name, string memory _description, string memory _imageUrl, string memory _tokenName, string memory _tokenSymbol) public returns (uint256) {
        if (bytes(users[msg.sender].username).length == 0) {
            UserProfile storage newUser = users[msg.sender];
            newUser.username = "First";
            newUser.description = "Creator of community";
            newUser.profilePicUrl = ""; // Empty profile picture
            emit ProfileCreated(msg.sender, newUser.username, true);
        }

        uint256 newCommunityId = nextCommunityId;
        Community storage newCommunity = communities[newCommunityId];

        newCommunity.name = _name;
        newCommunity.description = _description;
        newCommunity.imageUrl = _imageUrl;
        newCommunity.creator = msg.sender;
        newCommunity.memberCount = 1;
        newCommunity.members.push(msg.sender);
        newCommunity.eventCount = 0;
        newCommunity.state = CommunityState.ContributionSubmission;
        newCommunity.nextStateTransitionTime = block.timestamp + 1 weeks;

        // Create a new ERC20 token for the community
        CommunityToken newToken = new CommunityToken(_tokenName, _tokenSymbol, address(rankingsContract));
        newCommunity.tokenContractAddress = address(newToken);
        newCommunity.respectToDistribute = 0;

        nextCommunityId++;

        CommunityData storage creatorCommunityData = users[msg.sender].communityData[newCommunityId];
        creatorCommunityData.communityId = newCommunityId;
        creatorCommunityData.isApproved = true; // Creator is automatically approved

        emit CommunityCreated(newCommunityId, _name, msg.sender, address(newToken));
        emit CommunityJoined(msg.sender, newCommunityId, true);

        return newCommunityId;
    }


    function approveUser(address _user, uint256 _communityId) public {
        require(bytes(users[msg.sender].username).length > 0, "Approver profile does not exist");
        require(bytes(users[_user].username).length > 0, "User profile to approve does not exist");
        require(communities[_communityId].memberCount > 5, "Approval not required for first 5 members");

        CommunityData storage approverData = users[msg.sender].communityData[_communityId];
        require(approverData.communityId != 0, "Approver not part of this community");
        require(approverData.isApproved, "Approver must be an approved member of the community");

        CommunityData storage userData = users[_user].communityData[_communityId];
        require(userData.communityId != 0, "User not part of this community");
        require(!userData.isApproved, "User already approved");
        require(userData.approvers.length < 2, "User already has 2 approvals");

        for (uint i = 0; i < userData.approvers.length; i++) {
            require(userData.approvers[i] != msg.sender, "Approver has already approved this user");
        }

        userData.approvers.push(msg.sender);

        if (userData.approvers.length == 2) {
            userData.isApproved = true;
        }

        emit UserApproved(_user, _communityId, msg.sender);
    }
   
    function createProfileAndJoinCommunity(
        string memory _username,
        string memory _description,
        string memory _profilePicUrl,
        uint256 _communityId
    ) public {
        require(_communityId > 0 && _communityId < nextCommunityId, "Invalid community ID");

        UserProfile storage user = users[msg.sender];
        bool isNewProfile = bytes(user.username).length == 0;

        if (isNewProfile) {
            user.username = _username;
            user.description = _description;
            user.profilePicUrl = _profilePicUrl;
        }

        require(user.communityData[_communityId].communityId == 0, "Already joined this community");

        Community storage community = communities[_communityId];
        bool isApproved = community.memberCount < 26;

        CommunityData storage newCommunityData = user.communityData[_communityId];
        newCommunityData.communityId = _communityId;
        newCommunityData.isApproved = isApproved;

        community.memberCount++;
        community.members.push(msg.sender);

        emit ProfileCreated(msg.sender, _username, isNewProfile);
        emit CommunityJoined(msg.sender, _communityId, isApproved);
    }
       function changeState(uint256 _communityId) public {
        Community storage community = communities[_communityId];
        require(community.creator != address(0), "Community does not exist");
        require(msg.sender == community.creator || msg.sender == owner(), "Not authorized to change state");

        if (community.state == CommunityState.ContributionSubmission) {
            community.state = CommunityState.ContributionRanking;
            address[] memory contributors = contributionsContract.getWeeklyContributors(_communityId, community.eventCount);
            require(contributors.length > 0, "No contributors for this week");
            contributionsContract.createGroupsForCurrentWeek(_communityId);
        } else {
            community.state = CommunityState.ContributionSubmission;
            community.eventCount++;
            rankingsContract.determineConsensusForAllGroups(_communityId, community.eventCount - 1);
        }

        community.nextStateTransitionTime = block.timestamp + 1 weeks;
        emit CommunityStateChanged(_communityId, community.state);
    }
    function getCommunityMembers(uint256 _communityId) public view returns (
        address[] memory memberAddresses,
        string[] memory memberUsernames
    ) {
        require(_communityId > 0 && _communityId < nextCommunityId, "Invalid community ID");

        Community storage community = communities[_communityId];
        uint256 memberCount = community.memberCount;

        memberAddresses = new address[](memberCount);
        memberUsernames = new string[](memberCount);

        for (uint256 i = 0; i < memberCount; i++) {
            address memberAddress = community.members[i];
            UserProfile storage user = users[memberAddress];

            memberAddresses[i] = memberAddress;
            memberUsernames[i] = user.username;
        }
    }

    function getRespectToDistribute(uint256 _communityId) public view returns (uint256) {
        require(_communityId > 0 && _communityId < nextCommunityId, "Invalid community ID");
        return communities[_communityId].respectToDistribute;
    }

    function setRespectToDistribute(uint256 _communityId, uint256 _amount) public onlyOwner {
        require(_communityId > 0 && _communityId < nextCommunityId, "Invalid community ID");
        communities[_communityId].respectToDistribute = _amount;
    }

    function getUserProfile(address _user) public view returns (string memory, string memory, string memory) {
        require(bytes(users[_user].username).length > 0, "Profile does not exist");
        UserProfile storage user = users[_user];
        return (user.username, user.description, user.profilePicUrl);
    }

    function getUserCommunityData(address _user, uint256 _communityId) public view returns (uint256, bool, address[] memory) {
        require(bytes(users[_user].username).length > 0, "Profile does not exist");
        CommunityData storage communityData = users[_user].communityData[_communityId];
        require(communityData.communityId != 0, "User not part of this community");
        return (communityData.communityId, communityData.isApproved, communityData.approvers);
    }
    function getCommunityProfile(uint256 _communityId) public view override returns (
        string memory,
        string memory,
        string memory,
        address,
        uint256,
        CommunityState,
        uint256,
        address
    ) {
        require(_communityId > 0 && _communityId < nextCommunityId, "Invalid community ID");
        Community storage community = communities[_communityId];
        return (
            community.name,
            community.description,
            community.imageUrl,
            community.creator,
            community.memberCount,
            community.state,
            community.eventCount,
            community.tokenContractAddress
        );
    }
    }

