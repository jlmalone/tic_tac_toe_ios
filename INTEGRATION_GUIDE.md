# Integration Guide: Using the Ethereum Database

## Quick Start

### 1. Initialize BlockchainService

```swift
import SwiftUI

@main
struct TicTacToeiOSApp: App {
    @StateObject var blockchainService = BlockchainService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(blockchainService)
        }
    }
}
```

### 2. Access Blockchain Service in Views

```swift
struct ContentView: View {
    @EnvironmentObject var blockchainService: BlockchainService

    var body: some View {
        VStack {
            Text("Factory: \(blockchainService.factoryAddress ?? "Loading...")")
            Button("Create Game") {
                Task {
                    let gameAddress = try await blockchainService.createGame(by: 0)
                    blockchainService.currentGameAddress = gameAddress
                }
            }
        }
    }
}
```

### 3. Read Board State

```swift
Task {
    let board = try await blockchainService.readBoardState()
    print(board)  // [[String]] with 9 addresses
}
```

### 4. Make a Move

```swift
Task {
    try await blockchainService.makeMove(by: 0, row: 0, col: 0)
}
```

---

## Complete API Reference

### BlockchainService Class

**File**: `/tic_tac_toe_ios/BlockchainService.swift`

#### Published Properties

| Property | Type | Mutable | Purpose |
|----------|------|---------|---------|
| `useLocal` | Bool | Yes | Toggle local vs testnet |
| `factoryAddress` | String? | Yes | Active factory address |
| `currentGameAddress` | String? | Yes | Current game contract address |
| `player1` | String | No | Player 1 address (read-only) |
| `player2` | String | No | Player 2 address (read-only) |
| `rpcURL` | String | No | RPC endpoint (read-only) |

#### Methods

##### createGame(by player: Int) -> String

```swift
func createGame(by player: Int) -> String
```

**Purpose**: Create a new game instance

**Parameters**:
- `player`: 0 or 1 (which player initiates)

**Returns**: Game contract address (String)

**Throws**:
- Network errors
- Invalid player index
- RPC errors

**Example**:
```swift
do {
    let gameAddress = try await blockchainService.createGame(by: 0)
    print("Game created: \(gameAddress)")
} catch {
    print("Error: \(error)")
}
```

**Gas Cost**: ~180,000

---

##### makeMove(by player: Int, row: UInt8, col: UInt8)

```swift
func makeMove(by player: Int, row: UInt8, col: UInt8)
```

**Purpose**: Make a move on the current game

**Parameters**:
- `player`: 0 or 1 (player making move)
- `row`: 0-2 (row coordinate)
- `col`: 0-2 (column coordinate)

**Throws**:
- "Cell already occupied"
- "Cannot play twice"
- "Invalid coordinates"
- "Game already ended"
- Network errors

**Example**:
```swift
do {
    try await blockchainService.makeMove(by: 0, row: 1, col: 1)
    print("Move successful")
} catch {
    print("Move failed: \(error)")
}
```

**Gas Cost**: 75,000

---

##### readBoardState() -> [[String]]

```swift
func readBoardState() -> [[String]]
```

**Purpose**: Get current board state

**Returns**: 3×3 array of addresses (or empty strings for empty cells)

**Example**:
```swift
let board = try await blockchainService.readBoardState()
for (row, cells) in board.enumerated() {
    for (col, cell) in cells.enumerated() {
        print("[\(row)][\(col)]: \(cell)")
    }
}
```

**Response Format**:
```swift
[
    ["0xaddr1", "", "0xaddr2"],
    ["", "0xaddr1", ""],
    ["", "", ""]
]
```

---

##### checkBlockchainConnection()

```swift
func checkBlockchainConnection()
```

**Purpose**: Verify RPC connection works

**Throws**: Network errors if connection fails

**Example**:
```swift
do {
    try await blockchainService.checkBlockchainConnection()
    print("Connected!")
} catch {
    print("Connection failed: \(error)")
}
```

---

### Configuration

#### Using Local Hardhat Network

```swift
blockchainService.useLocal = true
```

**Deployment Addresses**:
- Factory: `0x4A679253410272dd5232B3Ff7cF5dbB88f295319`
- Game: `0xa85233C63b9Ee964Add6F2cffe00Fd84eb32338f`
- RPC URL: `http://127.0.0.1:8545`

---

#### Using Sepolia Testnet

```swift
blockchainService.useLocal = false
```

**Deployment Addresses**:
- Factory: `0xa0B53DbDb0052403E38BBC31f01367aC6782118E`
- Game: `0x340AC014d800Ac398Af239Cebc3a376eb71B0353`
- RPC URL: `https://sepolia.infura.io/v3/...`

---

## Common Patterns

### Pattern 1: Game Creation Workflow

```swift
func startNewGame() {
    Task {
        do {
            // 1. Create game
            let gameAddress = try await blockchainService.createGame(by: 0)

            // 2. Store address
            blockchainService.currentGameAddress = gameAddress

            // 3. Initialize board
            self.board = try await blockchainService.readBoardState()

            // 4. Show success
            self.status = "Game created: \(gameAddress)"
        } catch {
            self.status = "Error: \(error)"
        }
    }
}
```

---

### Pattern 2: Making a Move with Validation

```swift
func makePlayerMove(row: Int, col: Int) {
    Task {
        do {
            // 1. Validate input
            guard row >= 0 && row <= 2 && col >= 0 && col <= 2 else {
                self.status = "Invalid coordinates"
                return
            }

            // 2. Check cell is empty
            let board = try await blockchainService.readBoardState()
            guard board[row][col].isEmpty || board[row][col] == "0x0000000000000000000000000000000000000000" else {
                self.status = "Cell already occupied"
                return
            }

            // 3. Set loading state
            self.isLoading = true

            // 4. Send move
            try await blockchainService.makeMove(
                by: currentPlayerIdx,
                row: UInt8(row),
                col: UInt8(col)
            )

            // 5. Update board
            self.board = try await blockchainService.readBoardState()

            // 6. Switch player
            self.currentPlayerIdx = (self.currentPlayerIdx + 1) % 2

            self.status = "Move successful"
        } catch {
            self.status = "Error: \(error)"
        }
        self.isLoading = false
    }
}
```

---

### Pattern 3: Polling for Game Updates

```swift
func startPollingForMoves() {
    Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
        Task {
            do {
                let newBoard = try await blockchainService.readBoardState()
                if newBoard != self.board {
                    self.board = newBoard
                    // Opponent made a move
                    self.currentPlayerIdx = (self.currentPlayerIdx + 1) % 2
                }
            } catch {
                print("Poll error: \(error)")
            }
        }
    }
}
```

---

### Pattern 4: Checking Game Result

```swift
func checkGameResult() async {
    do {
        // Get all events
        let allEvents = try await web3.eth.getLogs(
            address: blockchainService.currentGameAddress ?? "",
            topics: []
        )

        // Check for GameWon
        let wonEvents = allEvents.filter {
            $0.topics[0].contains("GameWon")
        }

        if let wonEvent = wonEvents.first {
            let winner = wonEvent.topics[1]
            if winner.lowercased().contains(blockchainService.player1.lowercased()) {
                self.status = "Player 1 Won!"
            } else {
                self.status = "Player 2 Won!"
            }
        }

        // Check for GameDraw
        let drawEvents = allEvents.filter {
            $0.topics[0].contains("GameDraw")
        }

        if !drawEvents.isEmpty {
            self.status = "Game is a Draw!"
        }
    } catch {
        print("Error: \(error)")
    }
}
```

---

## Error Handling

### Common Errors and Solutions

| Error | Cause | Solution |
|-------|-------|----------|
| "Cell already occupied" | Move to filled cell | Check cell before move |
| "Cannot play twice" | Same player twice | Wait for other player |
| "Invalid coordinates" | Row/col outside 0-2 | Validate input range |
| "Game already ended" | Move in finished game | Check gameEnded flag |
| Network timeout | RPC slow/down | Retry with backoff |
| "Connection refused" | RPC unreachable | Switch to backup RPC |

### Error Handling Example

```swift
func handleMoveError(_ error: Error) {
    let errorMessage: String

    switch error {
    case let networkError as NetworkError:
        errorMessage = "Network error: \(networkError.localizedDescription)"
    case let contractError where contractError.localizedDescription.contains("already occupied"):
        errorMessage = "Cell is already taken"
    case let contractError where contractError.localizedDescription.contains("Cannot play twice"):
        errorMessage = "You already moved, wait for opponent"
    default:
        errorMessage = "Error: \(error.localizedDescription)"
    }

    self.status = errorMessage
    print(errorMessage)
}
```

---

## Performance Tips

### 1. Batch Board Reads

**Inefficient** ❌:
```swift
let cell_0_0 = try await readCell(0, 0)
let cell_0_1 = try await readCell(0, 1)
let cell_0_2 = try await readCell(0, 2)
// ... 9 separate calls
```

**Efficient** ✅:
```swift
let board = try await blockchainService.readBoardState()
// Single call returns all 9 cells
```

---

### 2. Cache Board State

```swift
@State private var cachedBoard: [[String]]?
@State private var lastUpdateTime: Date = Date()

func getBoardWithCache() async throws -> [[String]] {
    // Return cached if less than 2 seconds old
    if let cached = cachedBoard,
       Date().timeIntervalSince(lastUpdateTime) < 2 {
        return cached
    }

    // Fetch fresh
    let fresh = try await blockchainService.readBoardState()
    self.cachedBoard = fresh
    self.lastUpdateTime = Date()
    return fresh
}
```

---

### 3. Use Task Groups for Parallel Operations

```swift
async let gameEnded = getGameEnded()
async let winner = getWinner()
async let board = readBoardState()

let (isEnded, winnerAddr, boardState) = try await (gameEnded, winner, board)
```

---

### 4. Implement Exponential Backoff for Retries

```swift
func executeWithRetry(
    maxAttempts: Int = 3,
    delayMs: Int = 1000
) async throws {
    var lastError: Error?
    var delay = delayMs

    for attempt in 1...maxAttempts {
        do {
            try await blockchainService.readBoardState()
            return
        } catch {
            lastError = error
            if attempt < maxAttempts {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000))
                delay *= 2  // Exponential backoff
            }
        }
    }

    throw lastError ?? NSError(domain: "Retry failed", code: -1)
}
```

---

## Testing

### Unit Test Example

```swift
import XCTest

class BlockchainServiceTests: XCTestCase {
    var sut: BlockchainService!

    override func setUp() {
        super.setUp()
        sut = BlockchainService()
        sut.useLocal = true
    }

    func testCreateGame() async throws {
        let gameAddress = try await sut.createGame(by: 0)
        XCTAssertFalse(gameAddress.isEmpty)
        XCTAssertTrue(gameAddress.hasPrefix("0x"))
    }

    func testReadEmptyBoard() async throws {
        let gameAddress = try await sut.createGame(by: 0)
        sut.currentGameAddress = gameAddress

        let board = try await sut.readBoardState()
        XCTAssertEqual(board.count, 3)
        XCTAssertEqual(board[0].count, 3)
    }

    func testMakeMove() async throws {
        let gameAddress = try await sut.createGame(by: 0)
        sut.currentGameAddress = gameAddress

        try await sut.makeMove(by: 0, row: 0, col: 0)

        let board = try await sut.readBoardState()
        XCTAssertFalse(board[0][0].isEmpty)
    }
}
```

---

## Migration Guide: Adding New Features

### Example: Add Chat Messages to Game

**Step 1**: Update smart contract (new version)

```solidity
event MessageSent(address indexed sender, string message);

function sendMessage(string memory message) public {
    require(gameEnded == false, "Game already ended");
    emit MessageSent(msg.sender, message);
}
```

**Step 2**: Update BlockchainService

```swift
func sendMessage(_ message: String) async throws {
    let data = encodeFunction("sendMessage", params: [message])
    try await web3.eth.sendTransaction(
        to: currentGameAddress,
        data: data,
        from: playerAddress
    )
}
```

**Step 3**: Update UI to show messages

```swift
func listenForMessages() {
    let filter = EventFilter(
        address: currentGameAddress,
        topics: ["0x" + keccak256("MessageSent(address,string)")]
    )

    web3.eth.filter(filter) { event in
        if let messageEvent = event as? MessageSentEvent {
            self.messages.append((
                sender: messageEvent.sender,
                text: messageEvent.message
            ))
        }
    }
}
```

---

## Best Practices

1. **Always validate input** before sending transactions
2. **Handle errors gracefully** with meaningful messages
3. **Cache data** to reduce RPC calls
4. **Use polling** for real-time updates (or Event filters)
5. **Test thoroughly** on Hardhat local before Sepolia
6. **Check gas balance** before making moves
7. **Implement timeouts** for long-running operations
8. **Log all errors** for debugging

---

## Troubleshooting

### Issue: "Connection refused"

**Solution**: Ensure Hardhat node is running

```bash
npx hardhat node
```

### Issue: "Invalid RPC URL"

**Solution**: Check Info.plist for correct RPC URL

```xml
<key>LOCAL_RPC_URL</key>
<string>http://127.0.0.1:8545</string>
```

### Issue: "Out of gas"

**Solution**: Increase gas limit in transaction

```swift
let tx = TransactionObject(
    gasLimit: 200_000  // Increase from default
)
```

### Issue: "No contract at address"

**Solution**: Ensure contract deployed and address is correct

```swift
let code = try await web3.eth.getCode(at: gameAddress)
if code == "0x" {
    print("No contract at this address")
}
```

---

## Resources

- [Database Schema Documentation](./DATABASE_SCHEMA.md)
- [Deployment Guide](./DEPLOYMENT.md)
- [Performance Optimization Guide](./PERFORMANCE.md)
- [Web3.swift Documentation](https://github.com/Boilertalk/Web3.swift)
- [Ethereum JSON-RPC API](https://ethereum.org/en/developers/docs/apis/json-rpc/)
- [Smart Contract ABI Specification](https://docs.soliditylang.org/en/latest/abi-spec.html)

---

**Last Updated**: 2025-11-15
**Document Version**: 1.0.0
