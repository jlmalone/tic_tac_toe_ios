//
//  BlockchainService.swift
//  tic_tac_toe_ios_ethereum
//
//  Created by Agent Malone on 5/13/25.
//

import Foundation
import SwiftUI // Needed for ObservableObject and @Published
import Web3
import Web3Contract // For Contract
import Web3PromiseKit // For async/await support on promises
import CryptoKit // For SHA256 hashing in emoji helper
import BigInt // For Chain ID

// --- Constants ---
let ZERO_ADDRESS_STRING = "0x0000000000000000000000000000000000000000"

// --- Configuration (Loaded from Info.plist) ---
private let infoDict = Bundle.main.infoDictionary

// Attempt to load configuration from Info.plist, fallback to safe defaults or placeholders
private let PKS_LOCAL = [
    infoDict?["PRIVATE_KEY_HARDHAT_0"] as? String ?? "0xMissingHardhatPK0_Fallback",
    infoDict?["PRIVATE_KEY_HARDHAT_1"] as? String ?? "0xMissingHardhatPK1_Fallback"
]
private let PKS_SEPOLIA = [
    infoDict?["PRIVATE_KEY_PLAYER1"] as? String ?? "0xMissingSepoliaPK1_Fallback",
    infoDict?["PRIVATE_KEY_PLAYER2"] as? String ?? "0xMissingSepoliaPK2_Fallback"
]

private let RPC_URL_LOCAL = infoDict?["LOCAL_RPC_URL"] as? String ?? "http://127.0.0.1:8545/" // Default if not in Plist
private let RPC_URL_SEPOLIA = infoDict?["SEPOLIA_RPC_URL"] as? String ?? "https://sepolia.infura.io/v3/YOUR_INFURA_OR_ALCHEMY_KEY" // Default if not in Plist

private let CHAIN_ID_LOCAL = BigInt(infoDict?["HARDHAT_CHAIN_ID"] as? String ?? "31337") ?? BigInt(31337)
private let CHAIN_ID_SEPOLIA = BigInt(infoDict?["SEPOLIA_CHAIN_ID"] as? String ?? "11155111") ?? BigInt(11155111)


// --- The Real Blockchain Brain ---

@MainActor // Makes sure changes happen on the main thread for the UI
class BlockchainService: ObservableObject {

    // --- UI Reactive Properties ---
    @Published var isLocal: Bool = {
        // Determine initial network state based on some logic, e.g., a default or last used.
        // For simplicity, defaulting to true (local).
        // In a real app, you might save the user's last preference.
        return true
    }() {
        didSet {
            if oldValue != isLocal {
                print("BlockchainService: Network switch detected. Reinitializing client for \(isLocal ? "LOCAL" : "SEPOLIA").")
                reinitializeClient()
            }
        }
    }

    @Published var factoryAddress: String? = nil
    @Published var currentGameAddress: String? = nil {
        didSet {
            if oldValue != currentGameAddress {
                print("BlockchainService: currentGameAddress changed to \(currentGameAddress ?? "nil"). Updating game contract instance.")
                updateGameContractInstance()
            }
        }
    }

    @Published var player1Address: String = "Loading P1 Addr..."
    @Published var player2Address: String = "Loading P2 Addr..."
    @Published var rpcUrlString: String = "Loading RPC..."
    @Published var chainIdDisplay: String = "Loading ChainID..." // Renamed to avoid conflict with internal BigInt chainId

    // --- Internal State ---
    private var deploymentInfo: DeploymentAddresses? // Loaded from bundled JSON
    private var web3: Web3! // Force unwrapped after initialization
    private var currentChainId: BigInt = CHAIN_ID_LOCAL // Internal BigInt representation

    // ABI strings and Contract instances
    private var gameContractABIString: String?
    private var factoryContractABIString: String?
    private var gameContract: StaticContract?
    private var factoryContract: StaticContract?

    // --- Initialization ---
    init() {
        print("BlockchainService: Initializing...")

        gameContractABIString = loadContractABI(fileName: "MultiPlayerTicTacToe")
        factoryContractABIString = loadContractABI(fileName: "TicTacToeFactory")

        // Initial client setup based on the default `isLocal` state
        reinitializeClient()
        printDerivedAddresses() // Print addresses after initial setup
    }

    // --- Client and Configuration Management ---
    func reinitializeClient() {
        let networkName = isLocal ? "LOCAL (Hardhat)" : "SEPOLIA Testnet"
        print("BlockchainService: Reinitializing Web3 client for \(networkName)...")

        let newRpcUrl = isLocal ? RPC_URL_LOCAL : RPC_URL_SEPOLIA
        let newChainId = isLocal ? CHAIN_ID_LOCAL : CHAIN_ID_SEPOLIA

        self.rpcUrlString = newRpcUrl
        self.chainIdDisplay = newChainId.description
        self.currentChainId = newChainId

        guard let providerUrl = URL(string: newRpcUrl) else {
            print("BlockchainService: ERROR - Invalid RPC URL: \(newRpcUrl). Web3 client cannot be initialized.")
            // Consider setting an error state for the UI
            self.web3 = nil // Ensure web3 is nil if setup fails
            return
        }
        self.web3 = Web3(provider: Web3HttpProvider(url: providerUrl))
        print("BlockchainService: Web3 client initialized with RPC: \(newRpcUrl), Chain ID: \(newChainId)")

        // Load deployment addresses for the current network
        self.deploymentInfo = loadDeploymentInfo() // This depends on the current 'isLocal' state
        self.factoryAddress = self.deploymentInfo?.factoryAddress
        print("BlockchainService: Factory address for \(networkName) set to: \(self.factoryAddress ?? "Not found")")

        // Clear game-specific state
        self.currentGameAddress = nil // This will trigger updateGameContractInstance via didSet

        // Update player addresses
        updatePlayerAddresses()

        // Update contract instances
        updateFactoryContractInstance() // Game contract instance will be updated when currentGameAddress is set

        print("BlockchainService: Client reinitialization for \(networkName) complete.")
        // printDerivedAddresses() // Optionally print addresses again after reinit
    }

    private func updatePlayerAddresses() {
        let pk1Hex = isLocal ? PKS_LOCAL[0] : PKS_SEPOLIA[0]
        let pk2Hex = isLocal ? PKS_LOCAL[1] : PKS_SEPOLIA[1]

        do {
            let pk1 = try EthereumPrivateKey(hex: pk1Hex)
            self.player1Address = pk1.address.hex(eip55: true)
        } catch {
            print("BlockchainService: ERROR - Failed to derive Player 1 address from PK: \(pk1Hex). Error: \(error)")
            self.player1Address = "P1 Addr Error"
        }

        do {
            let pk2 = try EthereumPrivateKey(hex: pk2Hex)
            self.player2Address = pk2.address.hex(eip55: true)
        } catch {
            print("BlockchainService: ERROR - Failed to derive Player 2 address from PK: \(pk2Hex). Error: \(error)")
            self.player2Address = "P2 Addr Error"
        }
    }

    private func loadDeploymentInfo() -> DeploymentAddresses? {
        let fileName = isLocal ? "deployment_output_hardhat_local" : "deployment_output_sepolia_testnet"
        print("BlockchainService: Attempting to load deployment info from \(fileName).json")

        guard let url = Bundle.main.url(forResource: fileName, withExtension: "json") else {
            print("BlockchainService: ERROR - Could not find \(fileName).json in app bundle.")
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(DeploymentAddresses.self, from: data)
            print("BlockchainService: Successfully loaded deployment info for \(isLocal ? "Local" : "Sepolia"). Factory: \(decoded.factoryAddress ?? "None")")
            return decoded
        } catch {
            print("BlockchainService: ERROR - Loading or decoding \(fileName).json: \(error)")
            return nil
        }
    }

    private func loadContractABI(fileName: String) -> String? {
        print("BlockchainService: Attempting to load ABI from \(fileName).json")
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "json") else {
            print("BlockchainService: ERROR - Could not find ABI file \(fileName).json in app bundle.")
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            guard let jsonObject = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                  let abiArray = jsonObject["abi"] else {
                print("BlockchainService: ERROR - 'abi' key not found or invalid structure in \(fileName).json.")
                return nil
            }
            let abiData = try JSONSerialization.data(withJSONObject: abiArray, options: [.prettyPrinted]) // Use .prettyPrinted for debug, .fragmentsAllowed if it's just an array
            guard let abiString = String(data: abiData, encoding: .utf8) else {
                print("BlockchainService: ERROR - Could not convert ABI data to string for \(fileName).json.")
                return nil
            }
            print("BlockchainService: Successfully loaded ABI for \(fileName).")
            return abiString
        } catch {
            print("BlockchainService: ERROR - Loading or parsing ABI file \(fileName).json: \(error)")
            return nil
        }
    }

    private func updateGameContractInstance() {
        guard let gameAddrHex = self.currentGameAddress, !gameAddrHex.isEmpty else {
            print("BlockchainService: Game address is nil or empty. Clearing game contract instance.")
            self.gameContract = nil
            return
        }
        guard let abiStr = self.gameContractABIString else {
            print("BlockchainService: ERROR - Game contract ABI string is missing. Cannot create instance.")
            self.gameContract = nil
            return
        }
        guard let web3 = self.web3 else {
            print("BlockchainService: ERROR - Web3 client not initialized. Cannot create game contract instance.")
            self.gameContract = nil
            return
        }
        guard let address = try? EthereumAddress(hex: gameAddrHex, eip55: false) else {
            print("BlockchainService: ERROR - Invalid game contract address format: \(gameAddrHex).")
            self.gameContract = nil
            return
        }

        print("BlockchainService: Creating/Updating game contract instance for address: \(gameAddrHex)")
        self.gameContract = web3.eth.Contract(json: abiStr, address: address)
        if self.gameContract == nil {
            print("BlockchainService: ERROR - Failed to create StaticContract instance for game contract.")
        } else {
            print("BlockchainService: Game contract instance created successfully for \(gameAddrHex).")
        }
    }

    private func updateFactoryContractInstance() {
        guard let factoryAddrHex = self.factoryAddress, !factoryAddrHex.isEmpty else {
            print("BlockchainService: Factory address is nil or empty. Clearing factory contract instance.")
            self.factoryContract = nil
            return
        }
        guard let abiStr = self.factoryContractABIString else {
            print("BlockchainService: ERROR - Factory contract ABI string is missing. Cannot create instance.")
            self.factoryContract = nil
            return
        }
        guard let web3 = self.web3 else {
            print("BlockchainService: ERROR - Web3 client not initialized. Cannot create factory contract instance.")
            self.factoryContract = nil
            return
        }
        guard let address = try? EthereumAddress(hex: factoryAddrHex, eip55: false) else {
            print("BlockchainService: ERROR - Invalid factory contract address format: \(factoryAddrHex).")
            self.factoryContract = nil
            return
        }

        print("BlockchainService: Creating/Updating factory contract instance for address: \(factoryAddrHex)")
        self.factoryContract = web3.eth.Contract(json: abiStr, address: address)
        if self.factoryContract == nil {
            print("BlockchainService: ERROR - Failed to create StaticContract instance for factory contract.")
        } else {
            print("BlockchainService: Factory contract instance created successfully for \(factoryAddrHex).")
        }
    }

    func getPlayerCredentials(forPlayer index: Int) throws -> EthereumPrivateKey {
        let pkHex = isLocal ? PKS_LOCAL[index] : PKS_SEPOLIA[index]
        do {
            return try EthereumPrivateKey(hex: pkHex)
        } catch {
            print("BlockchainService: ERROR - Creating private key from hex for player \(index + 1). PK Hex: \(pkHex). Error: \(error)")
            throw NSError(domain: "BlockchainService", code: BlockchainErrorCode.invalidPrivateKeyFormat.rawValue, userInfo: [NSLocalizedDescriptionKey: "Invalid private key format for player \(index + 1). Check Info.plist."])
        }
    }

    func getPlayerCount() -> Int {
        return 2
    }

    func printDerivedAddresses() {
        print("── Blockchain Service Status ──")
        print("Network: \(isLocal ? "LOCAL (Hardhat)" : "SEPOLIA Testnet")")
        print("RPC URL: \(rpcUrlString)")
        print("Chain ID: \(chainIdDisplay)")
        print("P1 Address: \(player1Address)")
        print("P2 Address: \(player2Address)")
        print("Factory Address: \(factoryAddress ?? "Not Loaded/Set")")
        print("Current Game Address: \(currentGameAddress ?? "None")")
        print("Game Contract Instance: \(gameContract != nil ? "Initialized" : "Not Initialized")")
        print("Factory Contract Instance: \(factoryContract != nil ? "Initialized" : "Not Initialized")")
        print("─────────────────────────────")
    }

    // --- Blockchain Read Functions ---
    func readBool(fnName: String) async throws -> Bool {
        print("BlockchainService: Reading bool function '\(fnName)'...")
        guard let contract = gameContract else {
            throw NSError(domain: "BlockchainService", code: BlockchainErrorCode.noGameContractInstance.rawValue, userInfo: [NSLocalizedDescriptionKey: "Game contract not available for readBool."])
        }
        do {
            let result: [Bool] = try await contract.read(fnName).call() // Using Web3PromiseKit for async
            let value = result.first ?? false
            print("BlockchainService: Read '\(fnName)' -> \(value)")
            return value
        } catch {
            print("BlockchainService: ERROR - Reading bool '\(fnName)': \(error)")
            throw NSError(domain: "BlockchainService", code: BlockchainErrorCode.contractReadError.rawValue, userInfo: [NSLocalizedDescriptionKey: "Failed to read boolean value for '\(fnName)' from contract. \(error.localizedDescription)"])
        }
    }

    func readAddress(fnName: String) async throws -> String {
        print("BlockchainService: Reading address function '\(fnName)'...")
        guard let contract = gameContract else {
            throw NSError(domain: "BlockchainService", code: BlockchainErrorCode.noGameContractInstance.rawValue, userInfo: [NSLocalizedDescriptionKey: "Game contract not available for readAddress."])
        }
        do {
            let result: [EthereumAddress] = try await contract.read(fnName).call() // Using Web3PromiseKit for async
            let addressHex = result.first?.hex(eip55: false).lowercased() ?? ZERO_ADDRESS_STRING
            print("BlockchainService: Read '\(fnName)' -> \(addressHex)")
            return addressHex
        } catch {
            print("BlockchainService: ERROR - Reading address '\(fnName)': \(error)")
            throw NSError(domain: "BlockchainService", code: BlockchainErrorCode.contractReadError.rawValue, userInfo: [NSLocalizedDescriptionKey: "Failed to read address value for '\(fnName)' from contract. \(error.localizedDescription)"])
        }
    }

    func getBoardState() async throws -> [[String]] {
        print("BlockchainService: Fetching board state...")
        guard let contract = gameContract else {
            throw NSError(domain: "BlockchainService", code: BlockchainErrorCode.noGameContractInstance.rawValue, userInfo: [NSLocalizedDescriptionKey: "Game contract not available for getBoardState."])
        }
        do {
            // The ABI for getBoardState returns address[3][3]
            // Web3.swift should decode this as [[EthereumAddress]]
            let result: [[EthereumAddress]] = try await contract.read("getBoardState").call() // Using Web3PromiseKit
            print("BlockchainService: Successfully decoded board state from contract.")
            return result.map { row in
                row.map { $0.hex(eip55: false).lowercased() }
            }
        } catch {
            print("BlockchainService: ERROR - Fetching or decoding board state: \(error)")
            throw NSError(domain: "BlockchainService", code: BlockchainErrorCode.failedToDecodeBoard.rawValue, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch or decode board state from contract. \(error.localizedDescription)"])
        }
    }

    // --- Blockchain Write Functions ---
    func createGameByPlayer(playerIndex: Int = 0) async throws -> String? {
        print("BlockchainService: Creating game via factory by player \(playerIndex + 1)...")
        guard let factory = self.factoryContract else {
            throw NSError(domain: "BlockchainService", code: BlockchainErrorCode.noFactoryContractInstance.rawValue, userInfo: [NSLocalizedDescriptionKey: "Factory contract not available to create game."])
        }
        guard let web3 = self.web3 else {
            throw NSError(domain: "BlockchainService", code: BlockchainErrorCode.web3ClientNotInitialized.rawValue, userInfo: [NSLocalizedDescriptionKey: "Web3 client not initialized for createGame."])
        }

        let playerCredentials = try getPlayerCredentials(forPlayer: playerIndex)
        print("BlockchainService: Using deployer address for createGame: \(playerCredentials.address.hex(eip55: true))")

        guard let createGameFunction = factory.createWrite("createGame", parameters: []) else {
            throw NSError(domain: "BlockchainService", code: BlockchainErrorCode.failedToPrepareTx.rawValue, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare 'createGame' transaction."])
        }

        do {
            // Send transaction and wait for receipt
            // Note: `send()` may require explicit gas parameters or rely on Web3.swift's estimation
            // For simplicity, we let Web3.swift handle nonce and gas if possible.
            // You might need to pass `gasPrice: try await web3.eth.gasPrice()` and `gasLimit: try await createGameFunction.estimateGas(...)`
            print("BlockchainService: Sending 'createGame' transaction...")
            let txResponse = try await createGameFunction.send(
                nonce: nil, // Let Web3.swift determine nonce from playerCredentials.address
                gasPrice: nil, // Let Web3.swift determine gas price (or set manually)
                maxFeePerGas: nil,
                maxPriorityFeePerGas: nil,
                gasLimit: BigUInt(2_000_000), // Provide a reasonable gas limit
                from: playerCredentials.address, // Explicitly set from address
                value: nil, // No ETH value sent
                accessList: [:],
                transactionType: .legacy // Or .eip1559 if preferred and supported
            ).promise.get() // Using .promise.get() for Web3PromiseKit

            print("BlockchainService: 'createGame' transaction sent. Hash: \(txResponse.transactionHash.hex()). Waiting for receipt...")
            let txReceipt = try await txResponse.wait() // Wait for the transaction to be mined

            if txReceipt.status != .success {
                print("BlockchainService: ERROR - 'createGame' transaction failed on chain. Status: \(txReceipt.status). Hash: \(txReceipt.transactionHash.hex())")
                throw NSError(domain: "BlockchainService", code: BlockchainErrorCode.transactionFailed.rawValue, userInfo: [NSLocalizedDescriptionKey: "Create game transaction failed on chain (Hash: \(txReceipt.transactionHash.hex())). Check block explorer."])
            }
            print("BlockchainService: 'createGame' transaction succeeded. Hash: \(txReceipt.transactionHash.hex())")

            // Parse GameCreated event from logs
            // ABI for the GameCreated event: event GameCreated(address indexed gameAddress);
            let gameCreatedEventSignature = "GameCreated(address)" // Name and types
            let gameCreatedEventTopic = try EthereumTopic(signature: gameCreatedEventSignature)

            for logEntry in txReceipt.logs {
                if logEntry.topics.first == gameCreatedEventTopic { // Check the first topic (event signature hash)
                    // The new game address is an indexed parameter, so it's in the topics array.
                    // Since it's the first (and only) indexed parameter, it's usually logEntry.topics[1]
                    if logEntry.topics.count > 1 {
                        let gameAddressData = logEntry.topics[1].hex() // topics[0] is event signature
                        // Convert the 32-byte topic data to a 20-byte address (take last 40 hex chars)
                        let newGameAddressHex = "0x" + String(gameAddressData.suffix(40))
                        if EthereumAddress(hex: newGameAddressHex, eip55: false) != nil {
                            print("BlockchainService: GameCreated event found. New game address: \(newGameAddressHex)")
                            self.currentGameAddress = newGameAddressHex // This will trigger UI update via @Published and gameContract update
                            return newGameAddressHex
                        } else {
                            print("BlockchainService: WARNING - GameCreated event topic[1] was not a valid address: \(gameAddressData)")
                        }
                    }
                }
            }
            print("BlockchainService: ERROR - GameCreated event log not found or address could not be parsed from transaction receipt.")
            throw NSError(domain: "BlockchainService", code: BlockchainErrorCode.eventNotFound.rawValue, userInfo: [NSLocalizedDescriptionKey: "Create game transaction succeeded, but GameCreated event log was not found or address was unparsable."])

        } catch {
            print("BlockchainService: ERROR - Sending 'createGame' transaction or processing receipt: \(error)")
            if let web3Error = error as? Web3Error {
                 throw NSError(domain: "BlockchainService", code: BlockchainErrorCode.web3Error.rawValue, userInfo: [NSLocalizedDescriptionKey: "Web3 Error during createGame: \(web3Error.localizedDescription)"])
            }
            throw error // Re-throw other errors
        }
    }

    func makeMove(playerIndex: Int, row: Int, col: Int) async throws -> String {
        print("BlockchainService: Making move by player \(playerIndex + 1) at (\(row), \(col))...")
        guard let contract = self.gameContract else {
            throw NSError(domain: "BlockchainService", code: BlockchainErrorCode.noGameContractInstance.rawValue, userInfo: [NSLocalizedDescriptionKey: "Game contract not available to make move."])
        }
        guard let web3 = self.web3 else {
             throw NSError(domain: "BlockchainService", code: BlockchainErrorCode.web3ClientNotInitialized.rawValue, userInfo: [NSLocalizedDescriptionKey: "Web3 client not initialized for makeMove."])
        }

        let playerCredentials = try getPlayerCredentials(forPlayer: playerIndex)
        print("BlockchainService: Using signer address for makeMove: \(playerCredentials.address.hex(eip55: true))")

        guard (0...2).contains(row) && (0...2).contains(col) else {
            throw NSError(domain: "BlockchainService", code: BlockchainErrorCode.invalidRowColInput.rawValue, userInfo: [NSLocalizedDescriptionKey: "Invalid row/column input for makeMove: (\(row), \(col)). Must be 0-2."])
        }

        // Parameters for makeMove: uint8 row, uint8 col
        guard let makeMoveFunction = contract.createWrite(
            "makeMove",
            parameters: [UInt8(row) as SolidityEncodable, UInt8(col) as SolidityEncodable]
        ) else {
            throw NSError(domain: "BlockchainService", code: BlockchainErrorCode.failedToPrepareTx.rawValue, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare 'makeMove' transaction."])
        }

        do {
            print("BlockchainService: Sending 'makeMove' transaction...")
            let txResponse = try await makeMoveFunction.send(
                nonce: nil,
                gasPrice: nil,
                maxFeePerGas: nil,
                maxPriorityFeePerGas: nil,
                gasLimit: BigUInt(500_000), // Provide a reasonable gas limit for a move
                from: playerCredentials.address,
                value: nil,
                accessList: [:],
                transactionType: .legacy
            ).promise.get()

            print("BlockchainService: 'makeMove' transaction sent. Hash: \(txResponse.transactionHash.hex()). Waiting for receipt...")
            let txReceipt = try await txResponse.wait()

            if txReceipt.status != .success {
                print("BlockchainService: ERROR - 'makeMove' transaction failed on chain. Status: \(txReceipt.status). Hash: \(txReceipt.transactionHash.hex())")
                throw NSError(domain: "BlockchainService", code: BlockchainErrorCode.transactionFailed.rawValue, userInfo: [NSLocalizedDescriptionKey: "Make move transaction failed on chain (Hash: \(txReceipt.transactionHash.hex())). Check contract logic or block explorer."])
            }

            let txHashHex = txReceipt.transactionHash.hex()
            print("BlockchainService: 'makeMove' transaction succeeded. Hash: \(txHashHex)")
            return txHashHex
        } catch {
            print("BlockchainService: ERROR - Sending 'makeMove' transaction or processing receipt: \(error)")
             if let web3Error = error as? Web3Error {
                 throw NSError(domain: "BlockchainService", code: BlockchainErrorCode.web3Error.rawValue, userInfo: [NSLocalizedDescriptionKey: "Web3 Error during makeMove: \(web3Error.localizedDescription)"])
            }
            throw error
        }
    }

    // --- Emoji Helper ---
    func emojiForAddress(_ addr: String) -> String {
        let emojis = [
            "😀", "🐶", "🌟", "🍕", "🚀", "🐍", "🎮", "📚", "🎵", "🌈",
            "🍔", "🧠", "🦄", "💎", "🕹️", "🧊", "⚡", "💡", "🧩", "🎯"
        ]
        if addr.lowercased() == ZERO_ADDRESS_STRING.lowercased() || addr.isEmpty {
            return ""
        }
        let addressCleaned = addr.lowercased().replacingOccurrences(of: "0x", with: "")
        guard let data = addressCleaned.data(using: .utf8) else { return "❓" }

        let digest = SHA256.hash(data: data)
        let byte = digest.first ?? 0
        return emojis[Int(byte) % emojis.count]
    }

    // Custom Error Codes for more specific error handling in UI
    enum BlockchainErrorCode: Int {
        case invalidPrivateKeyFormat = 100
        case noGameContractInstance = 200
        case noFactoryContractInstance = 201
        case contractReadError = 210
        case failedToDecodeBoard = 211
        case web3ClientNotInitialized = 220
        case failedToPrepareTx = 300
        case transactionFailed = 301
        case eventNotFound = 302
        case invalidRowColInput = 400
        case web3Error = 500 // Generic Web3.swift error

        var description: String { // For UI display
            switch self {
            case .invalidPrivateKeyFormat: return "Invalid Private Key"
            case .noGameContractInstance: return "Game Not Joined/Created"
            case .noFactoryContractInstance: return "Factory Not Initialized"
            case .contractReadError: return "Contract Read Failed"
            case .failedToDecodeBoard: return "Board Decode Failed"
            case .web3ClientNotInitialized: return "Web3 Not Initialized"
            case .failedToPrepareTx: return "Tx Preparation Failed"
            case .transactionFailed: return "Tx Failed On-chain"
            case .eventNotFound: return "Expected Event Not Found"
            case .invalidRowColInput: return "Invalid Input"
            case .web3Error: return "Web3 Library Error"
            }
        }
    }
}

// Helper extension for PromiseKit to async/await (if not already provided by Web3PromiseKit)
// This ensures .wait() can be called on the Promise returned by Web3.swift's send()
// If Web3PromiseKit already makes .get() available for async/await, this might not be strictly needed
// but doesn't hurt. The `send().promise.get()` pattern is typical for Web3PromiseKit.
/*
extension Web3.TransactionSendingResult {
    func wait() async throws -> EthereumTransactionReceiptObject {
        return try await self.promise.get() // .get() on a PromiseKit promise waits for it
    }
}
*/
