# Garden System - Multi-Strategy RWA Vaults

## 🌱 Overview

The Garden System allows users to choose between different RWA yield strategies based on their risk tolerance. Each "Garden" is a separate Diamond vault with its own governance and RWA allocation.

## 🏗️ Architecture

```
GardenRegistry (Tracks all gardens)
       ↓
GardenFactory (Deploys new gardens)
       ↓
   Diamond Garden (Individual vault with strategy)
       ├── DiamondRWAYieldFacetV2 (RWA management)
       ├── GovernanceFacet (DAO voting)
       └── DiamondCutFacet (Upgrades)
```

## 📊 Strategy Types

### 🛡️ Conservative Garden (Lowest Risk)
- **Primary RWA**: Backed IB01 T-Bills (8.7% APY)
- **Secondary**: None (single-asset)
- **Risk**: Lowest - Government-backed treasury bills
- **Best For**: Capital preservation + stable yield

### ⚖️ Balanced Garden (Medium Risk)
- **Primary RWA**: Backed IB01 T-Bills (8.7% APY)
- **Secondary**: Ondo USDY (4.8% APY)
- **Risk**: Medium - Mix of T-Bills + yield stablecoins
- **Best For**: Balanced risk/reward profile

### 🚀 Aggressive Garden (Higher Risk)
- **Primary RWA**: Ondo OUSG (5.1% APY)
- **Secondary**: MatrixDock STBT (6.2% APY)
- **Risk**: Higher - High-yield RWA tokens
- **Best For**: Maximum yield seekers

## 🔑 Key Features

### For Users
- **Choose Your Risk**: Pick a garden matching your risk tolerance
- **Deposit Once**: No need to manage individual RWAs
- **DAO Governance**: Vote on RWA upgrades within your garden
- **Compare Gardens**: See TVL, APY, and user count across all vaults

### For Deployers
- **Factory Pattern**: Deploy new gardens with one call
- **Registry Tracking**: All gardens discoverable in one place
- **Template Facets**: Reuse facet implementations across gardens
- **Strategy Presets**: Preconfigured Conservative/Balanced/Aggressive

## 📝 How to Use

### Deploy the System

```bash
forge script script/DeployGardenSystem.s.sol --broadcast
```

This deploys:
1. GardenRegistry (tracks all gardens)
2. GardenFactory (creates new gardens)
3. Template Facets (reused by all gardens)
4. 3 Initial Gardens (Conservative, Balanced, Aggressive)

### User Flow

```solidity
// 1. View all available gardens
GardenRegistry.getAllGardenStats()
// Returns: [{name: "Conservative", apy: 870, tvl: 1000000}, ...]

// 2. Choose a garden and deposit
address conservativeGarden = 0x...;
USDC.approve(conservativeGarden, 1000e6);
DiamondRWAYieldFacetV2(conservativeGarden).deposit(1000e6);

// 3. Earn yield automatically
// Your USDC is deposited into T-Bills earning 8.7% APY

// 4. Vote on RWA upgrades
GovernanceFacet(conservativeGarden).propose(newRWA, "Switch to higher yield T-Bill");
GovernanceFacet(conservativeGarden).castVote(proposalId, 1); // Vote Yes

// 5. Withdraw anytime
DiamondRWAYieldFacetV2(conservativeGarden).withdraw(shares);
```

### Deployer: Create Custom Garden

```solidity
// 1. Configure new strategy
factory.configureStrategy(
    GardenRegistry.StrategyType.CONSERVATIVE,
    customRWA,
    address(0),
    100e6, // 100 USDC minimum
    "Custom Strategy"
);

// 2. Deploy garden
address newGarden = factory.deployGarden(
    GardenRegistry.StrategyType.CONSERVATIVE,
    "My Custom Garden"
);

// Garden is now live and registered!
```

## 🔍 Registry Functions

### Discovery
```solidity
// Get all gardens
address[] memory gardens = registry.getAllGardens();

// Filter by strategy
address[] memory conservative = registry.getGardensByStrategy(
    GardenRegistry.StrategyType.CONSERVATIVE
);

// Get detailed stats
GardenRegistry.GardenStats memory stats = registry.getGardenStats(garden);
// Returns: {gardenAddress, strategy, name, tvl, apy, userCount, isActive}
```

### Comparison
```solidity
// Compare all gardens
GardenRegistry.GardenStats[] memory allStats = registry.getAllGardenStats();

for (uint i = 0; i < allStats.length; i++) {
    console.log("Garden:", allStats[i].name);
    console.log("APY:", allStats[i].apy); // basis points
    console.log("TVL:", allStats[i].tvl); // USDC
    console.log("Users:", allStats[i].userCount);
}
```

## 🧪 Testing

```bash
# Test complete garden system
forge test --match-contract GardenSystemTest

# Expected: 19+ tests passing
```

Tests cover:
- Registry initialization and tracking
- Factory deployment and configuration
- Garden deployment for all strategies
- Multi-garden operations
- Stats retrieval and comparison
- Admin functions

## 🎯 Real-World Example

**Alice** (Conservative)
```solidity
// Alice is risk-averse, chooses Conservative Garden
conservativeGarden.deposit(10000e6); // $10,000 USDC
// Earns 8.7% APY from T-Bills
// After 1 year: ~$870 profit
```

**Bob** (Balanced)
```solidity
// Bob wants balanced risk/reward
balancedGarden.deposit(10000e6); // $10,000 USDC
// Starts with T-Bills (8.7%), can vote to switch to USDY (4.8%)
// Flexible strategy via governance
```

**Charlie** (Aggressive)
```solidity
// Charlie wants max yield
aggressiveGarden.deposit(10000e6); // $10,000 USDC
// Earns from OUSG (5.1%) + STBT (6.2%)
// Higher risk, higher potential reward
```

## 📦 Contracts

- **GardenRegistry.sol** - Tracks all deployed gardens, provides discovery/comparison
- **GardenFactory.sol** - Deploys new Diamond gardens with preconfigured strategies
- **DeployGardenSystem.s.sol** - Deployment script for complete system

## 🔐 Security

- Each garden has **independent DAO governance** (1 share = 1 vote)
- **24-hour timelock** on RWA upgrades
- **Whitelisted RWAs** only (prevents rug pulls)
- **Factory pattern** ensures consistent initialization
- **Registry tracking** provides transparency

## 🚀 Next Steps

1. **Deploy System**: Run `DeployGardenSystem.s.sol`
2. **Test Gardens**: Users deposit into their chosen strategy
3. **Monitor Performance**: Use registry to compare garden APYs
4. **Governance**: Token holders vote on RWA upgrades
5. **Add Strategies**: Factory can deploy custom gardens anytime

---

Built with EIP-2535 Diamond Standard 💎
