# CLAUDE.md — tic_tac_toe_ios_ethereum

## Tic-Tac-Toe Blockchain Ecosystem

This project is part of a 7-project ecosystem. **Flagship:** [tic-tac-toe-eth-react](~/WebstormProjects/tic-tac-toe-eth-react/) ([ECOSYSTEM.md](~/WebstormProjects/tic-tac-toe-eth-react/ECOSYSTEM.md))

| Project | Path | Chain | Status |
|---------|------|-------|--------|
| **tic-tac-toe-eth-react** (flagship) | `~/WebstormProjects/tic-tac-toe-eth-react/` | ETH Sepolia | Live |
| tic-tac-toe-smart-contract | `~/tic-tac-toe-smart-contract/` | ETH Sepolia | Deployed |
| tic_tac_toe_android | `~/StudioProjects/tic_tac_toe_android/` | ETH Sepolia | Working |
| **tic_tac_toe_ios_ethereum** (this repo) | `~/ios_code/tic_tac_toe_ios_ethereum/` | ETH Sepolia | Working |
| tic_tac_toe_compose | `~/IdeaProjects/tic_tac_toe_compose/` | ETH Sepolia | **BROKEN** |
| tic-tac-toe-cli | `~/IdeaProjects/tic-tac-toe-cli/` | ETH Sepolia | Working |
| tic-tac-toe-sol | `~/RustroverProjects/tic-tac-toe-sol/` | Solana Devnet | Deployed |

**Shared Addresses (Sepolia):** Factory `0xa0B53DbDb0052403E38BBC31f01367aC6782118E` / Game `0x340AC014d800Ac398Af239Cebc3a376eb71B0353`

---

## Project Overview

SwiftUI iOS client for the Tic-Tac-Toe smart contract system. Connects to Ethereum Sepolia via Web3.swift.

## Tech Stack

- **SwiftUI** for UI
- **Web3.swift** for Ethereum interaction
- **XCTest** for testing

## Contract Integration

- Factory + Game ABIs manually encoded in BlockchainService
- Network selection: Hardhat local or Sepolia testnet
- Config in `Info.plist` (RPC URLs, private keys)

## Security Warning

**Private keys are stored in Info.plist — NOT production-ready.** Keys are readable in the app bundle. Move to keychain or wallet delegation for production.

## Key Functions

- `createGame(by player:)` — Manual transaction construction to deploy game
- `makeMove(by player:, row:, col:)` — On-chain move submission
- `board()` — Read board state
- `checkBlockchainConnection()` — Connectivity verification

## Build & Run

Open in Xcode, select iOS simulator or device, build and run. Requires MetaMask-compatible wallet or direct private key (dev only).
