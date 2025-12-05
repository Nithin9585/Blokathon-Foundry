# DAO Governance System 🗳️

**Community-controlled RWA strategy upgrades using token voting**

## Overview

The Diamond RWA Yield Engine now includes a complete DAO governance system that allows vault shareholders to democratically vote on which Real World Asset (RWA) to invest in. This replaces centralized admin control with community decision-making.

## How It Works

### Voting Power = Vault Shares

When you deposit USDC into the vault:
- You receive vault shares (1 USDC = 1 share)
- **1 share = 1 vote** in governance
- Your voting power is proportional to your deposit

### Governance Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    DAO GOVERNANCE FLOW                       │
└─────────────────────────────────────────────────────────────┘

1. 📝 CREATE PROPOSAL
   └─> Anyone with 100+ shares can propose a new RWA
   └─> Example: "Switch from Ondo OUSG (5.1%) to Backed IB01 (8.7%)"

2. 🗳️ VOTING PERIOD (7 days)
   └─> Community votes YES/NO/ABSTAIN
   └─> Need 1000+ shares voting YES to pass (quorum)
   └─> 50%+ majority required

3. ⏰ TIMELOCK (24 hours)
   └─> Passed proposals enter 24hr security delay
   └─> Prevents rushed decisions and attacks

4. ✅ EXECUTION
   └─> After timelock, anyone can execute
   └─> All vault funds migrate to new RWA
   └─> Everyone earns new APY automatically
```

## Smart Contracts

### Core Contracts

| Contract | Purpose |
|----------|---------|
| `GovernanceFacet.sol` | Main DAO interface (propose, vote, execute) |
| `GovernanceBase.sol` | Internal voting logic and power calculation |
| `GovernanceStorage.sol` | Proposal storage and vote tracking |
| `IGovernance.sol` | Standard governance interface |

### Integration

Governance controls these functions in `DiamondRWAYieldFacetV2.sol`:
- `scheduleUpgrade()` - DAO proposes new RWA
- `executeScheduledUpgrade()` - DAO executes after timelock
- `cancelScheduledUpgrade()` - DAO cancels pending upgrade

## Governance Parameters

### Default Configuration

```solidity
Voting Delay:        1 block (~12 seconds)
Voting Period:       50,400 blocks (~7 days)
Proposal Threshold:  100 USDC worth of shares
Quorum Required:     1,000 USDC worth of votes
Timelock Delay:      24 hours
```

### Adjustable Parameters

Only the contract owner can update these during transition phase:
- `setVotingDelay()` - Change delay before voting starts
- `setVotingPeriod()` - Change voting duration
- `setProposalThreshold()` - Change minimum to create proposal
- `setQuorumVotes()` - Change minimum votes to pass

## Usage Examples

### 1. Create a Proposal

```solidity
// You need 100+ shares to propose
GovernanceFacet governance = GovernanceFacet(diamondAddress);

uint256 proposalId = governance.propose(
    0xCA30c93B02514f86d5C86a6e375E3A330B435Fb5, // Backed IB01 address
    "Upgrade to Backed IB01 for 8.7% APY (currently 5.1% on Ondo)"
);
```

### 2. Vote on Proposal

```solidity
// Vote types: 0=Against, 1=For, 2=Abstain
governance.castVote(proposalId, 1); // Vote YES

// Or vote with a reason
governance.castVoteWithReason(
    proposalId, 
    1, 
    "8.7% APY is significantly better than our current 5.1%"
);
```

### 3. Queue After Passing

```solidity
// After voting ends and proposal passed
uint256 executionTime = governance.queue(proposalId);
// executionTime = current timestamp + 24 hours
```

### 4. Execute After Timelock

```solidity
// After 24 hours passed
governance.execute(proposalId);
// This calls scheduleUpgrade() on the RWA facet
// All funds automatically migrate to new RWA
```

## Deployment

### 1. Deploy Governance Facet

```bash
forge script script/DeployGovernance.s.sol:DeployGovernance \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify
```

Make sure to set in `.env`:
```
PRIVATE_KEY=your_deployer_key
DIAMOND_ADDRESS=your_existing_diamond
```

### 2. Initialize Governance

The script automatically initializes with default parameters. To customize:

```solidity
GovernanceFacet(diamond).initializeGovernance(
    1,        // votingDelay (blocks)
    50400,    // votingPeriod (blocks)
    100e6,    // proposalThreshold (100 USDC)
    1000e6,   // quorumVotes (1000 USDC)
    86400     // timelockDelay (24 hours)
);
```

## Testing

### Run DAO Demo

```bash
forge script script/DAOGovernanceDemo.s.sol:DAOGovernanceDemo --fork-url $ARBITRUM_RPC -vvv
```

This demonstrates:
- Alice deposits 1000 USDC → 1000 voting power
- Alice creates proposal to switch RWAs
- Alice + Bob vote YES
- Proposal passes and executes
- Everyone now earns higher APY

### Run Governance Tests

```bash
forge test --match-contract GovernanceTest -vv
```

## Security Features

### ✅ Timelock Protection
- 24-hour delay before execution
- Allows community to react to malicious proposals
- Can cancel during timelock if needed

### ✅ Quorum Requirements
- Need 1000+ USDC worth of votes to pass
- Prevents low-participation attacks
- Ensures meaningful community consensus

### ✅ Proposal Threshold
- Need 100+ USDC shares to create proposal
- Prevents spam proposals
- Ensures proposers have skin in the game

### ✅ Checkpoint System
- Votes based on balance at proposal creation
- Prevents flashloan attacks
- Can't buy voting power after seeing proposal

### ✅ Proposal States
```
Pending → Active → Succeeded → Queued → Executed
                 ↓
              Defeated/Canceled/Expired
```

## Migration Path to Full DAO

### Phase 1: Hybrid Control (Current)
- Owner retains emergency powers
- DAO can propose and vote
- Owner can override if needed

### Phase 2: DAO Primary
- DAO controls all upgrades
- Owner only for emergencies
- 48+ hour timelock for security

### Phase 3: Full Decentralization
- Owner renounced or transferred to governance
- All control via DAO voting
- Multi-sig backup for critical operations

## Frontend Integration

### Check User's Voting Power

```javascript
const shares = await vault.getUserShares(userAddress);
console.log(`You have ${shares} voting power`);
```

### List Active Proposals

```javascript
const proposalCount = await governance.proposalCount();
for (let i = 1; i <= proposalCount; i++) {
  const proposal = await governance.getProposal(i);
  const state = await governance.state(i);
  console.log(`Proposal #${i}: ${proposal.description}`);
  console.log(`Status: ${state}`);
}
```

### Check If User Voted

```javascript
const hasVoted = await governance.hasVoted(proposalId, userAddress);
if (!hasVoted) {
  // Show voting UI
}
```

## Why This Matters

### Traditional DeFi Problems
❌ Admin controls everything  
❌ Stuck with one yield source  
❌ No community input  
❌ Trust a single team  

### Diamond RWA DAO Solution
✅ **Community-controlled**: Token holders decide  
✅ **Dynamic**: Switch to best APY via vote  
✅ **Transparent**: All votes on-chain  
✅ **Secure**: 24hr timelock + quorum  

## Example Scenario

**Current State**: Vault invested in Ondo OUSG earning 5.1% APY

**Market Change**: Backed IB01 now offers 8.7% APY

**DAO Response**:
1. Community member creates proposal
2. 1500 USDC worth of shares vote YES
3. Proposal passes after 7 days
4. 24hr timelock completes
5. Execute: All funds migrate to Backed IB01
6. Everyone now earns 8.7% APY (70% increase!)

**Result**: The vault automatically optimizes yield based on community consensus

## Gas Costs

Approximate gas usage on Arbitrum:

| Action | Gas Cost |
|--------|----------|
| Create Proposal | ~100k gas (~$0.10) |
| Cast Vote | ~80k gas (~$0.08) |
| Queue Proposal | ~60k gas (~$0.06) |
| Execute | ~200k gas (~$0.20) |

## Questions?

The governance system is built on battle-tested patterns:
- **Compound Governor**: Proposal/voting structure
- **OpenZeppelin Timelock**: Security delay
- **ERC20Votes**: Checkpoint-based voting power

Read more:
- [Compound Governance](https://compound.finance/docs/governance)
- [OpenZeppelin Governor](https://docs.openzeppelin.com/contracts/4.x/governance)
- [EIP-2535 Diamond Standard](https://eips.ethereum.org/EIPS/eip-2535)

---

**Built for the Diamond RWA Yield Engine Hackathon** 🏆
