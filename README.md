# MiniKleros

*NOTE* This Project is a boilerplate developed to test my hypothesis on Dual-Token Reputation Recovery Mechanism for Decentralized Arbitration. It needs to be implemented, but you can find some thoughts on it [in the proposal document](./Proposal.md). 

## Overview

MiniKleros is a simplified arbitration protocol that allows jurors to stake tokens and vote on disputes using a commit-reveal scheme. Jurors who vote with the majority are rewarded, while those who vote with the minority or fail to reveal their votes are penalized.

> 💡 **Note:** This implementation uses permanent stake penalties for minority voters. See [Proposal.md](./Proposal.md) for a dual-token approach that I am playing around with currently to address a few limitations.

## Architecture

### Smart Contracts

#### 1. ProjectPNK.sol
An ERC20 token used for staking in the arbitration system.
- **Features:**
  - Based on OpenZeppelin's ERC20 with Ownable
  - Owner can mint tokens for testing
  - Initial supply of 1,000,000 PNK tokens

#### 2. MiniKleros.sol
The main arbitrator contract handling dispute resolution.
- **Key Features:**
  - Juror staking and unstaking
  - Weighted random juror selection based on stake
  - Commit-reveal voting mechanism
  - Automatic penalty and reward distribution
  - Integration with arbitrable contracts

- **State Machine:**
  - `Committing`: Jurors submit vote commitments (1 day)
  - `Revealing`: Jurors reveal their votes (1 day)
  - `Resolved`: Dispute is finalized and ruling enforced

- **Incentive Mechanism:**
  - Minority voters lose 20% of their stake (permanent loss)
  - Non-revealing jurors lose 20% of their stake (permanent loss)
  - Majority voters share penalties + arbitration fee


#### 3. ArbitrableEscrow.sol
A sample escrow contract that uses MiniKleros for dispute resolution.
- **Features:**
  - Buyer deposits ETH for seller
  - Buyer can release funds voluntarily
  - Either party can raise a dispute
  - Dispute ruling automatically releases funds to winner

## Installation

```bash
# Clone the repository
cd arbitration

# Install dependencies (already done during setup)
forge install

# Build the project
forge build

# Run tests
forge test

# Run tests with verbose output
forge test -vv
```

## Usage

### Deploying Contracts

```solidity
// Deploy ProjectPNK token
ProjectPNK pnk = new ProjectPNK();

// Deploy MiniKleros arbitrator
MiniKleros kleros = new MiniKleros(address(pnk));

// Deploy escrow contract
ArbitrableEscrow escrow = new ArbitrableEscrow{value: 1 ether}(
    address(kleros),
    sellerAddress,
    0.1 ether // arbitration fee
);
```

### Becoming a Juror

```solidity
// Approve and stake PNK tokens
pnk.approve(address(kleros), stakeAmount);
kleros.stake(stakeAmount);
```

### Creating a Dispute

```solidity
// Raise a dispute from the escrow contract
escrow.raiseDispute{value: arbitrationFee}();
```

### Voting on a Dispute

```solidity
// 1. Commit vote (during commit phase)
uint256 disputeID = 0;
uint256 choice = 1; // your vote
uint256 salt = 12345; // random salt
bytes32 commitment = keccak256(abi.encodePacked(disputeID, choice, salt));
kleros.commitVote(disputeID, commitment);

// 2. Reveal vote (during reveal phase, after commit deadline)
kleros.revealVote(disputeID, choice, salt);

// 3. Tally votes (after reveal deadline, callable by anyone)
kleros.tallyVotes(disputeID);
```

## Test Suite

The project includes comprehensive tests covering:

1. **Staking Tests**
   - Token staking and unstaking
   - Stake tracking and total calculation

2. **Dispute Creation Tests**
   - Creating disputes with arbitration fees
   - Juror selection verification

3. **Commit-Reveal Tests**
   - Valid commit and reveal flows
   - Invalid reveal attempts
   - Deadline enforcement

4. **Full Lifecycle Tests**
   - Complete dispute resolution
   - Stake redistribution for majority/minority voters
   - Penalty enforcement for non-revealing jurors

5. **Escrow Integration Tests**
   - Voluntary fund release
   - Dispute-based fund distribution
   - Winner verification

### Running Tests

```bash
# Run all tests
forge test

# Run tests with gas reporting
forge test --gas-report

# Run specific test
forge test --match-test testFullDisputeLifecycleWithMajority

# Run tests with detailed traces
forge test -vvvv
```

## Security Considerations

 **This is a simplified implementation for educational purposes and should NOT be used in production without significant improvements:**

1. **Randomness:** Uses `block.prevrandao` which is manipulable by validators
2. **Juror Selection:** Simple weighted selection may not be secure at scale
3. **No Timelock:** Unstaking is immediate (no withdrawal delay)
4. **No Appeal System:** Rulings are final
5. **Fixed Penalties:** 20% penalty may not be economically optimal
6. **No Juror Coherence:** Jurors can be selected multiple times across disputes
7. **Permanent Minority Punishment:** Minority voters permanently lose stake, creating the "virtuous contrarian" problem (see [Proposal.md](./Proposal.md) for a potential solution)

## Gas Optimization Opportunities (maybe , I asked gpt for these, and this cool readme as well)

- Use tighter variable packing in structs
- Cache array lengths in loops
- Use events for off-chain data storage
- Implement batch operations for multiple jurors

## Future Enhancements

### Dual-Token Reputation Recovery System
See [Proposal.md](./Proposal.md) for a detailed mechanism to address the "virtuous contrarian" problem in Schelling-point arbitration systems. Key innovations include:
- Recoverable reputation through negative/decoherence tokens
- Exit validation protocol that triggers re-arbitration
- Confidence accounting to track system uncertainty
- Support for ahead-of-curve jurors without permanent punishment

### Quadratic Voting Integration
New Kleros implementations are discussing about Quadratic voting. I still need to look into it. 



## Project Structure

```
arbitration/
├── src/
│   ├── ProjectPNK.sol         # ERC20 staking token
│   ├── MiniKleros.sol         # Main arbitrator contract
│   └── ArbitrableEscrow.sol   # Sample arbitrable contract
├── test/
│   └── MiniKleros.t.sol       # Comprehensive test suite
├── lib/                        # Dependencies
├── foundry.toml               # Foundry configuration
└── README.md                  # This file
```

## Dependencies

- Solidity ^0.8.20
- Foundry (forge, cast, anvil)
- OpenZeppelin Contracts v5.0.0

## Development

```bash
# Format code
forge fmt

# Check for security issues (requires slither)
slither .

# Generate coverage report
forge coverage

# Deploy to local testnet
anvil  # in one terminal
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast
```


