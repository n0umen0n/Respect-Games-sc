// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

interface ICommunityGovernanceProfiles {
    enum CommunityState { ContributionSubmission, ContributionRanking }

    function removeMember(uint256 _communityId, address _member) external;
    function setRespectToDistribute(uint256 _communityId, uint256 _amount) external;
    function mintTokens(uint256 _communityId, uint256 _amount) external;
    function getUserProfile(address _user) external view returns (string memory, string memory, string memory);
    function getUserCommunityData(address _user, uint256 _communityId) external view returns (uint256, bool, address[] memory);
    function getCommunityProfile(uint256 _communityId) external view returns (string memory, string memory, string memory, address, uint256, CommunityState, uint256, address);
    function getRespectToDistribute(uint256 _communityId) external view returns (uint256);
}

interface ICommunityGovernanceContributions {
    function getAverageRespect(address _user, uint256 _communityId) external view returns (uint256);
        function createGroupsForCurrentWeek(uint256 _communityId) external;
    function getWeeklyContributors(uint256 _communityId, uint256 _week) external view returns (address[] memory);
}

contract CommunityGovernanceMultiSig is Ownable {
    ICommunityGovernanceProfiles public profilesContract;
    ICommunityGovernanceContributions public contributionsContract;

    constructor() Ownable(msg.sender) {}

    struct MultiSigInfo {
        address[5] topRespectedUsers;
        mapping(uint256 => MultiSigProposal) proposals;
    }

    struct MultiSigProposal {
        ProposalType proposalType;
        uint256 value;
        address targetMember;
        uint256 signatureCount;
        mapping(address => bool) hasSignedProposal;
        bool executed;
    }

    enum ProposalType { RemoveMember, SetRespectToDistribute, MintTokens }

    mapping(uint256 => MultiSigInfo) private communityMultiSigs;

    event TopRespectedUsersUpdated(uint256 indexed communityId, address[5] topUsers);
    event ProposalCreated(uint256 indexed communityId, uint256 indexed proposalId, ProposalType proposalType);
    event ProposalSigned(uint256 indexed communityId, uint256 indexed proposalId, address signer);
    event ProposalExecuted(uint256 indexed communityId, uint256 indexed proposalId);

    function setProfilesContract(address _profilesContractAddress) public onlyOwner {
        profilesContract = ICommunityGovernanceProfiles(_profilesContractAddress);
    }

    function setContributionsContract(address _contributionsContractAddress) public onlyOwner {
        contributionsContract = ICommunityGovernanceContributions(_contributionsContractAddress);
    }

    function updateTopRespectedUsers(uint256 _communityId, address[] memory allMembers) public onlyOwner {
        require(allMembers.length > 0, "Community must have members");

        uint256[] memory respectScores = new uint256[](allMembers.length);

        for (uint256 i = 0; i < allMembers.length; i++) {
            respectScores[i] = contributionsContract.getAverageRespect(allMembers[i], _communityId);
        }

        address[5] memory topUsers;
        for (uint256 i = 0; i < 5 && i < allMembers.length; i++) {
            uint256 maxIndex = i;
            for (uint256 j = i + 1; j < allMembers.length; j++) {
                if (respectScores[j] > respectScores[maxIndex]) {
                    maxIndex = j;
                }
            }
            if (maxIndex != i) {
                (allMembers[i], allMembers[maxIndex]) = (allMembers[maxIndex], allMembers[i]);
                (respectScores[i], respectScores[maxIndex]) = (respectScores[maxIndex], respectScores[i]);
            }
            topUsers[i] = allMembers[i];
        }

        communityMultiSigs[_communityId].topRespectedUsers = topUsers;
        emit TopRespectedUsersUpdated(_communityId, topUsers);
    }

    function createProposal(uint256 _communityId, uint256 _proposalId, ProposalType _type, uint256 _value, address _targetMember) public {
        require(isTopRespectedUser(msg.sender, communityMultiSigs[_communityId].topRespectedUsers), "Not authorized");
        require(communityMultiSigs[_communityId].proposals[_proposalId].signatureCount == 0, "Proposal ID already exists");
        
        MultiSigProposal storage proposal = communityMultiSigs[_communityId].proposals[_proposalId];
        
        proposal.proposalType = _type;
        proposal.value = _value;
        proposal.targetMember = _targetMember;
        proposal.signatureCount = 1;
        proposal.hasSignedProposal[msg.sender] = true;
        
        emit ProposalCreated(_communityId, _proposalId, _type);
    }

    function signProposal(uint256 _communityId, uint256 _proposalId) public {
        require(isTopRespectedUser(msg.sender, communityMultiSigs[_communityId].topRespectedUsers), "Not authorized");
        
        MultiSigProposal storage proposal = communityMultiSigs[_communityId].proposals[_proposalId];
        require(proposal.signatureCount > 0, "Proposal does not exist");
        require(!proposal.executed, "Proposal already executed");
        require(!proposal.hasSignedProposal[msg.sender], "Already signed");
        
        proposal.hasSignedProposal[msg.sender] = true;
        proposal.signatureCount++;
        
        emit ProposalSigned(_communityId, _proposalId, msg.sender);
        
        if (proposal.signatureCount >= 3) {
            executeProposal(_communityId, _proposalId);
        }
    }

    function executeProposal(uint256 _communityId, uint256 _proposalId) internal {
        MultiSigProposal storage proposal = communityMultiSigs[_communityId].proposals[_proposalId];
        require(!proposal.executed, "Proposal already executed");
        require(proposal.signatureCount >= 3, "Not enough signatures");
        
        proposal.executed = true;
        
        if (proposal.proposalType == ProposalType.RemoveMember) {
            profilesContract.removeMember(_communityId, proposal.targetMember);
        } else if (proposal.proposalType == ProposalType.SetRespectToDistribute) {
            profilesContract.setRespectToDistribute(_communityId, proposal.value);
        } else if (proposal.proposalType == ProposalType.MintTokens) {
            profilesContract.mintTokens(_communityId, proposal.value);
        }
        
        emit ProposalExecuted(_communityId, _proposalId);
    }

    function isTopRespectedUser(address _user, address[5] memory _topUsers) internal pure returns (bool) {
        for (uint256 i = 0; i < 5; i++) {
            if (_topUsers[i] == _user) {
                return true;
            }
        }
        return false;
    }

    function getTopRespectedUsers(uint256 _communityId) public view returns (address[5] memory) {
        return communityMultiSigs[_communityId].topRespectedUsers;
    }

    function getProposal(uint256 _communityId, uint256 _proposalId) public view returns (
        ProposalType proposalType,
        uint256 value,
        address targetMember,
        uint256 signatureCount,
        bool executed
    ) {
        MultiSigProposal storage proposal = communityMultiSigs[_communityId].proposals[_proposalId];
        return (
            proposal.proposalType,
            proposal.value,
            proposal.targetMember,
            proposal.signatureCount,
            proposal.executed
        );
    }

    function hasSignedProposal(uint256 _communityId, uint256 _proposalId, address _signer) public view returns (bool) {
        return communityMultiSigs[_communityId].proposals[_proposalId].hasSignedProposal[_signer];
    }
}