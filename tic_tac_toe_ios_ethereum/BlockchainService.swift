//
//  BlockchainService.swift
//  tic_tac_toe_ios_ethereum
//
//  Created by Agent Malone on 5/13/25.
//

import Foundation
import SwiftUI
import Web3                         // core client & types
import Web3ContractABI              // DynamicContract helpers
import Web3PromiseKit               // PromiseKit → async/await
import BigInt
import CryptoKit

// ──────────────────────────────────────────────────────────────────────────────
// MARK: – Simple config helpers
// ──────────────────────────────────────────────────────────────────────────────
private let info = Bundle.main.infoDictionary ?? [:]
private func cfg(_ k: String, _ def: String) -> String {
    (info[k] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? def
}
private let PK_LOCAL  = [cfg("PRIVATE_KEY_HARDHAT_0","0x00"),
                         cfg("PRIVATE_KEY_HARDHAT_1","0x00")]
private let PK_TEST   = [cfg("PRIVATE_KEY_PLAYER1","0x00"),
                         cfg("PRIVATE_KEY_PLAYER2","0x00")]
private let RPC_LOCAL = cfg("LOCAL_RPC_URL",   "http://127.0.0.1:8545")
private let RPC_TEST  = cfg("SEPOLIA_RPC_URL", "https://sepolia.infura.io/v3/REPLACE_ME")

// ---------------------------------------------------------------------------
// PUBLIC constant so UI can check for “draw”
// ---------------------------------------------------------------------------
public let ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"

// ──────────────────────────────────────────────────────────────────────────────
// MARK: – Service
// ──────────────────────────────────────────────────────────────────────────────
@MainActor
final class BlockchainService: ObservableObject {
    
    
    

    // UI-observable state ----------------------------------------------------
    @Published var useLocal = true { didSet { if oldValue != useLocal { reset() } } }
    @Published var factoryAddress:     String? { didSet { buildFactory() } }
    @Published var currentGameAddress: String? { didSet { buildGame()   } }

    @Published private(set) var player1 = "–"
    @Published private(set) var player2 = "–"
    @Published private(set) var rpcURL  = "–"

    // internals --------------------------------------------------------------
    private var web3: Web3?
    private var factoryABI: String?
    private var gameABI:    String?
    private var factory:    DynamicContract?
    private var game:       DynamicContract?

    // MARK: init -------------------------------------------------------------
    init() {
        factoryABI = loadABI(named: "TicTacToeFactory")
        print("DEBUG: factoryABI is \(factoryABI == nil ? "nil" : "loaded")") // <-- ADD THIS
        gameABI    = loadABI(named: "MultiPlayerTicTacToe")
        print("DEBUG: gameABI is \(gameABI == nil ? "nil" : "loaded")")       // <-- ADD THIS
        reset()
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: Public API
    // ──────────────────────────────────────────────────────────────────────

//    /// Deploy a new game via the factory; updates `currentGameAddress`.
//    func createGame(by player: Int = 0) async throws {
//        guard let factory,
//              let call = factory["createGame"]?() else { throw Err.noFactory }
//
//        let key   = try privKey(player)
//        let hash  = try await call.send(gasLimit: nil, from: key.address).wait()
//
//        let rcpt  = try await web3!.eth
//            .getTransactionReceipt(transactionHash: EthereumData(hash)).wait()
//
//        // ✅ status.quantity == 1  → success
//        guard let receipt = rcpt,
//              receipt.status?.quantity == BigUInt(1) else { throw Err.txFail }
//
//        // topic[1] = indexed gameAddress
//        guard let t1 = receipt.logs.first?.topics[safe: 1] else { throw Err.eventMiss }
//        currentGameAddress = "0x" + t1.hex().suffix(40)
//    }
    
    /// Deploy a new game via the factory; returns the new game address.
    func createGame(by player: Int = 0) async throws -> String {
        guard let factory,
              let invocation = factory["createGame"]?() else {
            throw Err.noFactory
        }

        let key  = try privKey(player)
        let hash = try await invocation
            .send(gasLimit: nil, from: key.address)
            .wait()

        let rcpt = try await web3!.eth
            .getTransactionReceipt(transactionHash: EthereumData(hash))
            .wait()

        // success is status.quantity == 1
        guard let receipt = rcpt,
              receipt.status?.quantity == BigUInt(1) else {
            throw Err.txFail
        }

        // parse the indexed `gameAddress` from topic[1]
        guard let topic1 = receipt.logs.first?.topics[safe: 1] else {
            throw Err.eventMiss
        }
        let newAddr = "0x" + topic1.hex().suffix(40)

        currentGameAddress = newAddr
        return newAddr
    }

    /// Make a move on the 3×3 board.
    func makeMove(by player: Int, row: UInt8, col: UInt8) async throws {
        guard let game,
              let call = game["makeMove"]?(row, col) else { throw Err.noGame }

        let key   = try privKey(player)
        let hash  = try await call.send(gasLimit: 500_000, from: key.address).wait()

        let rcpt  = try await web3!.eth
            .getTransactionReceipt(transactionHash: EthereumData(hash)).wait()

        guard rcpt?.status?.quantity == BigUInt(1) else { throw Err.txFail }
    }

    /// Fetch the board (`address[3][3]` → `[[String]]`)
    func board() async throws -> [[String]] {
        guard let game,
              let call = game["getBoardState"]?() else { throw Err.noGame }

        let any = try await call.call().wait()
        guard let raw = any as? [[EthereumAddress]] else { throw Err.decode }
        return raw.map { $0.map { $0.hex(eip55: false) } }
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: Private plumbing
    // ──────────────────────────────────────────────────────────────────────

    private func reset() {
//        rpcURL = useLocal ? RPC_LOCAL : RPC_TEST
//        web3   = Web3(rpcURL: rpcURL)
//
//        player1 = addr(PKS()[0]) ?? "⛔"
//        player2 = addr(PKS()[1]) ?? "⛔"
//
//        factoryAddress      = deployment()?.factoryAddress
//        currentGameAddress  = nil
        
        
        rpcURL = useLocal ? RPC_LOCAL : RPC_TEST
        print("DEBUG: reset() - Determined RPC URL: \(rpcURL)") // <-- ADD THIS
        web3   = Web3(rpcURL: rpcURL)
        print("DEBUG: reset() - Web3 initialized. web3 is \(web3 == nil ? "nil" : "NOT nil"). RPC used: \(rpcURL)") // <-- MODIFIED THIS

        player1 = addr(PKS()[0]) ?? "⛔"
        player2 = addr(PKS()[1]) ?? "⛔"

        factoryAddress      = deployment()?.factoryAddress
        print("DEBUG: reset() - factoryAddress set to: \(factoryAddress ?? "nil")")
        currentGameAddress  = nil
    }

    private func buildFactory() {
        
        print("DEBUG: buildFactory - ENTER. factoryAddress: \(factoryAddress ?? "nil"), factoryABI is \(factoryABI == nil ? "nil" : "loaded")")
        print("DEBUG: buildFactory - web3 object is \(web3 == nil ? "nil" : "NOT nil") at this point.") // <-- ADD THIS
        
//        print("DEBUG: Attempting to build factory. factoryAddress: \(factoryAddress ?? "nil"), factoryABI is \(factoryABI == nil ? "nil" : "loaded")") // <-- ADD THIS
        guard let a = factoryAddress,
              let abi = factoryABI,
              let ea  = try? EthereumAddress(hex: a, eip55: false)
        else {
          
            print("DEBUG: buildFactory guard failed. factoryAddress: \(factoryAddress ?? "nil"), factoryABI nil? \(factoryABI == nil)")
            
            factory = nil; return }
        
        // Explicitly check web3 before the call
        guard let currentWeb3 = web3 else {
            print("DEBUG: buildFactory - web3 is NIL right before trying to create contract object.") // <-- ADD THIS
            factory = nil
            return
        }

        factory = try? currentWeb3.eth.Contract( // Use currentWeb3 here
            json: abi.data(using: .utf8)!,
            abiKey: nil,
            address: ea)
        print("DEBUG: buildFactory - web3.eth.Contract for factory result: \(factory == nil ? "nil" : "SUCCESS")")


   
//        
//        print("DEBUG: web3.eth.Contract for factory result: \(factory == nil ? "nil" : "SUCCESS")") // <-- ADD THIS
        
    }
    
    
    @MainActor // Ensure UI updates are on the main thread if called from UI
    func checkBlockchainConnection() async -> String {
        guard let currentWeb3 = web3 else {
            return "Blockchain Connection Check: FAILED - web3 object is nil"
        }
        
        print("DEBUG: checkBlockchainConnection - Attempting to get block number...")
        do {
            let blockNumber = try await currentWeb3.eth.blockNumber().wait() // Uses the PromiseKit extension
            let message = "Blockchain Connection Check: SUCCESS - Latest block number on \(useLocal ? "LOCAL" : "SEPOLIA") is \(blockNumber)"
            print("DEBUG: \(message)")
            return message
        } catch {
            let errorMessage = "Blockchain Connection Check: FAILED - Error getting block number: \(error.localizedDescription)"
            print("DEBUG: \(errorMessage)")
            print("DEBUG: Underlying error details: \(error)") // Print more details about the error
            return errorMessage
        }
    }

    private func buildGame() {
        guard let a = currentGameAddress,
              let abi = gameABI,
              let ea  = try? EthereumAddress(hex: a, eip55: false)
        else { game = nil; return }

        game = try? web3?.eth.Contract(
            json: abi.data(using: .utf8)!,
            abiKey: nil,
            address: ea)
    }

    // ── ABI / deployment helpers ─────────────────────────────────────────
    private func loadABI(named n: String) -> String? {
        guard let url = Bundle.main.url(forResource: n, withExtension: "json"),
              let d   = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let arr = obj["abi"],
              let jd  = try? JSONSerialization.data(withJSONObject: arr)
        else { return nil }
        return String(data: jd, encoding: .utf8)
    }

    private func deployment() -> DeploymentAddresses? {
        let file = useLocal ? "deployment_output_hardhat_local"
                            : "deployment_output_sepolia_testnet"
        guard let url = Bundle.main.url(forResource: file, withExtension: "json"),
              let d   = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(DeploymentAddresses.self, from: d)
    }

    // ── key / addr helpers ───────────────────────────────────────────────
    private func PKS() -> [String] { useLocal ? PK_LOCAL : PK_TEST }

    private func privKey(_ i: Int) throws -> EthereumPrivateKey {
        try EthereumPrivateKey(hexPrivateKey: PKS()[i])
    }

    private func addr(_ pk: String) -> String? {
        try? EthereumPrivateKey(hexPrivateKey: pk).address.hex(eip55: true)
    }

    // ── error enum ───────────────────────────────────────────────────────
    enum Err: LocalizedError { case noFactory, noGame, txFail, eventMiss, decode }
    
    
    // ──────────────────────────────────────────────────────────────────────
    // MARK: Public read helpers  (add just below  board()  in the service)
    // ──────────────────────────────────────────────────────────────────────
    func readBool(fnName: String) async throws -> Bool {
        guard let game,
              let call = game[fnName]?() else { throw Err.noGame }
        let any = try await call.call().wait()
        guard let arr = any as? [Bool], let first = arr.first else { throw Err.decode }
        return first
    }

    func readAddress(fnName: String) async throws -> String {
        guard let game,
              let call = game[fnName]?() else { throw Err.noGame }
        let any = try await call.call().wait()
        guard let arr = any as? [EthereumAddress], let first = arr.first else { throw Err.decode }
        return first.hex(eip55: false)
    }
    
    func printDerivedAddresses() {
        print("Player 1:", player1)
        print("Player 2:", player2)
        print("Factory:", factoryAddress ?? "nil")
        print("Game:", currentGameAddress ?? "nil")
    }
    
    func emojiForAddress(_ addr: String) -> String {
        let emojis = [
            "😀", "🐶", "🌟", "🍕", "🚀",
            "🐍", "🎮", "📚", "🎵", "🌈",
            "🍔", "🧠", "🦄", "💎", "🕹️",
            "🧊", "⚡", "💡", "🧩", "🎯"
        ]

        let cleaned = addr
            .lowercased()
            .replacingOccurrences(of: "0x", with: "")

        guard let data = cleaned.data(using: .utf8) else {
            return "❓"
        }

        let digest = SHA256.hash(data: data)
        var iterator = digest.makeIterator()
        let byte = iterator.next() ?? 0

        return emojis[Int(byte) % emojis.count]
    }


}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: – Promise→async bridge (for Web3PromiseKit)
// ──────────────────────────────────────────────────────────────────────────────
import PromiseKit
private extension Promise {
    func wait() async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            self.done { cont.resume(returning: $0) }
                .catch { cont.resume(throwing: $0) }
        }
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: – Safe-index helper
// ──────────────────────────────────────────────────────────────────────────────
private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
