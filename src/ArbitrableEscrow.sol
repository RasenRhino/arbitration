// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IArbitrator
 * @dev Interface for the arbitrator contract
 */
interface IArbitrator {
    function createDispute(uint256 _choices, uint256 _arbitrationFee) external payable returns (uint256 disputeID);
}

/**
 * @title ArbitrableEscrow
 * @dev A simple escrow contract that can be arbitrated by MiniKleros
 */
contract ArbitrableEscrow {
    // Parties
    address public buyer;
    address public seller;
    IArbitrator public arbitrator;
    
    // Escrow details
    uint256 public arbitrationFee;
    uint256 public escrowAmount;
    bool public fundsReleased;
    bool public disputeRaised;
    uint256 public disputeID;

    // Ruling choices
    uint256 public constant BUYER_WINS = 0;
    uint256 public constant SELLER_WINS = 1;
    uint256 public constant CHOICES = 2;

    // Events
    event FundsDeposited(address indexed buyer, uint256 amount);
    event FundsReleased(address indexed recipient, uint256 amount);
    event DisputeRaised(uint256 indexed disputeID);
    event Ruled(uint256 indexed disputeID, uint256 ruling);

    // Modifiers
    modifier onlyBuyer() {
        require(msg.sender == buyer, "Only buyer can call");
        _;
    }

    modifier onlyParties() {
        require(msg.sender == buyer || msg.sender == seller, "Only parties can call");
        _;
    }

    modifier onlyArbitrator() {
        require(msg.sender == address(arbitrator), "Only arbitrator can call");
        _;
    }

    /**
     * @dev Constructor
     * @param _arbitrator Address of the MiniKleros arbitrator
     * @param _seller Address of the seller
     * @param _arbitrationFee Fee required to create a dispute
     */
    constructor(
        address _arbitrator,
        address _seller,
        uint256 _arbitrationFee
    ) payable {
        require(_seller != address(0), "Invalid seller address");
        require(_arbitrator != address(0), "Invalid arbitrator address");
        require(msg.value > 0, "Escrow amount must be greater than 0");

        buyer = msg.sender;
        seller = _seller;
        arbitrator = IArbitrator(_arbitrator);
        arbitrationFee = _arbitrationFee;
        escrowAmount = msg.value;

        emit FundsDeposited(buyer, msg.value);
    }

    /**
     * @dev Allows the buyer to release funds to the seller
     */
    function releaseFunds() external onlyBuyer {
        require(!fundsReleased, "Funds already released");
        require(!disputeRaised, "Dispute already raised");

        fundsReleased = true;
        
        (bool success, ) = seller.call{value: escrowAmount}("");
        require(success, "Transfer failed");

        emit FundsReleased(seller, escrowAmount);
    }

    /**
     * @dev Allows either party to raise a dispute
     */
    function raiseDispute() external payable onlyParties {
        require(!fundsReleased, "Funds already released");
        require(!disputeRaised, "Dispute already raised");
        require(msg.value == arbitrationFee, "Incorrect arbitration fee");

        disputeRaised = true;
        disputeID = arbitrator.createDispute{value: arbitrationFee}(CHOICES, arbitrationFee);

        emit DisputeRaised(disputeID);
    }

    /**
     * @dev Callback function called by the arbitrator to enforce the ruling
     * @param _disputeID The ID of the dispute
     * @param _ruling The ruling (0 for buyer wins, 1 for seller wins)
     */
    function rule(uint256 _disputeID, uint256 _ruling) external onlyArbitrator {
        require(_disputeID == disputeID, "Invalid dispute ID");
        require(!fundsReleased, "Funds already released");

        fundsReleased = true;

        address recipient;
        if (_ruling == BUYER_WINS) {
            recipient = buyer;
        } else if (_ruling == SELLER_WINS) {
            recipient = seller;
        } else {
            // In case of a tie or invalid ruling, default to buyer
            recipient = buyer;
        }

        (bool success, ) = recipient.call{value: escrowAmount}("");
        require(success, "Transfer failed");

        emit Ruled(_disputeID, _ruling);
        emit FundsReleased(recipient, escrowAmount);
    }

    /**
     * @dev Returns the contract balance
     */
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}

