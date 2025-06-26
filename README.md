# Tic-Tac-Toe iOS Ethereum

This is an iOS application that implements a Tic-Tac-Toe game with integration to the Ethereum blockchain.

## Current State

- Integrates with the Ethereum blockchain for game logic.

## Ethereum Integration

The application interacts with the Ethereum blockchain using the `Web3.swift` library.

### Configuration

- **Networks:** Supports both local (Hardhat) and Sepolia testnet.
- **RPC URLs:** Configured via `LOCAL_RPC_URL` and `SEPOLIA_RPC_URL` in `Info.plist` (or environment variables).
- **Private Keys:** Player private keys (`PRIVATE_KEY_HARDHAT_0`, `PRIVATE_KEY_HARDHAT_1`, `PRIVATE_KEY_PLAYER1`, `PRIVATE_KEY_PLAYER2`) are loaded from `Info.plist` (or environment variables) for signing transactions. **Note: Storing private keys directly in `Info.plist` is not secure for production applications.**

### Smart Contracts

- **Factory Contract:** `TicTacToeFactory` (or `TicTacToeFactory_NoErrorTypes`) is used to create new game instances. Its ABI is loaded from `TicTacToeFactory.json` (or `TicTacToeFactory_NoErrorTypes.json`).
- **Game Contract:** `MultiPlayerTicTacToe` represents an individual game instance. Its ABI is loaded from `MultiPlayerTicTacToe.json`.
- **Deployment Addresses:** Contract addresses for both local and Sepolia networks are loaded from `deployment_output_hardhat_local.json` and `deployment_output_sepolia_testnet.json` respectively.

### Key Functionalities (`BlockchainService.swift`)

- **`createGame(by player: Int)`:**
    - Initiates a new Tic-Tac-Toe game on the blockchain.
    - Manually constructs, signs, and sends the transaction.
    - Estimates gas, retrieves nonce, and handles chain ID for signing.
    - Polls for transaction receipt and verifies on-chain status.
    - Parses `GameCreated` event logs to extract the new game contract address.
- **`makeMove(by player: Int, row: UInt8, col: UInt8)`:**
    - Allows a player to make a move on the game board.
    - Similar to `createGame`, it constructs, signs, and sends the transaction.
    - Verifies transaction success and logs `MoveMade` events.
- **`board()`:**
    - Reads the current state of the Tic-Tac-Toe board from the blockchain.
    - Calls the `getBoardState` view function on the game contract.
    - Decodes the `address[3][3]` return type into a Swift `[[String]]`.
- **`checkBlockchainConnection()`:**
    - Verifies connectivity to the configured Ethereum node by fetching the latest block number.
- **`retry<T>(...)` and `retryReceiptFetch(...)`:**
    - Helper functions for robust transaction handling, implementing exponential backoff for retrying failed operations or receipt polling.
- **`loadABI(named: String)`:**
    - Loads contract ABI JSON from the application bundle.
- **`deployment()`:**
    - Loads deployed contract addresses from JSON files based on the selected network.
- **`privKey(_ i: Int)` and `addr(_ pk: String)`:**
    - Utility functions for managing private keys and deriving Ethereum addresses.
- **`emojiForAddress(_ addr: String)`:**
    - A utility to map Ethereum addresses to emojis for UI representation.

### Error Handling

The `BlockchainService` uses an `Err` enum (`noFactory`, `noGame`, `txFail`, `eventMiss`, `decode`) to categorize and throw specific errors during blockchain interactions.

## User Interface (UI) and Game Logic

- **`TicTacToeiOSApp.swift`:** The application's entry point, which loads the `ContentView`.
- **`ContentView.swift`:** The main user interface, built with SwiftUI.
    - **State Management:** Uses `@StateObject` for `BlockchainService` (for blockchain interactions) and `@State` variables for UI-specific data (e.g., `status`, `board`, `rowInput`, `colInput`, `gameAddressInput`, `isLoading`).
    - **Game Flow:**
        1. **Network Selection:** Users can toggle between local (Hardhat) and Sepolia testnet.
        2. **Game Creation/Joining:**
            - **Create Game:** Player 1 can create a new game instance on the blockchain via the `createGame` function in `BlockchainService`.
            - **Join Game:** Users can join an existing game by entering its contract address.
        3. **Making Moves:** Players input row and column (0-2) and submit their move. The `makeMove` function in `BlockchainService` handles the on-chain transaction.
        4. **Board Display:** The game board is rendered dynamically, displaying emojis for player markers (derived from their Ethereum addresses).
        5. **Game Status:** The UI updates with status messages, including transaction progress, errors, and game outcomes (win/draw).
    - **Controls:**
        - **Network Controls:** Toggle between local and Sepolia networks, and print derived player addresses.
        - **Factory Controls:** Create a new game or join an existing one.
        - **Move Controls:** Select current player (signer) and input row/column for moves.
        - **Debug Controls:** Refresh board state, check `gameEnded` status.
        - **Diagnostic Controls:** Test blockchain connection.
    - **Styling:** Uses custom `MatrixTextFieldStyle`, `MatrixButtonStyle`, and `MatrixSecondaryButtonStyle` (defined in `Theme.swift`) to achieve a Matrix-themed aesthetic.

## Game Logic

- **On-Chain Logic:** The core game rules (valid moves, win conditions, draw conditions) are enforced by the `MultiPlayerTicTacToe` smart contract on the Ethereum blockchain.
- **Off-Chain State:** The iOS app fetches the board state from the blockchain and renders it. It also manages local UI state such as current player, input fields, and loading indicators.
- **Winner Determination:** After each move, the app checks the `gameEnded` and `winner` functions on the smart contract to determine if the game has concluded and who won.

## Wallet Integration

Currently, the application handles wallet integration by directly loading private keys from `Info.plist` (or environment variables) and using `Web3.swift`'s `EthereumPrivateKey` for transaction signing. This approach is used for simplicity in development and testing, but it is **not secure for production applications** as it exposes private keys within the app's bundle.

## Gas Management

Transaction gas management is handled programmatically within `BlockchainService.swift`:

- **Nonce:** Retrieved using `web3!.eth.getTransactionCount`.
- **Gas Price:** Fetched using `web3!.eth.gasPrice()`.
- **Gas Limit:** Estimated dynamically using `web3!.eth.estimateGas` based on the transaction's `to` address and `data`.

This ensures that transactions are sent with appropriate gas parameters, though it currently uses a legacy transaction type (`.legacy`) and does not explicitly support EIP-1559 (Type 2) transactions.

## Testing Procedures

Currently, the project lacks a dedicated test suite. Testing has primarily been manual, involving deploying contracts to local Hardhat networks and Sepolia, and interacting with the UI.

## Feature Expansion

Beyond the core Tic-Tac-Toe gameplay on the blockchain, several features could enhance the application:

- **Multiplayer Matchmaking and Lobby System:** Implement a system for players to find and join games, rather than manually sharing contract addresses.
- **Leaderboards:** Track player statistics (wins, losses, draws) and display a global leaderboard.
- **NFT Integration:** Explore using NFTs for unique game pieces, player avatars, or in-game achievements.
- **Custom Game Rules:** Allow players to define custom rules or board sizes.
- **Spectator Mode:** Enable users to watch ongoing games.

## App Store Submission Guidelines and Compliance

Submitting a blockchain-enabled application to the Apple App Store requires careful consideration of their guidelines, particularly regarding cryptocurrency and NFTs. Key areas to address include:

- **Clear Disclosures:** Transparently inform users about the use of blockchain technology, potential transaction fees (gas), and the immutability of on-chain actions.
- **In-App Purchases:** If any in-game items or features involve real money, they must adhere to Apple's in-app purchase mechanisms.
- **Wallet Management:** Ensure that any wallet functionality complies with Apple's security and privacy requirements.
- **Regulatory Compliance:** Adhere to relevant financial regulations in all target regions.

## Enhanced Security Considerations

Security is paramount for blockchain applications. Key areas for improvement include:

- **Private Key Management:** Transition away from storing private keys directly in the app. Implement secure wallet integration (e.g., WalletConnect) or explore hardware wallet integration.
- **Smart Contract Audits:** Conduct professional security audits of the `MultiPlayerTicTacToe` and `TicTacToeFactory` smart contracts to identify and mitigate vulnerabilities.
- **Input Validation:** Implement robust input validation on both the client-side (iOS app) and contract-side to prevent malicious inputs.
- **Transaction Monitoring:** Implement monitoring for suspicious on-chain activity.
- **Dependency Security:** Regularly audit third-party libraries and dependencies for known vulnerabilities.

## Performance Optimization

Optimizing performance is crucial for a smooth user experience, especially with blockchain interactions:

- **RPC Call Optimization:** Minimize unnecessary RPC calls and batch requests where possible.
- **Event Listening:** Efficiently listen for and process blockchain events (e.g., `GameCreated`, `MoveMade`) to update the UI in real-time.
- **UI Responsiveness:** Ensure the UI remains responsive during blockchain transactions and data fetching.
- **Gas Efficiency:** Optimize smart contract code for gas efficiency to reduce transaction costs.

## Comprehensive Documentation

Further expand documentation to include:

- Detailed explanations of the game logic flow, including state transitions and win conditions.
- A breakdown of UI components and their interactions.
- Best practices for development and deployment, including environment setup (Hardhat, Sepolia).
- A guide for contributing to the project.
- Troubleshooting common issues.

