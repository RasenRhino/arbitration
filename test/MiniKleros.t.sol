// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/ProjectPNK.sol";
import "../src/MiniKleros.sol";
import "../src/ArbitrableEscrow.sol";

contract MiniKlerosTest is Test {
    ProjectPNK public pnk;
    MiniKleros public kleros;
    ArbitrableEscrow public escrow;

    address public owner;
    address public alice;
    address public bob;
    address public charlie;
    address public dave;
    address public buyer;
    address public seller;

    uint256 public constant INITIAL_STAKE = 1000 ether;
    uint256 public constant ARBITRATION_FEE = 0.1 ether;
    uint256 public constant ESCROW_AMOUNT = 1 ether;

    function setUp() public {
        // Set up test accounts
        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");
        dave = makeAddr("dave");
        buyer = makeAddr("buyer");
        seller = makeAddr("seller");

        // Deploy contracts
        pnk = new ProjectPNK();
        kleros = new MiniKleros(address(pnk));

        // Mint PNK tokens to test users
        pnk.mint(alice, INITIAL_STAKE);
        pnk.mint(bob, INITIAL_STAKE);
        pnk.mint(charlie, INITIAL_STAKE);
        pnk.mint(dave, INITIAL_STAKE);

        // Fund test accounts with ETH
        vm.deal(buyer, 10 ether);
        vm.deal(seller, 10 ether);
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        vm.deal(charlie, 10 ether);
    }

    function testStaking() public {
        // Alice stakes tokens
        vm.startPrank(alice);
        pnk.approve(address(kleros), INITIAL_STAKE);
        kleros.stake(INITIAL_STAKE);
        vm.stopPrank();

        assertEq(kleros.jurorStakes(alice), INITIAL_STAKE);
        assertEq(kleros.totalStaked(), INITIAL_STAKE);
    }

    function testUnstaking() public {
        // Alice stakes tokens
        vm.startPrank(alice);
        pnk.approve(address(kleros), INITIAL_STAKE);
        kleros.stake(INITIAL_STAKE);

        // Alice unstakes half
        uint256 unstakeAmount = INITIAL_STAKE / 2;
        kleros.unstake(unstakeAmount);
        vm.stopPrank();

        assertEq(kleros.jurorStakes(alice), INITIAL_STAKE - unstakeAmount);
        assertEq(kleros.totalStaked(), INITIAL_STAKE - unstakeAmount);
        assertEq(pnk.balanceOf(alice), unstakeAmount);
    }

    function testCreateDispute() public {
        // Set up jurors
        _setupJurors();

        // Create escrow and dispute
        vm.prank(buyer);
        escrow = new ArbitrableEscrow{value: ESCROW_AMOUNT}(
            address(kleros),
            seller,
            ARBITRATION_FEE
        );

        // Raise dispute
        vm.prank(buyer);
        escrow.raiseDispute{value: ARBITRATION_FEE}();

        assertEq(kleros.disputeCount(), 1);
        address[] memory selectedJurors = kleros.getSelectedJurors(0);
        assertEq(selectedJurors.length, 3);
    }

    function testCommitVote() public {
        _setupJurors();
        uint256 disputeID = _createDispute();

        address[] memory selectedJurors = kleros.getSelectedJurors(disputeID);
        address juror = selectedJurors[0];

        // Juror commits vote
        uint256 choice = 1;
        uint256 salt = 12345;
        bytes32 commitment = keccak256(abi.encodePacked(disputeID, choice, salt));

        vm.prank(juror);
        kleros.commitVote(disputeID, commitment);

        assertEq(kleros.getCommitment(disputeID, juror), commitment);
    }

    function testRevealVote() public {
        _setupJurors();
        uint256 disputeID = _createDispute();

        address[] memory selectedJurors = kleros.getSelectedJurors(disputeID);
        address juror = selectedJurors[0];

        // Commit vote
        uint256 choice = 1;
        uint256 salt = 12345;
        bytes32 commitment = keccak256(abi.encodePacked(disputeID, choice, salt));

        vm.prank(juror);
        kleros.commitVote(disputeID, commitment);

        // Fast forward past commit deadline
        vm.warp(block.timestamp + 1 days + 1);

        // Reveal vote
        vm.prank(juror);
        kleros.revealVote(disputeID, choice, salt);

        assertTrue(kleros.hasRevealed(disputeID, juror));
        assertEq(kleros.getRevealedVote(disputeID, juror), choice);
    }

    function testInvalidReveal() public {
        _setupJurors();
        uint256 disputeID = _createDispute();

        address[] memory selectedJurors = kleros.getSelectedJurors(disputeID);
        address juror = selectedJurors[0];

        // Commit vote
        uint256 choice = 1;
        uint256 salt = 12345;
        bytes32 commitment = keccak256(abi.encodePacked(disputeID, choice, salt));

        vm.prank(juror);
        kleros.commitVote(disputeID, commitment);

        // Fast forward past commit deadline
        vm.warp(block.timestamp + 1 days + 1);

        // Try to reveal with wrong salt
        vm.prank(juror);
        vm.expectRevert("Invalid reveal");
        kleros.revealVote(disputeID, choice, 99999);
    }

    function testFullDisputeLifecycleWithMajority() public {
        _setupJurors();
        uint256 disputeID = _createDispute();

        address[] memory selectedJurors = kleros.getSelectedJurors(disputeID);
        
        // Record initial stakes
        uint256 aliceInitialStake = kleros.jurorStakes(selectedJurors[0]);
        uint256 bobInitialStake = kleros.jurorStakes(selectedJurors[1]);
        uint256 charlieInitialStake = kleros.jurorStakes(selectedJurors[2]);

        // All jurors commit votes (Alice and Bob vote 1, Charlie votes 0)
        uint256 salt1 = 11111;
        uint256 salt2 = 22222;
        uint256 salt3 = 33333;

        bytes32 commitment1 = keccak256(abi.encodePacked(disputeID, uint256(1), salt1));
        bytes32 commitment2 = keccak256(abi.encodePacked(disputeID, uint256(1), salt2));
        bytes32 commitment3 = keccak256(abi.encodePacked(disputeID, uint256(0), salt3));

        vm.prank(selectedJurors[0]);
        kleros.commitVote(disputeID, commitment1);

        vm.prank(selectedJurors[1]);
        kleros.commitVote(disputeID, commitment2);

        vm.prank(selectedJurors[2]);
        kleros.commitVote(disputeID, commitment3);

        // Fast forward past commit deadline
        vm.warp(block.timestamp + 1 days + 1);

        // All jurors reveal votes
        vm.prank(selectedJurors[0]);
        kleros.revealVote(disputeID, 1, salt1);

        vm.prank(selectedJurors[1]);
        kleros.revealVote(disputeID, 1, salt2);

        vm.prank(selectedJurors[2]);
        kleros.revealVote(disputeID, 0, salt3);

        // Fast forward past reveal deadline
        vm.warp(block.timestamp + 1 days + 1);

        // Tally votes
        kleros.tallyVotes(disputeID);

        // Check that dispute is resolved
        assertEq(uint256(kleros.getDisputeState(disputeID)), uint256(MiniKleros.DisputeState.Resolved));

        // Check stakes after tallying
        uint256 aliceFinalStake = kleros.jurorStakes(selectedJurors[0]);
        uint256 bobFinalStake = kleros.jurorStakes(selectedJurors[1]);
        uint256 charlieFinalStake = kleros.jurorStakes(selectedJurors[2]);

        // Alice and Bob (majority) should have increased stakes
        assertGt(aliceFinalStake, aliceInitialStake, "Alice stake should increase");
        assertGt(bobFinalStake, bobInitialStake, "Bob stake should increase");

        // Charlie (minority) should have decreased stake
        assertLt(charlieFinalStake, charlieInitialStake, "Charlie stake should decrease");

        // Check penalty calculation
        uint256 expectedPenalty = (charlieInitialStake * 20) / 100;
        assertEq(charlieFinalStake, charlieInitialStake - expectedPenalty);

        // Check that escrow funds were released to seller (ruling = 1)
        assertEq(escrow.fundsReleased(), true);
    }

    function testPenaltyForFailedReveal() public {
        _setupJurors();
        uint256 disputeID = _createDispute();

        address[] memory selectedJurors = kleros.getSelectedJurors(disputeID);
        
        // Record initial stakes
        uint256 juror1InitialStake = kleros.jurorStakes(selectedJurors[0]);
        uint256 juror2InitialStake = kleros.jurorStakes(selectedJurors[1]);
        uint256 juror3InitialStake = kleros.jurorStakes(selectedJurors[2]);

        // All jurors commit votes
        uint256 salt1 = 11111;
        uint256 salt2 = 22222;
        uint256 salt3 = 33333;

        bytes32 commitment1 = keccak256(abi.encodePacked(disputeID, uint256(1), salt1));
        bytes32 commitment2 = keccak256(abi.encodePacked(disputeID, uint256(1), salt2));
        bytes32 commitment3 = keccak256(abi.encodePacked(disputeID, uint256(0), salt3));

        vm.prank(selectedJurors[0]);
        kleros.commitVote(disputeID, commitment1);

        vm.prank(selectedJurors[1]);
        kleros.commitVote(disputeID, commitment2);

        vm.prank(selectedJurors[2]);
        kleros.commitVote(disputeID, commitment3);

        // Fast forward past commit deadline
        vm.warp(block.timestamp + 1 days + 1);

        // Only first two jurors reveal (third juror fails to reveal)
        vm.prank(selectedJurors[0]);
        kleros.revealVote(disputeID, 1, salt1);

        vm.prank(selectedJurors[1]);
        kleros.revealVote(disputeID, 1, salt2);

        // Fast forward past reveal deadline
        vm.warp(block.timestamp + 1 days + 1);

        // Tally votes
        kleros.tallyVotes(disputeID);

        // Check stakes after tallying
        uint256 juror1FinalStake = kleros.jurorStakes(selectedJurors[0]);
        uint256 juror2FinalStake = kleros.jurorStakes(selectedJurors[1]);
        uint256 juror3FinalStake = kleros.jurorStakes(selectedJurors[2]);

        // First two jurors (revealed and majority) should have increased stakes
        assertGt(juror1FinalStake, juror1InitialStake, "Juror 1 stake should increase");
        assertGt(juror2FinalStake, juror2InitialStake, "Juror 2 stake should increase");

        // Third juror (failed to reveal) should have decreased stake
        uint256 expectedPenalty = (juror3InitialStake * 20) / 100;
        assertEq(juror3FinalStake, juror3InitialStake - expectedPenalty, "Juror 3 should be penalized");
    }

    function testEscrowReleaseFundsByBuyer() public {
        _setupJurors();

        // Create escrow
        vm.prank(buyer);
        escrow = new ArbitrableEscrow{value: ESCROW_AMOUNT}(
            address(kleros),
            seller,
            ARBITRATION_FEE
        );

        uint256 sellerInitialBalance = seller.balance;

        // Buyer releases funds
        vm.prank(buyer);
        escrow.releaseFunds();

        assertEq(escrow.fundsReleased(), true);
        assertEq(seller.balance, sellerInitialBalance + ESCROW_AMOUNT);
    }

    function testEscrowRulingBuyerWins() public {
        _setupJurors();
        uint256 disputeID = _createDispute();

        address[] memory selectedJurors = kleros.getSelectedJurors(disputeID);

        // All jurors vote for buyer (choice 0)
        uint256 salt1 = 11111;
        uint256 salt2 = 22222;
        uint256 salt3 = 33333;

        bytes32 commitment1 = keccak256(abi.encodePacked(disputeID, uint256(0), salt1));
        bytes32 commitment2 = keccak256(abi.encodePacked(disputeID, uint256(0), salt2));
        bytes32 commitment3 = keccak256(abi.encodePacked(disputeID, uint256(0), salt3));

        vm.prank(selectedJurors[0]);
        kleros.commitVote(disputeID, commitment1);

        vm.prank(selectedJurors[1]);
        kleros.commitVote(disputeID, commitment2);

        vm.prank(selectedJurors[2]);
        kleros.commitVote(disputeID, commitment3);

        // Fast forward past commit deadline
        vm.warp(block.timestamp + 1 days + 1);

        // All jurors reveal votes
        vm.prank(selectedJurors[0]);
        kleros.revealVote(disputeID, 0, salt1);

        vm.prank(selectedJurors[1]);
        kleros.revealVote(disputeID, 0, salt2);

        vm.prank(selectedJurors[2]);
        kleros.revealVote(disputeID, 0, salt3);

        // Fast forward past reveal deadline
        vm.warp(block.timestamp + 1 days + 1);

        uint256 buyerInitialBalance = buyer.balance;

        // Tally votes
        kleros.tallyVotes(disputeID);

        // Check that funds were released to buyer
        assertEq(escrow.fundsReleased(), true);
        assertEq(buyer.balance, buyerInitialBalance + ESCROW_AMOUNT);
    }

    function testCannotCommitAfterDeadline() public {
        _setupJurors();
        uint256 disputeID = _createDispute();

        address[] memory selectedJurors = kleros.getSelectedJurors(disputeID);

        // Fast forward past commit deadline
        vm.warp(block.timestamp + 1 days + 1);

        // Try to commit vote
        bytes32 commitment = keccak256(abi.encodePacked(disputeID, uint256(1), uint256(12345)));

        vm.prank(selectedJurors[0]);
        vm.expectRevert("Commit deadline passed");
        kleros.commitVote(disputeID, commitment);
    }

    function testCannotRevealBeforeCommitDeadline() public {
        _setupJurors();
        uint256 disputeID = _createDispute();

        address[] memory selectedJurors = kleros.getSelectedJurors(disputeID);

        // Commit vote
        uint256 choice = 1;
        uint256 salt = 12345;
        bytes32 commitment = keccak256(abi.encodePacked(disputeID, choice, salt));

        vm.prank(selectedJurors[0]);
        kleros.commitVote(disputeID, commitment);

        // Try to reveal immediately (before commit deadline)
        vm.prank(selectedJurors[0]);
        vm.expectRevert("Not in revealing phase");
        kleros.revealVote(disputeID, choice, salt);
    }

    function testCannotRevealAfterDeadline() public {
        _setupJurors();
        uint256 disputeID = _createDispute();

        address[] memory selectedJurors = kleros.getSelectedJurors(disputeID);

        // Commit vote
        uint256 choice = 1;
        uint256 salt = 12345;
        bytes32 commitment = keccak256(abi.encodePacked(disputeID, choice, salt));

        vm.prank(selectedJurors[0]);
        kleros.commitVote(disputeID, commitment);

        // Fast forward past reveal deadline
        vm.warp(block.timestamp + 3 days);

        // Try to reveal after deadline
        vm.prank(selectedJurors[0]);
        vm.expectRevert("Reveal deadline passed");
        kleros.revealVote(disputeID, choice, salt);
    }

    function testNonJurorCannotCommit() public {
        _setupJurors();
        uint256 disputeID = _createDispute();

        // Try to commit as non-juror
        bytes32 commitment = keccak256(abi.encodePacked(disputeID, uint256(1), uint256(12345)));

        vm.prank(dave);
        vm.expectRevert("Not a selected juror");
        kleros.commitVote(disputeID, commitment);
    }

    // Helper functions

    function _setupJurors() internal {
        // Alice, Bob, and Charlie stake tokens
        vm.startPrank(alice);
        pnk.approve(address(kleros), INITIAL_STAKE);
        kleros.stake(INITIAL_STAKE);
        vm.stopPrank();

        vm.startPrank(bob);
        pnk.approve(address(kleros), INITIAL_STAKE);
        kleros.stake(INITIAL_STAKE);
        vm.stopPrank();

        vm.startPrank(charlie);
        pnk.approve(address(kleros), INITIAL_STAKE);
        kleros.stake(INITIAL_STAKE);
        vm.stopPrank();
    }

    function _createDispute() internal returns (uint256 disputeID) {
        // Create escrow
        vm.prank(buyer);
        escrow = new ArbitrableEscrow{value: ESCROW_AMOUNT}(
            address(kleros),
            seller,
            ARBITRATION_FEE
        );

        // Raise dispute
        vm.prank(buyer);
        escrow.raiseDispute{value: ARBITRATION_FEE}();

        disputeID = 0;
    }
}

