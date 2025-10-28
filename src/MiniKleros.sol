// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IArbitrable
 * @dev Interface for contracts that can be arbitrated by MiniKleros
 */
interface IArbitrable {
    function rule(uint256 _disputeID, uint256 _ruling) external;
}

/**
 * @title MiniKleros
 * @dev A simplified Kleros-style decentralized arbitration system
 */
contract MiniKleros {
    // State of a dispute
    enum DisputeState {
        Committing,
        Revealing,
        Resolved
    }

    // Dispute structure
    struct Dispute {
        DisputeState state;
        IArbitrable arbitrable;
        uint256 choices;
        uint256 arbitrationFee;
        address[] selectedJurors;
        mapping(address => bytes32) commitments;
        mapping(address => uint256) revealedVotes;
        mapping(address => bool) hasRevealed;
        uint256 commitDeadline;
        uint256 revealDeadline;
    }

    IERC20 public pnkToken;
    mapping(address => uint256) public jurorStakes;
    address[] public jurors;
    uint256 public totalStaked;
    mapping(uint256 => Dispute) public disputes;
    uint256 public disputeCount;

    // Constants for penalties and rewards
    uint256 public constant PENALTY_PERCENT = 20; // 20% penalty for minority/no-reveal
    uint256 public constant COMMIT_DURATION = 1 days;
    uint256 public constant REVEAL_DURATION = 1 days;
    uint256 public constant JUROR_COUNT = 3;

    // Events
    event Staked(address indexed juror, uint256 amount);
    event Unstaked(address indexed juror, uint256 amount);
    event DisputeCreated(uint256 indexed disputeID);
    event VoteCommitted(uint256 indexed disputeID, address indexed juror);
    event VoteRevealed(uint256 indexed disputeID, address indexed juror, uint256 choice);
    event DisputeResolved(uint256 indexed disputeID, uint256 ruling);

    constructor(address _pnkToken) {
        pnkToken = IERC20(_pnkToken);
    }

    /**
     * @dev Allows a user to stake PNK tokens to become a juror
     * @param _amount Amount of PNK to stake
     */
    function stake(uint256 _amount) external {
        require(_amount > 0, "Amount must be greater than 0");
        require(pnkToken.transferFrom(msg.sender, address(this), _amount), "Transfer failed");

        if (jurorStakes[msg.sender] == 0) {
            jurors.push(msg.sender);
        }

        jurorStakes[msg.sender] += _amount;
        totalStaked += _amount;

        emit Staked(msg.sender, _amount);
    }

    /**
     * @dev Allows a user to unstake PNK tokens
     * @param _amount Amount of PNK to unstake
     */
    function unstake(uint256 _amount) external {
        require(jurorStakes[msg.sender] >= _amount, "Insufficient staked amount");

        jurorStakes[msg.sender] -= _amount;
        totalStaked -= _amount;

        require(pnkToken.transfer(msg.sender, _amount), "Transfer failed");

        emit Unstaked(msg.sender, _amount);
    }

    /**
     * @dev Creates a new dispute
     * @param _choices Number of choices for the dispute
     * @param _arbitrationFee Fee paid by the arbitrable contract
     * @return disputeID The ID of the created dispute
     */
    function createDispute(uint256 _choices, uint256 _arbitrationFee) external payable returns (uint256 disputeID) {
        require(msg.value == _arbitrationFee, "Incorrect arbitration fee");
        require(totalStaked > 0, "No jurors available");
        require(_choices >= 2, "At least 2 choices required");

        disputeID = disputeCount++;
        Dispute storage dispute = disputes[disputeID];

        dispute.state = DisputeState.Committing;
        dispute.arbitrable = IArbitrable(msg.sender);
        dispute.choices = _choices;
        dispute.arbitrationFee = _arbitrationFee;
        dispute.commitDeadline = block.timestamp + COMMIT_DURATION;
        dispute.revealDeadline = block.timestamp + COMMIT_DURATION + REVEAL_DURATION;

        // Select jurors
        dispute.selectedJurors = _selectJurors();

        emit DisputeCreated(disputeID);
    }

    /**
     * @dev Selects jurors based on weighted random selection
     * @return selectedJurors Array of selected juror addresses
     */
    function _selectJurors() internal view returns (address[] memory selectedJurors) {
        selectedJurors = new address[](JUROR_COUNT);
        bool[] memory isSelected = new bool[](jurors.length);
        
        for (uint256 i = 0; i < JUROR_COUNT; i++) {
            uint256 randomPoint = uint256(keccak256(abi.encodePacked(
                block.prevrandao,
                block.timestamp,
                disputeCount,
                i
            ))) % totalStaked;

            uint256 cumulative = 0;
            for (uint256 j = 0; j < jurors.length; j++) {
                if (!isSelected[j]) {
                    cumulative += jurorStakes[jurors[j]];
                    if (cumulative > randomPoint) {
                        selectedJurors[i] = jurors[j];
                        isSelected[j] = true;
                        break;
                    }
                }
            }
        }
    }

    /**
     * @dev Commits a vote for a dispute
     * @param _disputeID The ID of the dispute
     * @param _commitment The commitment hash (keccak256(abi.encodePacked(_disputeID, _choice, _salt)))
     */
    function commitVote(uint256 _disputeID, bytes32 _commitment) external {
        Dispute storage dispute = disputes[_disputeID];
        require(dispute.state == DisputeState.Committing, "Not in committing phase");
        require(block.timestamp < dispute.commitDeadline, "Commit deadline passed");
        require(_isSelectedJuror(_disputeID, msg.sender), "Not a selected juror");
        require(dispute.commitments[msg.sender] == bytes32(0), "Already committed");

        dispute.commitments[msg.sender] = _commitment;

        emit VoteCommitted(_disputeID, msg.sender);
    }

    /**
     * @dev Reveals a vote for a dispute
     * @param _disputeID The ID of the dispute
     * @param _choice The vote choice
     * @param _salt The salt used in the commitment
     */
    function revealVote(uint256 _disputeID, uint256 _choice, uint256 _salt) external {
        Dispute storage dispute = disputes[_disputeID];
        
        // Update state if commit deadline has passed
        if (block.timestamp >= dispute.commitDeadline && dispute.state == DisputeState.Committing) {
            dispute.state = DisputeState.Revealing;
        }

        require(dispute.state == DisputeState.Revealing, "Not in revealing phase");
        require(block.timestamp >= dispute.commitDeadline, "Commit deadline not passed");
        require(block.timestamp < dispute.revealDeadline, "Reveal deadline passed");
        require(_isSelectedJuror(_disputeID, msg.sender), "Not a selected juror");
        require(!dispute.hasRevealed[msg.sender], "Already revealed");
        require(_choice < dispute.choices, "Invalid choice");

        bytes32 commitment = keccak256(abi.encodePacked(_disputeID, _choice, _salt));
        require(commitment == dispute.commitments[msg.sender], "Invalid reveal");

        dispute.revealedVotes[msg.sender] = _choice;
        dispute.hasRevealed[msg.sender] = true;

        emit VoteRevealed(_disputeID, msg.sender, _choice);
    }

    /**
     * @dev Tallies votes and resolves the dispute
     * @param _disputeID The ID of the dispute
     */
    function tallyVotes(uint256 _disputeID) external {
        Dispute storage dispute = disputes[_disputeID];
        require(block.timestamp >= dispute.revealDeadline, "Reveal deadline not passed");
        require(dispute.state != DisputeState.Resolved, "Already resolved");

        dispute.state = DisputeState.Resolved;

        // Count votes
        uint256[] memory voteCounts = new uint256[](dispute.choices);
        for (uint256 i = 0; i < dispute.selectedJurors.length; i++) {
            address juror = dispute.selectedJurors[i];
            if (dispute.hasRevealed[juror]) {
                uint256 choice = dispute.revealedVotes[juror];
                voteCounts[choice]++;
            }
        }

        // Find majority
        uint256 ruling = 0;
        uint256 maxVotes = 0;
        for (uint256 i = 0; i < dispute.choices; i++) {
            if (voteCounts[i] > maxVotes) {
                maxVotes = voteCounts[i];
                ruling = i;
            }
        }

        // Calculate penalties and rewards
        uint256 totalPenalties = 0;
        address[] memory winners = new address[](JUROR_COUNT);
        uint256 winnerCount = 0;

        for (uint256 i = 0; i < dispute.selectedJurors.length; i++) {
            address juror = dispute.selectedJurors[i];
            
            // Penalize jurors who didn't reveal or voted for minority
            if (!dispute.hasRevealed[juror] || dispute.revealedVotes[juror] != ruling) {
                uint256 penalty = (jurorStakes[juror] * PENALTY_PERCENT) / 100;
                jurorStakes[juror] -= penalty;
                totalStaked -= penalty;
                totalPenalties += penalty;
            } else {
                // Track winners who voted with majority
                winners[winnerCount++] = juror;
            }
        }

        // Distribute rewards to winners (penalties + arbitration fee)
        if (winnerCount > 0) {
            uint256 totalReward = totalPenalties + dispute.arbitrationFee;
            uint256 rewardPerWinner = totalReward / winnerCount;

            for (uint256 i = 0; i < winnerCount; i++) {
                jurorStakes[winners[i]] += rewardPerWinner;
                totalStaked += rewardPerWinner;
            }
        }

        // Call rule on arbitrable contract
        dispute.arbitrable.rule(_disputeID, ruling);

        emit DisputeResolved(_disputeID, ruling);
    }

    /**
     * @dev Checks if an address is a selected juror for a dispute
     * @param _disputeID The ID of the dispute
     * @param _juror The address to check
     * @return True if the address is a selected juror
     */
    function _isSelectedJuror(uint256 _disputeID, address _juror) internal view returns (bool) {
        Dispute storage dispute = disputes[_disputeID];
        for (uint256 i = 0; i < dispute.selectedJurors.length; i++) {
            if (dispute.selectedJurors[i] == _juror) {
                return true;
            }
        }
        return false;
    }

    /**
     * @dev Gets the selected jurors for a dispute
     * @param _disputeID The ID of the dispute
     * @return The array of selected juror addresses
     */
    function getSelectedJurors(uint256 _disputeID) external view returns (address[] memory) {
        return disputes[_disputeID].selectedJurors;
    }

    /**
     * @dev Gets the state of a dispute
     * @param _disputeID The ID of the dispute
     * @return The state of the dispute
     */
    function getDisputeState(uint256 _disputeID) external view returns (DisputeState) {
        return disputes[_disputeID].state;
    }

    /**
     * @dev Gets the commitment for a juror in a dispute
     * @param _disputeID The ID of the dispute
     * @param _juror The juror address
     * @return The commitment hash
     */
    function getCommitment(uint256 _disputeID, address _juror) external view returns (bytes32) {
        return disputes[_disputeID].commitments[_juror];
    }

    /**
     * @dev Checks if a juror has revealed their vote
     * @param _disputeID The ID of the dispute
     * @param _juror The juror address
     * @return True if the juror has revealed
     */
    function hasRevealed(uint256 _disputeID, address _juror) external view returns (bool) {
        return disputes[_disputeID].hasRevealed[_juror];
    }

    /**
     * @dev Gets the revealed vote for a juror
     * @param _disputeID The ID of the dispute
     * @param _juror The juror address
     * @return The revealed vote choice
     */
    function getRevealedVote(uint256 _disputeID, address _juror) external view returns (uint256) {
        return disputes[_disputeID].revealedVotes[_juror];
    }
}

