// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interfaces/ICommunityGovernanceProfiles.sol";
import "./CommunityGovernanceProfilesStorage.sol";
import "./interfaces/ICommunityGovernanceRankings.sol";
import "./interfaces/ICommunityGovernanceContributions.sol";
import "./interfaces/ICommunityGovernanceMultiSig.sol";
import "./CommunityToken.sol";

contract CommunityGovernanceProfilesImplementation is 
    ICommunityGovernanceProfiles, 
    CommunityGovernanceProfilesStorage, 
    Initializable, 
    OwnableUpgradeable 
{    function initialize(address initialOwner) public initializer {
        __Ownable_init(initialOwner);
        if (nextCommunityId == 0) {
            nextCommunityId = 1;
        }
    }

    function setRankingsContract(address _rankingsContractAddress) external onlyOwner {
        rankingsContract = ICommunityGovernanceRankings(_rankingsContractAddress);
    }

    function setContributionsContract(address _contributionsContractAddress) external onlyOwner {
        contributionsContract = ICommunityGovernanceContributions(_contributionsContractAddress);
    }

    function setMultiSigContract(address _multiSigContractAddress) external onlyOwner {
        multiSigContract = ICommunityGovernanceMultiSig(_multiSigContractAddress);
    }

    function createCommunity(string memory _name, string memory _description, string memory _imageUrl, string memory _tokenName, string memory _tokenSymbol) external  returns (uint256) {
        if (bytes(users[msg.sender].username).length == 0) {
            UserProfile storage newUser = users[msg.sender];
            newUser.username = "First";
            newUser.description = "Creator of community";
            newUser.profilePicUrl = "";
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

        CommunityToken newToken = new CommunityToken(_tokenName, _tokenSymbol, address(this));
        newCommunity.tokenContractAddress = address(newToken);
        newCommunity.respectToDistribute = 1000;

        nextCommunityId++;

        CommunityData storage creatorCommunityData = users[msg.sender].communityData[newCommunityId];
        creatorCommunityData.communityId = newCommunityId;
        creatorCommunityData.isApproved = true;

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

    function createProfileAndJoinCommunity(string memory _username, string memory _description, string memory _profilePicUrl, uint256 _communityId) public {
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
        } 
        
        else {
            community.state = CommunityState.ContributionSubmission;
           community.eventCount++;
            rankingsContract.determineConsensusForAllGroups(_communityId, community.eventCount - 1);
            contributionsContract.updateAllUsersRespectData(_communityId);
            multiSigContract.updateTopRespectedUsers(_communityId, community.members);
        }

        //community.nextStateTransitionTime = block.timestamp + 1 weeks;
        emit CommunityStateChanged(_communityId, community.state);
        
    }

    function getCommunityMembers(uint256 _communityId) public view returns (address[] memory memberAddresses, string[] memory memberUsernames) {
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

    function getRespectToDistribute(uint256 _communityId) public view override returns (uint256) {
        require(_communityId > 0 && _communityId < nextCommunityId, "Invalid community ID");
        return communities[_communityId].respectToDistribute;
    }

    function getUserProfile(address _user) public view override returns (string memory, string memory, string memory) {
        require(bytes(users[_user].username).length > 0, "Profile does not exist");
        UserProfile storage user = users[_user];
        return (user.username, user.description, user.profilePicUrl);
    }

    function getUserCommunityData(address _user, uint256 _communityId) public view override returns (uint256, bool, address[] memory) {
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

    function removeMemberFromCommunity(uint256 _communityId, address _member) external {
        require(msg.sender == address(multiSigContract), "Only MultiSig contract can call this function");
        Community storage community = communities[_communityId];
        
        for (uint256 i = 0; i < community.members.length; i++) {
            if (community.members[i] == _member) {
                community.members[i] = community.members[community.members.length - 1];
                community.members.pop();
                community.memberCount--;
                delete users[_member].communityData[_communityId];
                break;
            }
        }
    }

}