# Dual-Token Reputation Recovery Mechanism for Decentralized Arbitration

## Problem Statement
Current Schelling-point arbitration systems (like [Kleros](https://kleros.io/)) permanently punish minority voters, creating a "virtuous contrarian" problem where ahead-of-curve jurors lose tokens despite being ultimately correct.

## Core Innovation: Dual-Token System

### Token Mechanics
- **Positive tokens (PNK)**: Standard arbitration tokens for staking and voting
- **Negative/Decoherence tokens**: Accumulated when voting against majority
  - Reduce voting weight but don't destroy PNK stake
  - Can only be exchanged for positive tokens (one-way conversion)
  - Represent system confidence debt - persist even after juror exits

### Reputation Recovery
- Voting with majority while holding negative tokens → burns those negative tokens
- Creates recoverable reputation rather than permanent loss
- Distinguishes between:
  - **Random contrarians**: Accumulate negative faster than they burn
  - **Virtuous contrarians**: Oscillate between gaining/burning on different cases

## Exit Validation Protocol

### Trigger Mechanism
When juror withdraws PNK stake:
1. System identifies all cases where they earned decoherence tokens
2. Those specific cases undergo re-arbitration with smaller juries (50 vs 100)
3. Decoherence tokens become the reward pool

### Economic Structure
- **Smaller jury → Higher individual rewards** (concentrated pool)
- **Lower individual penalty** (decoherence split among multiple jurors)
- Creates specialized "appellate juror" role with higher risk/reward

### Resolution Outcomes
- **New jury confirms original majority** → Decoherence tokens distributed as rewards
- **New jury agrees with contrarian** → Validates contrarian position
- **Unresolved case** → System maintains confidence debt until validated

## Key Advantages Over Existing Systems

| Aspect | Kleros (Current) | Dual-Token System |
|--------|------------------|-------------------|
| **Token Loss** | Permanent | Recoverable |
| **Exit Impact** | Tokens lost forever | Triggers validation |
| **Contrarian Support** | Punishes all dissent | Allows proven recovery |
| **System Confidence** | trackable but not salient | Persistent decoherence metric |

## Novel Properties

1. **Confidence Accounting**: System tracks unresolved uncertainty as persistent debt
2. **Automatic Audit**: Every contrarian exit triggers validation of controversial positions
3. **Self-Balancing**: True contrarians naturally equilibrate; random ones accumulate debt
4. **Market Discovery**: Forced token exchange creates price discovery for reputation

## Implementation Considerations

- Decoherence tokens persist as system confidence metric
- One-way token exchange increases positive token value through deflation
- Exit validation creates automatic "appeal through departure"
- System maintains integrity score independent of individual participation

---

*This mechanism transforms arbitration from a punitive system to a confidence-tracking system that can learn from and validate minority positions over time.*
