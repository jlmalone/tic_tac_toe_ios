# Deployment Guide: Smart Contracts and iOS App

## Table of Contents

1. [Network Configuration](#network-configuration)
2. [Smart Contract Deployment](#smart-contract-deployment)
3. [iOS App Deployment](#ios-app-deployment)
4. [Post-Deployment Verification](#post-deployment-verification)
5. [Network-Specific Considerations](#network-specific-considerations)
6. [Troubleshooting](#troubleshooting)

---

## Network Configuration

### Supported Networks

| Network | Type | RPC URL | Chain ID | Status |
|---------|------|---------|----------|--------|
| Hardhat (Local) | Development | http://127.0.0.1:8545 | 31337 | Active |
| Sepolia Testnet | Staging | https://sepolia.infura.io/v3/ | 11155111 | Active |
| Ethereum Mainnet | Production | N/A | 1 | Future |

### Configuration Storage

**File**: `Info.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Local Network -->
    <key>LOCAL_RPC_URL</key>
    <string>http://127.0.0.1:8545</string>

    <!-- Sepolia Testnet -->
    <key>SEPOLIA_RPC_URL</key>
    <string>https://sepolia.infura.io/v3/YOUR_INFURA_KEY</string>

    <!-- Private Keys (Local Testing Only) -->
    <key>PRIVATE_KEY_HARDHAT_0</key>
    <string>0x...</string>

    <key>PRIVATE_KEY_HARDHAT_1</key>
    <string>0x...</string>

    <!-- Sepolia Test Keys -->
    <key>PRIVATE_KEY_PLAYER1</key>
    <string>0x...</string>

    <key>PRIVATE_KEY_PLAYER2</key>
    <string>0x...</string>
</dict>
</plist>
```

---

## Smart Contract Deployment

### 1. Local Hardhat Deployment

#### Prerequisites

```bash
# Install dependencies
npm install --save-dev hardhat @nomiclabs/hardhat-waffle ethereum-waffle chai ethers

# Initialize Hardhat project
npx hardhat
```

#### Deploy to Local Network

```bash
# Start local Hardhat node (in separate terminal)
npx hardhat node

# Deploy contracts (in another terminal)
npx hardhat run scripts/deploy.js --network localhost
```

**Expected Output**:
```
Factory deployed to: 0x4A679253410272dd5232B3Ff7cF5dbB88f295319
Game deployed to: 0xa85233C63b9Ee964Add6F2cffe00Fd84eb32338f
Deployment addresses saved to: deployment_output_hardhat_local.json
```

**Output File**: `deployment_output_hardhat_local.json`

```json
{
    "gameImplementationAddress": "0xa85233C63b9Ee964Add6F2cffe00Fd84eb32338f",
    "factoryAddress": "0x4A679253410272dd5232B3Ff7cF5dbB88f295319"
}
```

---

### 2. Sepolia Testnet Deployment

#### Prerequisites

1. **Get Sepolia Testnet ETH**:
   - Go to https://sepoliafaucet.com/
   - Enter your wallet address
   - Wait for confirmation

2. **Create Infura API Key**:
   - Visit https://app.infura.io/
   - Create project
   - Copy API key

3. **Configure Environment**:
```bash
# Create .env file
SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/YOUR_INFURA_KEY
SEPOLIA_PRIVATE_KEY=0xYOUR_PRIVATE_KEY
```

#### Deploy to Sepolia

```bash
# Deploy with Hardhat
npx hardhat run scripts/deploy.js --network sepolia

# Or use Truffle
truffle migrate --network sepolia

# Or use Foundry
forge script scripts/Deploy.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast
```

**Output File**: `deployment_output_sepolia_testnet.json`

```json
{
    "gameImplementationAddress": "0x340AC014d800Ac398Af239Cebc3a376eb71B0353",
    "factoryAddress": "0xa0B53DbDb0052403E38BBC31f01367aC6782118E",
    "deploymentBlock": 7654322,
    "deploymentTxHash": "0xabcd1234..."
}
```

---

### 3. Verification on Sepolia

#### Verify Contract on Etherscan

```bash
npx hardhat verify --network sepolia ADDRESS "Constructor args"
```

Example:
```bash
npx hardhat verify --network sepolia 0x340AC014d800Ac398Af239Cebc3a376eb71B0353
```

**Expected Output**:
```
Successfully submitted source code for contract
Address: 0x340AC014d800Ac398Af239Cebc3a376eb71B0353
Status: Verified ✓
```

#### View on Etherscan

```
https://sepolia.etherscan.io/address/0x340AC014d800Ac398Af239Cebc3a376eb71B0353
```

---

## iOS App Deployment

### 1. Configure App for Target Network

**File**: `BlockchainService.swift`

```swift
func loadDeploymentAddresses() {
    let isDevelopment = useLocal
    let configFileName = isDevelopment
        ? "deployment_output_hardhat_local"
        : "deployment_output_sepolia_testnet"

    guard let url = Bundle.main.url(forResource: configFileName, withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let decoded = try? JSONDecoder().decode(DeploymentAddresses.self, from: data) else {
        print("Failed to load deployment config")
        return
    }

    self.factoryAddress = decoded.factoryAddress
}
```

### 2. Add Deployment Files to Xcode Project

1. Copy `deployment_output_hardhat_local.json` to project root
2. Copy `deployment_output_sepolia_testnet.json` to project root
3. In Xcode: File → Add Files to Project
4. Select both JSON files
5. Ensure files are added to target

### 3. Update Info.plist

**For Local Development**:
```xml
<key>LOCAL_RPC_URL</key>
<string>http://127.0.0.1:8545</string>
```

**For Sepolia**:
```xml
<key>SEPOLIA_RPC_URL</key>
<string>https://sepolia.infura.io/v3/YOUR_INFURA_KEY</string>
```

### 4. Build and Run

```bash
# Build for simulator
xcodebuild -scheme TicTacToeiOS -configuration Debug -destination generic/platform=iOS

# Build for device
xcodebuild -scheme TicTacToeiOS -configuration Release -destination generic/platform=iOS

# Or use Xcode directly
open tic_tac_toe_ios.xcodeproj
# Then ⌘B to build
# ⌘R to run
```

---

## Post-Deployment Verification

### 1. Verify Contract Deployment

```swift
// In app startup
Task {
    let code = try await web3.eth.getCode(at: factoryAddress)
    let isDeployed = code != "0x"
    print("Factory deployed: \(isDeployed)")
}
```

### 2. Test Contract Functions

```swift
// Test factory
Task {
    let gameAddress = try await blockchainService.createGame(by: 0)
    print("Game created: \(gameAddress)")
}

// Test game
Task {
    let board = try await blockchainService.readBoardState()
    print("Board state: \(board)")
}
```

### 3. Verify Deployment Addresses

**Expected Hardhat Addresses**:
- Factory: `0x4A679253410272dd5232B3Ff7cF5dbB88f295319`
- Game: `0xa85233C63b9Ee964Add6F2cffe00Fd84eb32338f`

**Expected Sepolia Addresses**:
- Factory: `0xa0B53DbDb0052403E38BBC31f01367aC6782118E`
- Game: `0x340AC014d800Ac398Af239Cebc3a376eb71B0353`

```swift
func verifyDeploymentAddresses() {
    let expected = useLocal
        ? ("0x4A679253410272dd5232B3Ff7cF5dbB88f295319", "0xa85233C63b9Ee964Add6F2cffe00Fd84eb32338f")
        : ("0xa0B53DbDb0052403E38BBC31f01367aC6782118E", "0x340AC014d800Ac398Af239Cebc3a376eb71B0353")

    XCTAssertEqual(factoryAddress, expected.0, "Factory address mismatch")
    // ... verify game address too
}
```

---

## Network-Specific Considerations

### Hardhat (Local Network)

**Characteristics**:
- ✅ Instant finality
- ✅ Free transactions (no gas cost)
- ✅ Full control (can reset state)
- ✅ Deterministic block generation
- ❌ No cross-network communication
- ❌ Local only (mobile cannot access)

**Best For**: Local testing and development

**Commands**:
```bash
# Start node
npx hardhat node

# Reset blockchain state
npx hardhat node --reset

# View accounts
npx hardhat accounts

# Deploy fresh
npx hardhat run scripts/deploy.js --network hardhat
```

### Sepolia Testnet

**Characteristics**:
- ✅ Public testnet (accessible from anywhere)
- ✅ Real Ethereum behavior simulation
- ✅ Persistent contracts (not reset)
- ✅ Actual block mining (12-15 seconds)
- ❌ Real testnet ETH needed
- ❌ Network-dependent performance

**Best For**: Staging before production

**Gas Estimation**:
```
Move transaction: ~75,000 gas
Current price: ~1-5 Gwei (varies)
Cost: 0.00015-0.00025 ETH (~$0.50-$1 USD)
```

**Monitor Testnet**:
- Block Explorer: https://sepolia.etherscan.io/
- View transactions: Search address in explorer
- Get test ETH: https://sepoliafaucet.com/

### Ethereum Mainnet (Future)

**When Ready**:
1. Security audit of smart contracts
2. Mainnet testnet validation
3. Updated deployment process
4. WalletConnect or similar for key management
5. Production monitoring and alerting

**Configuration**:
```xml
<key>MAINNET_RPC_URL</key>
<string>https://mainnet.infura.io/v3/YOUR_INFURA_KEY</string>
```

---

## Environment-Specific Configurations

### Development Environment

```swift
struct EnvironmentConfiguration {
    static let development = EnvironmentConfig(
        network: .hardhat,
        rpcURL: "http://127.0.0.1:8545",
        factoryAddress: "0x4A679253410272dd5232B3Ff7cF5dbB88f295319",
        requiresSignatureVerification: false
    )
}
```

### Staging Environment

```swift
struct EnvironmentConfiguration {
    static let staging = EnvironmentConfig(
        network: .sepolia,
        rpcURL: "https://sepolia.infura.io/v3/...",
        factoryAddress: "0xa0B53DbDb0052403E38BBC31f01367aC6782118E",
        requiresSignatureVerification: true
    )
}
```

---

## Rollback Procedures

### Scenario 1: Contract Bug Found

**Steps**:
1. Do NOT upgrade contract (immutable)
2. Deploy new contract version with fixes
3. Keep old contract accessible (for data recovery)
4. Update app to use new contract address
5. Release app update

**Configuration Before**:
```json
{
    "factoryAddress": "0xa0B53...BUGGY",
    "version": "1.0.0"
}
```

**Configuration After**:
```json
{
    "factoryAddress": "0x340AC...FIXED",
    "factoryAddressLegacy": "0xa0B53...BUGGY",
    "version": "1.0.1"
}
```

### Scenario 2: RPC Provider Down

**Alternative RPC Providers**:
```swift
let rpcProviders = [
    "https://sepolia.infura.io/v3/YOUR_KEY",           // Primary
    "https://endpoints.omnirpc.io/v1/sepolia/...",     // Secondary
    "https://public.blastapi.io/sepolia",              // Tertiary
]

func connectToFirstAvailableProvider() async throws {
    for rpc in rpcProviders {
        do {
            let web3 = Web3(rpcURL: rpc)
            _ = try await web3.eth.blockNumber()
            return web3  // Connected
        } catch {
            continue  // Try next
        }
    }
    throw NetworkError.allProvidersDown
}
```

---

## Monitoring and Maintenance

### 1. Contract Health Checks

```swift
func performHealthChecks() async {
    do {
        // Check 1: Factory exists
        let factoryCode = try await web3.eth.getCode(at: factoryAddress)
        XCTAssertNotEqual(factoryCode, "0x", "Factory not deployed")

        // Check 2: Can create game
        let gameAddress = try await blockchainService.createGame(by: 0)
        XCTAssertFalse(gameAddress.isEmpty, "Game creation failed")

        // Check 3: Can read state
        let board = try await blockchainService.readBoardState()
        XCTAssertEqual(board.count, 3, "Board invalid")

        print("✅ All health checks passed")
    } catch {
        print("❌ Health check failed: \(error)")
    }
}
```

### 2. Event Log Monitoring

```bash
# Monitor all events in real-time
cast logs --address 0x4A679253410272dd5232B3Ff7cF5dbB88f295319 \
    --follow \
    --rpc-url http://127.0.0.1:8545
```

### 3. Performance Metrics

```swift
func trackTransactionPerformance(txHash: String) async {
    let startTime = Date()

    while true {
        let receipt = try await web3.eth.getTransactionReceipt(byHash: txHash)
        if receipt != nil {
            let duration = Date().timeIntervalSince(startTime)
            let gasUsed = receipt?.gasUsed ?? 0

            print("Transaction: \(txHash)")
            print("Duration: \(duration)s")
            print("Gas used: \(gasUsed)")
            break
        }
        try await Task.sleep(nanoseconds: 500_000_000)  // 0.5s
    }
}
```

---

## Troubleshooting

### Issue: "Contract not found at address"

**Cause**: Contract not deployed or address incorrect

**Solution**:
```bash
# Verify deployment
cast code 0x4A679253410272dd5232B3Ff7cF5dbB88f295319 --rpc-url http://127.0.0.1:8545

# If "0x" returned, redeploy
npx hardhat run scripts/deploy.js --network hardhat
```

---

### Issue: "Connection refused" on Hardhat

**Cause**: Local node not running

**Solution**:
```bash
# In one terminal
npx hardhat node

# Verify it's running
curl http://127.0.0.1:8545 -X POST \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

---

### Issue: "Out of balance" on Sepolia

**Cause**: Not enough testnet ETH for transactions

**Solution**:
```
1. Go to https://sepoliafaucet.com/
2. Enter your wallet address
3. Request testnet ETH
4. Wait 5-10 minutes
5. Verify balance: cast balance <address> --rpc-url $SEPOLIA_RPC_URL
```

---

### Issue: "Invalid gas estimate"

**Cause**: Insufficient balance for gas

**Solution**:
```swift
let balance = try await web3.eth.getBalance(address: playerAddress)
let gasPrice = try await web3.eth.gasPrice()
let estimatedGas = 75_000
let requiredWei = BigInt(estimatedGas) * gasPrice

if balance < requiredWei {
    print("Insufficient balance")
    // Get more testnet ETH or ETH
}
```

---

### Issue: "Nonce too low"

**Cause**: Transaction already processed

**Solution**:
```swift
// Get current nonce
let nonce = try await web3.eth.getTransactionCount(address: playerAddress)

// Create new transaction with correct nonce
let tx = TransactionObject(
    nonce: nonce,
    // ... other params
)
```

---

## Deployment Checklist

### Before Local Deployment
- [ ] All smart contracts compile without errors
- [ ] Local Hardhat node can start
- [ ] Private keys configured in Info.plist

### Before Sepolia Deployment
- [ ] Contracts tested on local Hardhat
- [ ] Testnet ETH available (~0.5 ETH minimum)
- [ ] Infura API key created and configured
- [ ] .env file with private key prepared

### Before Release
- [ ] All contracts deployed and verified
- [ ] Deployment addresses added to app
- [ ] Integration tests passing
- [ ] Performance benchmarks acceptable
- [ ] Error handling implemented
- [ ] Documentation updated

---

**Last Updated**: 2025-11-15
**Document Version**: 1.0.0
