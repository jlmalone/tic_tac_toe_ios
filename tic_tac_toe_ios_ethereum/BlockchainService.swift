//
//  BlockchainService.swift
//  tic_tac_toe_ios_ethereum
//
//  Created by Agent Malone on 5/13/25.
//

import Foundation
import SwiftUI // Needed for ObservableObject and @Published

// --- Dummy Data and Placeholders ---
// Replace these with actual loading from Secrets.plist later
let DUMMY_PK_1 = "0xPrivateKey1_REPLACE_ME"
let DUMMY_PK_2 = "0xPrivateKey2_REPLACE_ME"
let DUMMY_P1_ADDR = "0xPlayerOneAddress0000000000000000000001"
let DUMMY_P2_ADDR = "0xPlayerTwoAddress0000000000000000000002"
let DUMMY_FACTORY_ADDR_LOCAL = "0xFactoryAddressLocal00000000000000000001"
let DUMMY_FACTORY_ADDR_SEPOLIA = "0xFactoryAddressSepolia000000000000000002"
let DUMMY_GAME_ADDR = "0xNewGameAddress000000000000000000000003"
let ZERO_ADDRESS_STRING_PLACEHOLDER = "0x0000000000000000000000000000000000000000" // Keep this

// --- The Fake Blockchain Brain ---

@MainActor // Makes sure changes happen on the main thread for the UI
class BlockchainService: ObservableObject {

    // --- Things the UI needs to know about and react to ---
    @Published var isLocal: Bool = true {
        didSet { // When isLocal changes...
            if oldValue != isLocal {
                print("BlockchainService: Switched to \(isLocal ? "LOCAL" : "SEPOLIA") mode")
                reinitializeClient() // Update addresses and factory
            }
        }
    }
    @Published var factoryAddress: String? = DUMMY_FACTORY_ADDR_LOCAL // Start with dummy local factory
    @Published var currentGameAddress: String? = nil // No game initially
    @Published var player1Address: String? = DUMMY_P1_ADDR // Dummy player 1 address
    @Published var player2Address: String? = DUMMY_P2_ADDR // Dummy player 2 address
    @Published var rpcUrlString: String = "http://127.0.0.1:8545/" // Dummy RPC URL
    @Published var chainId: String = "31337" // Dummy Chain ID

    // --- Internal state ---
    private var deploymentInfo: DeploymentAddresses?

    // --- Initialization ---
    init() {
        print("BlockchainService: Initializing...")
        // Load initial deployment info (will be fake for now)
        self.deploymentInfo = loadDeploymentInfo()
        // Set initial factory address based on the (fake) loaded info
        self.factoryAddress = self.deploymentInfo?.factoryAddress ?? (isLocal ? DUMMY_FACTORY_ADDR_LOCAL : DUMMY_FACTORY_ADDR_SEPOLIA)
        printDerivedAddresses() // Print the initial dummy addresses
    }

    // --- Placeholder Functions (These will do real work later) ---

    // Called when switching between Local and Sepolia
    func reinitializeClient() {
        print("BlockchainService: Reinitializing client for \(isLocal ? "LOCAL" : "SEPOLIA")...")
        // Fake loading deployment info for the new network
        self.deploymentInfo = loadDeploymentInfo()
        self.factoryAddress = self.deploymentInfo?.factoryAddress ?? (isLocal ? DUMMY_FACTORY_ADDR_LOCAL : DUMMY_FACTORY_ADDR_SEPOLIA)
        self.currentGameAddress = nil // Clear game address on network switch
        self.rpcUrlString = isLocal ? "http://127.0.0.1:8545/" : "https://sepolia.infura.io/v3/YOUR_KEY" // Update dummy RPC
        self.chainId = isLocal ? "31337" : "11155111" // Update dummy Chain ID
        
        // We'll keep player addresses the same dummy ones for now
        self.player1Address = DUMMY_P1_ADDR
        self.player2Address = DUMMY_P2_ADDR
        
        print("BlockchainService: Reinitialized. Factory: \(factoryAddress ?? "None")")
        printDerivedAddresses()
    }

    // Pretends to load the deployment addresses from a file
    func loadDeploymentInfo() -> DeploymentAddresses? {
        let fileName = isLocal ? "deployment_output_hardhat_local" : "deployment_output_sepolia_testnet"
        print("BlockchainService: Pretending to load \(fileName).json")
        // In the future, this will load and parse the actual JSON file from the app bundle
        
        // For now, just return a fake structure based on the network
        if isLocal {
            return DeploymentAddresses(gameImplementationAddress: "0xGameImplLocal...", factoryAddress: DUMMY_FACTORY_ADDR_LOCAL)
        } else {
            return DeploymentAddresses(gameImplementationAddress: "0xGameImplSepolia...", factoryAddress: DUMMY_FACTORY_ADDR_SEPOLIA)
        }
    }

    // Prints the current addresses to the Xcode console (bottom area)
    func printDerivedAddresses() {
        print("── Fake address info ──")
        print("P1    : \(player1Address ?? "N/A") (Dummy)")
        print("P2    : \(player2Address ?? "N/A") (Dummy)")
        print("Factory: \(factoryAddress ?? "<none>") (Dummy/Loaded)")
        print("Game   : \(currentGameAddress ?? "<none>")")
        print("RPC    : \(rpcUrlString) (Dummy)")
        print("ChainId: \(chainId) (Dummy)")
        print("──────────────────────")
    }

    // Pretends to get player credentials (just returns a dummy PK string)
    // Note: The real function will return a special 'EthereumPrivateKey' object
    func getPlayerCredentials(forPlayer index: Int) throws -> String {
        print("BlockchainService: Pretending to get credentials for player \(index)")
        if index == 0 {
            return DUMMY_PK_1
        } else {
            return DUMMY_PK_2
        }
        // In the real version, we'd load from Secrets.plist based on `isLocal`
    }

    func getPlayerCount() -> Int {
        return 2 // We always have 2 players
    }

    // --- Fake Blockchain Read Functions ---
    // These need `async throws` because the real ones will talk over the network

    func readBool(fnName: String) async throws -> Bool {
        print("BlockchainService: Pretending to read bool function '\(fnName)'...")
        try await Task.sleep(nanoseconds: 500_000_000) // Wait half a second
        // Return a fake value - maybe based on the function name?
        if fnName == "gameEnded" {
             // Let's pretend the game isn't ended unless a game address exists
            return currentGameAddress != nil && Bool.random() // Sometimes true if game exists
        }
        return false // Default fake answer
    }

    func readAddress(fnName: String) async throws -> String {
        print("BlockchainService: Pretending to read address function '\(fnName)'...")
        try await Task.sleep(nanoseconds: 600_000_000) // Wait a bit longer
        if fnName == "winner" && currentGameAddress != nil {
            // Pretend player 1 wins sometimes
            return Bool.random() ? DUMMY_P1_ADDR : ZERO_ADDRESS_STRING_PLACEHOLDER
        }
        if fnName == "lastPlayer" && currentGameAddress != nil {
             // Pretend player 2 played last sometimes
             return Bool.random() ? DUMMY_P2_ADDR : DUMMY_P1_ADDR
        }
        return ZERO_ADDRESS_STRING_PLACEHOLDER // Default fake answer (empty address)
    }

    // --- Fake Blockchain Write Functions ---

    // Pretends to create a game
    func createGameByPlayer(playerIndex: Int = 0) async throws -> String? {
        print("BlockchainService: Pretending to create game by player \(playerIndex)...")
        guard factoryAddress != nil else {
            print("BlockchainService: Error - No factory address set!")
            throw NSError(domain: "FakeBlockchain", code: 1, userInfo: [NSLocalizedDescriptionKey: "Factory address is missing"])
        }
        try await Task.sleep(nanoseconds: 1_500_000_000) // Wait 1.5 seconds (like a real transaction)
        print("BlockchainService: Game creation 'succeeded'!")
        self.currentGameAddress = DUMMY_GAME_ADDR // Set the fake game address
        return self.currentGameAddress
    }

    // Pretends to make a move
    // The real one returns a transaction hash (a long string)
    func makeMove(playerIndex: Int, row: Int, col: Int) async throws -> String {
         print("BlockchainService: Pretending player \(playerIndex) makes move at (\(row), \(col))...")
         guard currentGameAddress != nil else {
             print("BlockchainService: Error - No game address set!")
             throw NSError(domain: "FakeBlockchain", code: 2, userInfo: [NSLocalizedDescriptionKey: "No game address set"])
         }
         // Basic check: Don't allow move if row/col is bad (real contract does this better)
         guard (0...2).contains(row) && (0...2).contains(col) else {
              print("BlockchainService: Error - Invalid row/col!")
              throw NSError(domain: "FakeBlockchain", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid row/column input"])
         }

         try await Task.sleep(nanoseconds: 1_200_000_000) // Wait 1.2 seconds
         print("BlockchainService: Move 'succeeded'!")
         // We need to update the fake board state here later!
         return "0xFakeTransactionHash_\(Int.random(in: 1000...9999))" // Return a fake transaction hash
    }

    // --- Fake Board State ---
    // The real one returns a 2D array of strings (addresses)
    func getBoardState() async throws -> [[String]] {
        print("BlockchainService: Pretending to get board state...")
        guard currentGameAddress != nil else {
             print("BlockchainService: Warning - No game address, returning empty board.")
             // Return an empty 3x3 board if no game is set
              return Array(repeating: Array(repeating: ZERO_ADDRESS_STRING_PLACEHOLDER, count: 3), count: 3)
        }
        try await Task.sleep(nanoseconds: 700_000_000) // Wait 0.7 seconds

        // Let's return a very simple fake board for now
        // We'll make this smarter later when makeMove works
        let fakeBoard = [
            [DUMMY_P1_ADDR, ZERO_ADDRESS_STRING_PLACEHOLDER, DUMMY_P2_ADDR],
            [ZERO_ADDRESS_STRING_PLACEHOLDER, DUMMY_P1_ADDR, ZERO_ADDRESS_STRING_PLACEHOLDER],
            [DUMMY_P2_ADDR, ZERO_ADDRESS_STRING_PLACEHOLDER, ZERO_ADDRESS_STRING_PLACEHOLDER]
        ]
        print("BlockchainService: Returning fake board state.")
        return fakeBoard
    }

    // --- Emoji Helper (Same as before) ---
    func emojiForAddress(_ addr: String) -> String {
        // Use a simpler method for now, maybe just Player 1 = X, Player 2 = O?
        if addr.lowercased() == DUMMY_P1_ADDR.lowercased() {
            return "❌" // Player 1 is X
        } else if addr.lowercased() == DUMMY_P2_ADDR.lowercased() {
            return "⭕️" // Player 2 is O
        } else if addr.lowercased() == ZERO_ADDRESS_STRING_PLACEHOLDER.lowercased() {
             return "" // Empty cell
        } else {
            return "?" // Unknown address
        }
        /*
        // Original Emoji code (needs CryptoKit import)
        let emojis = [
            "😀", "🐶", "🌟", "🍕", "🚀", "🐍", "🎮", "📚", "🎵", "🌈",
            "🍔", "🧠", "🦄", "💎", "🕹️", "🧊", "⚡", "💡", "🧩", "🎯"
        ]
        // Requires `import CryptoKit` at the top of the file
        guard let data = addr.lowercased().replacingOccurrences(of: "0x", with: "").data(using: .utf8) else { return "❓" }
        let digest = SHA256.hash(data: data) // SHA256 not available by default without CryptoKit
        let byte = digest.first ?? 0
        return emojis[Int(byte) % emojis.count]
        */
    }
}

// Helper extension for making fake delays look nice
extension Task where Success == Never, Failure == Never {
    static func sleep(seconds: Double) async throws {
        let duration = UInt64(seconds * 1_000_000_000)
        try await Task.sleep(nanoseconds: duration)
    }
}
