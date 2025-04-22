solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract DAO is AccessControl, Pausable {
    using SafeMath for uint256;

    // Roles
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    // Token Addresses
    IERC20 public growToken;
    address public growStakingContract;

    // Proposal Structure
    struct Proposal {
        address proposer;
        string description;
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
        uint256 startTime;
        uint256 endTime;
        uint256 quorum;
        uint256 yesVotes;
        uint256 noVotes;
        bool executed;
        bool passed;
    }

    // Proposal State
    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed
    }

    // Proposal Quorum
    uint256 public constant PROPOSAL_QUORUM_PRECISION = 1000;
    uint256 public proposalQuorum; // e.g., 100 for 10%

    // Voting Delay and Period
    uint256 public constant VOTING_DELAY = 1 days;
    uint256 public votingPeriod = 7 days;

    // Proposal Counter
    uint256 public proposalCount;

    // Proposals
    mapping(uint256 => Proposal) public proposals;

    // Votes
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    mapping(uint256 => mapping(address => uint256)) public voterVotes;

    // Events
    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, string description);
    event Voted(uint256 indexed proposalId, address indexed voter, uint256 votes);
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalCanceled(uint256 indexed proposalId);

    constructor(address _growTokenAddress, address _growStakingContractAddress) {
        require(_growTokenAddress != address(0), "GROW Token address is the zero address");
        require(_growStakingContractAddress != address(0), "GROW Staking contract address is the zero address");
        growToken = IERC20(_growTokenAddress);
        growStakingContract = _growStakingContractAddress;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(EXECUTOR_ROLE, msg.sender);

        // Set default proposal quorum
        proposalQuorum = 100; // 10%
    }

    // Function to create a new proposal
    function createProposal(
        string memory description,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas
    ) external whenNotPaused {
        require(targets.length == values.length && targets.length == calldatas.length, "Invalid proposal parameters");
        uint256 id = ++proposalCount;
        proposals[id] = Proposal({
            proposer: msg.sender,
            description: description,
            targets: targets,
            values: values,
            calldatas: calldatas,
            startTime: block.timestamp.add(VOTING_DELAY),
            endTime: block.timestamp.add(VOTING_DELAY).add(votingPeriod),
            quorum: _getQuorum(),
            yesVotes: 0,
            noVotes: 0,
            executed: false,
            passed: false
        });
        emit ProposalCreated(id, msg.sender, description);
    }

    // Function to vote on a proposal
    function vote(uint256 proposalId, uint256 votes) external whenNotPaused {
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp >= proposal.startTime, "Voting has not started");
        require(block.timestamp <= proposal.endTime, "Voting has ended");
        require(!hasVoted[proposalId][msg.sender], "You have already voted on this proposal");
        require(votes == 0 || votes ==1, "You can only vote yes or no.");

        uint256 votingPower = _getVotingPower(msg.sender);
        require(votingPower > 0, "You have no voting power");

        hasVoted[proposalId][msg.sender] = true;
        voterVotes[proposalId][msg.sender] = votingPower;

        if(votes >0) {
             proposal.yesVotes = proposal.yesVotes.add(votingPower);
        } else {
             proposal.noVotes = proposal.noVotes.add(votingPower);
        }
       
        emit Voted(proposalId, msg.sender, votes);
    }

    // Function to execute a proposal
    function executeProposal(uint256 proposalId) external onlyRole(EXECUTOR_ROLE) whenNotPaused {
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp > proposal.endTime, "Voting is still active");
        require(getState(proposalId) == ProposalState.Succeeded, "Proposal did not pass");
        require(!proposal.executed, "Proposal has already been executed");

        proposal.executed = true;

        for (uint256 i = 0; i < proposal.targets.length; i++) {
            (bool success, ) = proposal.targets[i].call{value: proposal.values[i]}(proposal.calldatas[i]);
            require(success, "Proposal execution failed");
        }

        emit ProposalExecuted(proposalId);
    }

    function cancelProposal(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];
        require(msg.sender == proposal.proposer || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Only proposer or admin can cancel");
        require(getState(proposalId) == ProposalState.Pending || getState(proposalId) == ProposalState.Active, "Proposal cannot be canceled");
        proposals[proposalId].endTime = 0;
        emit ProposalCanceled(proposalId);
    }

    // Function to get the voting power of a user
    function _getVotingPower(address user) internal view returns (uint256) {
        // Get voting power from growStakingContract
        (bool success, bytes memory data) = growStakingContract.staticcall(abi.encodeWithSignature("getTotalStaked(address)", user));
        if (success) {
        return abi.decode(data, (uint256));
        } else {
        return 0;
        }
    }

    // Function to get the current state of a proposal
    function getState(uint256 proposalId) public view returns (ProposalState) {
        Proposal storage proposal = proposals[proposalId];

        if (proposal.endTime == 0) {
            return ProposalState.Canceled;
        } else if (block.timestamp <= proposal.startTime) {
            return ProposalState.Pending;
        } else if (block.timestamp <= proposal.endTime) {
            return ProposalState.Active;
        } else if (proposal.yesVotes <= proposal.noVotes || proposal.yesVotes < proposal.quorum) {
            return ProposalState.Defeated;
        } else if (proposal.executed) {
            return ProposalState.Executed;
        } else {
             return ProposalState.Succeeded;
        }
    }

    // Function to get the quorum
    function _getQuorum() internal view returns (uint256) {
        // Calculate quorum based on total staked GROW tokens
        (bool success, bytes memory data) = growStakingContract.staticcall(abi.encodeWithSignature("getTotalStakedToken()"));
        uint256 totalStaked;
        if (success) {
            totalStaked = abi.decode(data, (uint256));
        } else {
           totalStaked = 0;
        }
        return totalStaked.mul(proposalQuorum).div(PROPOSAL_QUORUM_PRECISION);
    }

    // Function to update the quorum
     function updateQuorum(uint256 newQuorum) external onlyRole(DEFAULT_ADMIN_ROLE){
        proposalQuorum = newQuorum;
    }

    // Function to update the voting period
    function updateVotingPeriod(uint256 newVotingPeriod) external onlyRole(DEFAULT_ADMIN_ROLE) {
        votingPeriod = newVotingPeriod;
    }

    // Function to pause the contract
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    // Function to unpause the contract
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}
