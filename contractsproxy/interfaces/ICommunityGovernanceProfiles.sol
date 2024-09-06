// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICommunityGovernanceProfiles {
    enum CommunityState { ContributionSubmission, ContributionRanking }

    event ProfileCreated(address indexed user, string username, bool isNewProfile);
    event CommunityJoined(address indexed user, uint256 indexed communityId, bool isApproved);
    event UserApproved(address indexed user, uint256 indexed communityId, address indexed approver);
    event CommunityCreated(uint256 indexed communityId, string name, address indexed creator, address tokenAddress);
    event CommunityStateChanged(uint256 indexed communityId, CommunityState newState);
    event RespectToDistributeChanged(uint256 indexed communityId, uint256 newAmount);
    event MemberRemoved(uint256 indexed communityId, address removedMember);
    event TokensMinted(uint256 indexed communityId, uint256 amount);

     function removeMemberFromCommunity(uint256 _communityId, address _member) external;
     function getRespectToDistribute(uint256 _communityId) external view returns (uint256);
     //function setRespectToDistribute(uint256 _communityId, uint256 _amount) external;
     function getUserProfile(address _user) external view returns (string memory username, string memory description, string memory profilePicUrl);
     function getUserCommunityData(address _user, uint256 _communityId) external view returns (uint256 communityId, bool isApproved, address[] memory approvers);
     function getCommunityProfile(uint256 _communityId) external view returns (
        string memory name,
        string memory description,
        string memory imageUrl,
        address creator,
        uint256 memberCount,
        CommunityState state,
        uint256 eventCount,
        address tokenContractAddress
    );
    function getCommunityMembers(uint256 _communityId) external view returns (address[] memory memberAddresses, string[] memory memberUsernames);
     //function removeMember(uint256 _communityId, address _member) external;
     //function mintTokens(uint256 _communityId, uint256 _amount) external;
}