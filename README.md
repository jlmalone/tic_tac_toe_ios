# Tic-Tac-Toe Matrix (iOS Ethereum dApp)

## Overview

Tic-Tac-Toe Matrix is an iOS application that brings the classic game of Tic-Tac-Toe to the blockchain. Game state and moves are recorded as transactions on an Ethereum-compatible network (currently supporting local Hardhat development and the Sepolia testnet). This project demonstrates how to build a decentralized application (dApp) on iOS using Swift and interact with smart contracts.

The application allows users to:
- Connect to the Sepolia testnet (or a local Hardhat node).
- Create new Tic-Tac-Toe games, which deploys a new game contract via a factory contract.
- Join existing games using their contract address.
- View the current game board, with player moves represented by emojis.
- Make moves, which are submitted as signed transactions to the game contract.
- See the game status, including whose turn it is and the eventual winner or a draw.

## Features

- **Decentralized Gameplay:** All game logic and state transitions are handled by smart contracts on the blockchain.
- **Smart Contract Interaction:** Utilizes the `Web3.swift` library for:
    - Connecting to Ethereum nodes via RPC.
    - Reading contract state (e.g., board, game status).
    - Sending signed transactions for actions like creating games and making moves.
    - Client-side private key management for signing transactions.
- **SwiftUI Interface:** A modern, responsive UI built with SwiftUI, styled with a "Matrix" theme.
- **Network Flexibility:** Supports:
    - **Sepolia Testnet:** For playing against others on a public test network.
    - **Local Hardhat Node:** For development and testing.
- **Event Parsing:** Parses event logs from transaction receipts to retrieve crucial data, such as the address of newly created game contracts.
- **Robust Transaction Handling:** Implements manual transaction signing and sending (`eth_sendRawTransaction`) and includes a retry mechanism with exponential backoff for fetching transaction receipts.

## Core Technologies & Libraries

- **Swift & SwiftUI:** For the iOS application development.
- **Web3.swift (version 0.8.8):** The primary library for interacting with the Ethereum blockchain.
    - `Web3ContractABI`: For working with smart contract ABIs.
    - `Web3PromiseKit`: For handling asynchronous operations with Promises (bridged to Swift Concurrency `async/await`).
- **Smart Contracts (Solidity):** (Assumed to be in a separate project/repository)
    - `TicTacToeFactory.sol`: A factory contract to deploy new game instances.
    - `MultiPlayerTicTacToe.sol`: The contract handling the actual game logic for a single Tic-Tac-Toe match.
- **Alchemy:** Used as the RPC provider for connecting to the Sepolia testnet.
- **Xcode:** The development environment for the iOS application.

## Project Structure (iOS App)

- **`BlockchainService.swift`**: The core service class responsible for all Web3 interactions, including:
    - Managing network connections (Local/Sepolia).
    - Loading contract ABIs and deployment addresses.
    - Initializing contract objects.
    - Constructing, signing, and sending transactions (`createGame`, `makeMove`).
    - Fetching and processing transaction receipts and event logs.
    - Reading contract state (`getBoardState`, `gameEnded`, `winner`).
    - Handling private keys (loaded from `Info.plist`).
- **`ContentView.swift`**: The main SwiftUI view that orchestrates the UI, manages app state, and calls `BlockchainService` methods in response to user actions.
- **`Theme.swift`**: Defines custom SwiftUI styles and colors for the "Matrix" theme.
- **`DeploymentAddress.swift`**: Codable struct for parsing deployment output JSON files.
- **`Info.plist` (and `.env` via `update_info_plist.sh` script):** Manages configuration like private keys, RPC URLs, and chain IDs.
- **ABI JSON Files (`TicTacToeFactory_NoErrorTypes.json`, `MultiPlayerTicTacToe.json`):** Contract ABIs included in the app bundle.
- **Deployment Output JSON Files (`deployment_output_sepolia_testnet.json`, `deployment_output_hardhat_local.json`):** Store deployed contract addresses for different networks.

## Getting Started

### Prerequisites

-   Xcode (latest stable version recommended).
-   An iOS device or Simulator.
-   An Alchemy account and API key for Sepolia (or another Sepolia RPC endpoint).
-   Sepolia ETH in your test accounts (Player 1 and Player 2) for paying gas fees. You can get this from a Sepolia faucet.
-   (For local development) A running Hardhat node.

### Configuration

1.  **Clone the repository.**
2.  **Create a `.env` file** in the root of the iOS project directory (`tic_tac_toe_ios_ethereum`). Populate it with your private keys and Alchemy API key. Refer to the `.env.example` file (if provided) or the required keys in `update_info_plist.sh`:
    ```env
    PRIVATE_KEY_PLAYER1=YOUR_SEPOLIA_PLAYER1_PRIVATE_KEY_NO_0x_PREFIX
    PRIVATE_KEY_PLAYER2=YOUR_SEPOLIA_PLAYER2_PRIVATE_KEY_NO_0x_PREFIX
    SEPOLIA_RPC_URL=YOUR_ALCHEMY_SEPOLIA_RPC_URL_WITH_API_KEY
    SEPOLIA_CHAIN_ID=11155111

    # For local Hardhat development
    PRIVATE_KEY_HARDHAT_0=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
    PRIVATE_KEY_HARDHAT_1=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
    LOCAL_RPC_URL=http://127.0.0.1:8545
    HARDHAT_CHAIN_ID=31337
    ```
3.  **Ensure Smart Contracts are Deployed:**
    *   Deploy your `TicTacToeFactory` and `MultiPlayerTicTacToe` (implementation contract) to the Sepolia testnet.
    *   Update `tic_tac_toe_ios_ethereum/deployment_output_sepolia_testnet.json` with the deployed `factoryAddress` (and `gameImplementationAddress` if your factory uses a beacon/proxy pattern).
    *   For local development, deploy to your Hardhat node and update `tic_tac_toe_ios_ethereum/deployment_output_hardhat_local.json`.
4.  **Ensure ABI Files are Correct:**
    *   Place your compiled ABI JSON for `MultiPlayerTicTacToe` as `MultiPlayerTicTacToe.json` in the `tic_tac_toe_ios_ethereum` folder.
    *   Place your compiled ABI JSON for `TicTacToeFactory` as `TicTacToeFactory.json` in the same folder.
    *   Run the `modify_abi.sh` script (or manually create `TicTacToeFactory_NoErrorTypes.json` by removing `"type": "error"` entries from `TicTacToeFactory.json`) to generate the ABI compatible with `Web3.swift 0.8.8`.
5.  **Build Script for Info.plist:**
    *   The project includes an `update_info_plist.sh` script. Ensure it's executable (`chmod +x update_info_plist.sh`).
    *   This script is set up as a "Run Script Phase" in Xcode's Build Phases to run before "Compile Sources." It copies values from `.env` to the app's `Info.plist`.
6.  **Open in Xcode:** Open the `.xcodeproj` or `.xcworkspace` file.
7.  **Build and Run:** Select your target device/simulator and run the app.

### How to Play

1.  The app should start connected to the SEPOLIA network by default (or LOCAL if `useLocal` in `BlockchainService` is initially true).
2.  Click **"Create Game (P1)"**. This will send a transaction. Wait for confirmation (the UI status will update, and the new game address will appear).
3.  The game board should load. Initially, it will be empty.
4.  The current signer is P1. Enter a row (0-2) and column (0-2).
5.  Click **"Make Move"**. This sends another transaction.
6.  After the move is confirmed, the board should update.
7.  To play as P2, click the "Signer: P1..." button to toggle to P2. The displayed address will change. P2 can then make a move.
8.  Continue until a player wins or the game is a draw.

## Current Status & Known Issues

-   **Game Creation:** Successfully working on Sepolia. Transactions are client-side signed and sent via `eth_sendRawTransaction`. Receipt fetching includes a retry mechanism.
-   **Board Display:** Successfully decodes and displays the board state after a game is created/joined. Empty cells (Zero Address) are displayed as empty.
-   **Make Move:** The `makeMove` function in `BlockchainService` has been implemented with the same manual signing and sending pattern as `createGame`. UI integration in `ContentView` calls this service method. **Further testing on this flow is the immediate next step.**
-   **Error Handling:** Basic error handling is in place, displaying messages in the UI.
-   **`Web3.swift` Version:** Uses version 0.8.8. This required a workaround for ABI parsing (removing `"type": "error"` entries) as this version had issues with that ABI feature.

## Future Enhancements (Potential)

-   Update `Web3.swift` to a newer version to potentially remove ABI workarounds and gain access to newer features/bugfixes.
-   More sophisticated UI/UX for player turns, game over states, and error feedback.
-   Displaying transaction hashes or links to Etherscan.
-   Support for EIP-1559 transactions (currently using legacy type).
-   Local game history or statistics.
-   Improved visual indication of whose turn it is.

## Contribution

This project is primarily a demonstration and learning tool. Feel free to fork, experiment, and adapt.

---
