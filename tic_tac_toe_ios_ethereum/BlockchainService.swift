//
//  BlockchainService.swift
//  tic_tac_toe_ios_ethereum
//
//  Created by Agent Malone on 5/13/25.
//

import Foundation
import SwiftUI
import Web3                  // core client & types
import Web3ContractABI       // DynamicContract helpers
import Web3PromiseKit        // PromiseKit → async/await
import BigInt
import CryptoKit             // for emoji hashing

// MARK: -– simple config helpers
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

// MARK: – deployment JSON (adjust keys if your file differs)
//todo ai. removed your DeploymentAddresses because it exists in another file as:

//import Foundation

//// This structure matches the layout of your deployment_output_*.json files
//struct DeploymentAddresses: Codable {
//    let gameImplementationAddress: String? // Must match JSON key exactly or use CodingKeys
//    let factoryAddress: String?            // Must match JSON key exactly or use CodingKeys
//
//    // If your JSON keys look like "factory_address", uncomment this section:
//    /*
//    enum CodingKeys: String, CodingKey {
//        case gameImplementationAddress = "game_implementation_address" // Example if JSON uses snake_case
//        case factoryAddress = "factory_address"
//    }
//    */
//}

//this was yours that i removed:
//struct DeploymentAddresses: Codable { let factoryAddress: String? }

// MARK: – service
@MainActor
final class BlockchainService: ObservableObject {

    // UI-observable
    @Published var useLocal = true { didSet { if oldValue != useLocal { reset() } } }
    @Published var factoryAddress: String? { didSet { buildFactory() } }
    @Published var currentGameAddress: String? { didSet { buildGame() } }

    @Published private(set) var player1 = "–"
    @Published private(set) var player2 = "–"
    @Published private(set) var rpcURL  = "–"

    // internals
    private var web3: Web3?
    private var factoryABI: String?
    private var gameABI:    String?
    private var factory:    DynamicContract?
    private var game:       DynamicContract?

    // MARK: init
    init() {
        factoryABI = loadABI(named: "TicTacToeFactory")
        gameABI    = loadABI(named: "MultiPlayerTicTacToe")
        reset()
    }

    // MARK: public API ------------------------------------------------------

    /// Deploys a new game via the factory and sets `currentGameAddress`.
    func createGame(by player: Int = 0) async throws {
        guard let factory,
              let invocation = factory["createGame"]?() else { throw Err.noFactory }

        let key  = try privKey(player)
        let hash = try await invocation.send(gasLimit: nil,
                                             from: key.address).wait()
        let rcpt = try await web3!.eth
            .getTransactionReceipt(transactionHash: EthereumData(hash))
            .wait()
        //todo AI fix
//        /Users/josephmalone/ios_code/tic_tac_toe_ios_ethereum/tic_tac_toe_ios_ethereum/BlockchainService.swift:72:43 Binary operator '==' cannot be applied to operands of type 'EthereumQuantity?' and 'SensoryFeedback'
        
        //todo ai can you refer to receipt when it wasnt declared yet??

 guard let receipt = rcpt, receipt.status == .success else { throw Err.txFail }
        

        // topic[1] = indexed gameAddress
        guard let newAddrTopic = receipt.logs.first?.topics[safe: 1] else { throw Err.eventMiss }
        currentGameAddress = "0x" + newAddrTopic.hex().suffix(40)
    }

    /// Makes a move in the current game.
    func makeMove(by player: Int, row: UInt8, col: UInt8) async throws {
        guard let game,
              let invocation = game["makeMove"]?(row, col) else { throw Err.noGame }

        let key  = try privKey(player)
        let hash = try await invocation
            .send(gasLimit: 500_000, from: key.address)
            .wait()
        let rcpt = try await web3!.eth
            .getTransactionReceipt(transactionHash: EthereumData(hash))
            .wait()
        
        //TODO AI
        ///Users/josephmalone/ios_code/tic_tac_toe_ios_ethereum/tic_tac_toe_ios_ethereum/BlockchainService.swift:98:28 Binary operator '==' cannot be applied to operands of type 'EthereumQuantity?' and 'SensoryFeedback'

        guard rcpt?.status == .success else { throw Err.txFail }
    }

    /// Returns the 3×3 board as lower-case hex addresses.
    func board() async throws -> [[String]] {
        guard let game,
              let call = game["getBoardState"]?() else { throw Err.noGame }

        let any = try await call.call().wait()
        guard let raw = any as? [[EthereumAddress]] else { throw Err.decode }
        return raw.map { $0.map { $0.hex(eip55: false) } }
    }

    // MARK: private helpers -------------------------------------------------

    private func reset() {
        rpcURL = useLocal ? RPC_LOCAL : RPC_TEST
        web3   = Web3(rpcURL: rpcURL)                                    // ✅ docs example :contentReference[oaicite:0]{index=0}
        player1 = addr(PKS()[0]) ?? "⛔"
        player2 = addr(PKS()[1]) ?? "⛔"

        factoryAddress = deployment()?.factoryAddress
        currentGameAddress = nil
    }

    private func buildFactory() {
        guard let a = factoryAddress,
              let abi = factoryABI,
              let ea  = try? EthereumAddress(hex: a, eip55: false)
        else { factory = nil; return }

        factory = try? web3?.eth.Contract(
            json: abi.data(using: .utf8)!,
            abiKey: nil,
            address: ea)
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

    // ABI & deployment loaders
    private func loadABI(named name: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
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

    // key / address helpers
    private func PKS() -> [String] { useLocal ? PK_LOCAL : PK_TEST }
    
    //todo ai fix
//    /Users/josephmalone/ios_code/tic_tac_toe_ios_ethereum/tic_tac_toe_ios_ethereum/BlockchainService.swift:190:78 Extraneous argument label 'hex:' in call

    
    private func privKey(_ idx: Int) throws -> EthereumPrivateKey { try .init(hex: PKS()[idx]) }
    
    
    //todo AI fix same deal
    
//    /Users/josephmalone/ios_code/tic_tac_toe_ios_ethereum/tic_tac_toe_ios_ethereum/BlockchainService.swift:196:73 Extraneous argument label 'hex:' in call

    private func addr(_ pk: String) -> String? { try? EthereumPrivateKey(hex: pk).address.hex(eip55: true) }

    // MARK: error plumbing
    enum Err: LocalizedError { case noFactory, noGame, txFail, eventMiss, decode }
}

// MARK: – Promise->async bridge (missing in some Package builds)
import PromiseKit
private extension Promise {
    func wait() async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            self.done { cont.resume(returning: $0) }
                .catch { cont.resume(throwing: $0) }
        }
    }
}

// MARK: – safe-index helper
private extension Array {
    subscript(safe idx: Int) -> Element? { indices.contains(idx) ? self[idx] : nil }
}

