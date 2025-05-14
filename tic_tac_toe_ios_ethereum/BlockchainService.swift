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
        factoryABI = loadABI(named: "TicTacToeFactory_NoErrorTypes")

//        factoryABI = loadABI(named: "TicTacToeFactory")
        print("DEBUG: factoryABI is \(factoryABI == nil ? "nil" : "loaded")") // <-- ADD THIS
        gameABI    = loadABI(named: "MultiPlayerTicTacToe")
        print("DEBUG: gameABI is \(gameABI == nil ? "nil" : "loaded")")       // <-- ADD THIS
        reset()
    }
    
    
    // Helper function for retrying an async throwing operation
    private func retry<T>(
        attempts: Int,
        initialDelaySeconds: UInt64 = 1,
        maxDelaySeconds: UInt64 = 16, // For exponential backoff
        factor: Double = 2.0,        // For exponential backoff
        operation: @escaping () async throws -> T? // Operation now returns T? to handle nil result
    ) async throws -> T? {
        var currentDelay = initialDelaySeconds
        for attempt in 0..<attempts {
            print("DEBUG: Retry - Attempt \(attempt + 1)/\(attempts)...")
            do {
                if let result = try await operation() {
                    return result // Success, return the non-nil result
                } else {
                    // Operation returned nil, meaning receipt not found yet
                    print("DEBUG: Retry - Operation returned nil (e.g., receipt not found yet) on attempt \(attempt + 1).")
                    if attempt == attempts - 1 {
                        print("DEBUG: Retry - Max attempts reached, operation still returned nil.")
                        return nil // Return nil after max attempts if still nil
                    }
                }
            } catch {
                print("DEBUG: Retry - Operation failed on attempt \(attempt + 1) with error: \(error.localizedDescription)")
                if attempt == attempts - 1 {
                    print("DEBUG: Retry - Max attempts reached, last attempt failed.")
                    throw error // Re-throw last error if all attempts fail with an error
                }
            }
            
            // Wait before retrying
            print("DEBUG: Retry - Waiting \(currentDelay) seconds before next attempt...")
            try await Task.sleep(nanoseconds: currentDelay * 1_000_000_000)
            // Exponential backoff:
            let nextDelayDouble = Double(currentDelay) * factor
            currentDelay = min(maxDelaySeconds, UInt64(nextDelayDouble))
        }
        return nil // Should not be reached if attempts > 0, but compiler needs it
    }

    // Helper function for retrying an async throwing operation with exponential backoff
    private func retryReceiptFetch(
        txHash: EthereumData, // Pass the transaction hash
        web3Instance: Web3.Eth, // Pass the web3.eth instance
        maxAttempts: Int,
        initialDelaySeconds: Double,
        maxDelaySeconds: Double,
        backoffFactor: Double
    ) async throws -> EthereumTransactionReceiptObject? { // Returns Optional Receipt
        var currentDelay = initialDelaySeconds
        for attempt in 1...maxAttempts {
            print("DEBUG: Receipt Poll - Attempt \(attempt)/\(maxAttempts) for tx: \(txHash.hex())")
            do {
                // Call getTransactionReceipt and use .wait() which handles its own promise resolution.
                // .wait() itself on getTransactionReceipt returns EthereumTransactionReceiptObject?
                if let receipt = try await web3Instance.getTransactionReceipt(transactionHash: txHash).wait() {
                    print("DEBUG: Receipt Poll - SUCCESS: Receipt found on attempt \(attempt).")
                    return receipt // Receipt found, return it
                } else {
                    // .wait() returned nil, meaning its internal polling found nothing yet.
                    print("DEBUG: Receipt Poll - Receipt still nil on attempt \(attempt) (after library's internal polling).")
                    if attempt == maxAttempts {
                        print("DEBUG: Receipt Poll - Max attempts reached, receipt still nil.")
                        return nil // Max attempts reached, still no receipt
                    }
                }
            } catch {
                // An error occurred during the getTransactionReceipt().wait() call
                print("DEBUG: Receipt Poll - FAILED on attempt \(attempt) with error: \(error.localizedDescription)")
                if attempt == maxAttempts {
                    print("DEBUG: Receipt Poll - Max attempts reached, last attempt failed with error.")
                    throw error // Re-throw the last error if all attempts fail with an error
                }
            }
            
            // Wait before next attempt only if not the last attempt
            if attempt < maxAttempts {
                print("DEBUG: Receipt Poll - Waiting \(String(format: "%.1f", currentDelay)) seconds before next attempt...")
                try await Task.sleep(nanoseconds: UInt64(currentDelay * 1_000_000_000))
                currentDelay = min(maxDelaySeconds, currentDelay * backoffFactor) // Exponential backoff
            }
        }
        return nil // Should only be reached if maxAttempts is 0, which is not typical
    }
    // ──────────────────────────────────────────────────────────────────────
    // MARK: Public API
    // ──────────────────────────────────────────────────────────────────────
    // In BlockchainService.swift

    func createGame(by player: Int = 0) async throws -> String {
        // 1. Ensure factory object is ready and get the specific invocation object
        guard let factoryInstance = self.factory else {
            print("DEBUG: createGame - Guard failed: self.factory object is nil.")
            throw Err.noFactory
        }
        guard let invocation: SolidityInvocation = factoryInstance["createGame"]?() else {
            print("DEBUG: createGame - Guard failed: Could not create invocation for 'createGame'.")
            throw Err.noFactory
        }

        // 2. Extract the target contract address and the encoded call data
        guard let transactionTo: EthereumAddress = invocation.handler.address else {
             print("DEBUG: createGame - Guard failed: Invocation handler address is nil.")
             throw Err.noFactory
        }
        guard let transactionData: EthereumData = invocation.encodeABI() else {
            print("DEBUG: createGame - Guard failed: Could not encode ABI for invocation.")
            throw Err.noFactory
        }
        
        // 3. Get the private key and derived 'from' address
        let privateKey: EthereumPrivateKey = try privKey(player)
        let fromAddress: EthereumAddress = privateKey.address
        
        print("DEBUG: createGame - Signer: \(fromAddress.hex(eip55: true)) (Player \(player + 1)), Network: \(useLocal ? "LOCAL" : "SEPOLIA")")
        print("DEBUG: createGame - Target Contract (to): \(transactionTo.hex(eip55: true))")
        print("DEBUG: createGame - Transaction Data (encoded call): \(transactionData.hex())")

        // 4. Manually construct, sign, and send the transaction
        let transactionHash: EthereumData
        do {
            print("DEBUG: createGame - Manually constructing, signing, and sending transaction...")

            // a. Get Nonce
            let nonce = try await web3!.eth.getTransactionCount(address: fromAddress, block: .pending).wait()
            
            // b. Get Gas Price
            let gasPrice = try await web3!.eth.gasPrice().wait()

            // c. Estimate Gas Limit
            let callForEstimation = EthereumCall(
                from: fromAddress,
                to: transactionTo,
                gas: nil,
                gasPrice: gasPrice,
                value: EthereumQuantity(quantity: 0),
                data: transactionData
            )
            
            print("DEBUG: createGame -   Estimating gas with call: from=\(callForEstimation.from!.hex(eip55: true)), to=\(callForEstimation.to.hex(eip55: true)), data=\(callForEstimation.data!.hex()), gasPrice=\(callForEstimation.gasPrice!.quantity)")
            let gasLimit = try await web3!.eth.estimateGas(call: callForEstimation).wait()
            
            print("DEBUG: createGame -   Nonce: \(nonce.quantity), GasPrice: \(gasPrice.quantity), Estimated GasLimit: \(gasLimit.quantity)")
            
            // d. Define Chain ID
//            let chainIdBigUInt = useLocal ? BigUInt(cfg("HARDHAT_CHAIN_ID", "31337"))! : BigUInt(cfg("SEPOLIA_CHAIN_ID", "11155111"))!
            
            let hardhatChainIdString = cfg("HARDHAT_CHAIN_ID", "31337").replacingOccurrences(of: "L", with: "")
            let sepoliaChainIdString = cfg("SEPOLIA_CHAIN_ID", "11155111").replacingOccurrences(of: "L", with: "")

            guard let hardhatChainIdBigUInt = BigUInt(hardhatChainIdString),
                  let sepoliaChainIdBigUInt = BigUInt(sepoliaChainIdString) else {
                print("DEBUG: createGame - FATAL: Could not convert chain ID strings to BigUInt. Hardhat: '\(hardhatChainIdString)', Sepolia: '\(sepoliaChainIdString)'")
                throw Err.decode // Or a more specific configuration error
            }
            
            let chainIdBigUInt = useLocal ? hardhatChainIdBigUInt : sepoliaChainIdBigUInt
            let ethereumChainIdForSigning = EthereumQuantity(quantity: chainIdBigUInt)
            print("DEBUG: createGame -   Using Chain ID for signing: \(chainIdBigUInt)")
//            let ethereumChainIdForSigning = EthereumQuantity(quantity: chainIdBigUInt) // <<< FIX 1a: Define variable
            
            print("DEBUG: createGame -   PARAMS FOR invocation.createTransaction: nonce=\(nonce.quantity), gasPrice=\(gasPrice.quantity), gasLimit=\(gasLimit.quantity), from=\(fromAddress.hex(eip55: true))")

            // e. Create the EthereumTransaction object (unsigned) using invocation.createTransaction
            guard let unsignedTransaction = invocation.createTransaction(
                nonce: nonce,
                gasPrice: gasPrice,
                maxFeePerGas: nil,
                maxPriorityFeePerGas: nil,
                gasLimit: gasLimit,
                from: fromAddress,
                value: EthereumQuantity(quantity: 0),
                accessList: [:],
                transactionType: .legacy
            ) else {
                 print("DEBUG: createGame - Guard failed: Could not create EthereumTransaction from invocation.createTransaction.")
                 throw Err.noFactory
            }
            
            
            // Now inspect the properties of the returned unsignedTransaction
              print("DEBUG: createGame -   RESULT of invocation.createTransaction:")
              print("DEBUG: createGame -     unsignedTransaction.to: \(unsignedTransaction.to?.hex(eip55: true) ?? "nil")")
              print("DEBUG: createGame -     unsignedTransaction.from: \(unsignedTransaction.from?.hex(eip55: true) ?? "nil")")
              print("DEBUG: createGame -     unsignedTransaction.data: \(unsignedTransaction.data.hex())")
              print("DEBUG: createGame -     unsignedTransaction.nonce: \(unsignedTransaction.nonce?.quantity.description ?? "nil")")
              print("DEBUG: createGame -     unsignedTransaction.gasPrice: \(unsignedTransaction.gasPrice?.quantity.description ?? "nil")")
              print("DEBUG: createGame -     unsignedTransaction.gasLimit: \(unsignedTransaction.gasLimit?.quantity.description ?? "nil")")
              print("DEBUG: createGame -     unsignedTransaction.value: \(unsignedTransaction.value?.quantity.description ?? "nil")")
              print("DEBUG: createGame -     unsignedTransaction.transactionType: \(unsignedTransaction.transactionType.rawValue)")

            // Safely print optional values
                        let to_str = unsignedTransaction.to?.hex(eip55: true) ?? "nil"
                        let data_str = unsignedTransaction.data.hex() // data is non-optional on EthereumTransaction
                        let gasLimit_str = unsignedTransaction.gasLimit?.quantity.description ?? "nil"
                        let gasPrice_str = unsignedTransaction.gasPrice?.quantity.description ?? "nil"
                        let nonce_str = unsignedTransaction.nonce?.quantity.description ?? "nil"
                        let type_str = unsignedTransaction.transactionType.rawValue

                        print("DEBUG: createGame -   Unsigned Tx (from invocation.createTransaction): to=\(to_str), data=\(data_str), gasLimit=\(gasLimit_str), gasPrice=\(gasPrice_str), nonce=\(nonce_str), type=\(type_str)")
//            print("DEBUG: createGame -   Unsigned Tx struct: to=\(unsignedTransaction.to?.hex(eip55: true) ?? "nil"), data=\(unsignedTransaction.data.hex()), gasLimit=\(unsignedTransaction.gasLimit!.quantity), gasPrice=\(unsignedTransaction.gasPrice!.quantity), nonce=\(unsignedTransaction.nonce!.quantity), type=\(unsignedTransaction.transactionType)")

            // f. Sign
            print("DEBUG: createGame -   Attempting to sign transaction using unsignedTransaction.sign(with: privateKey, chainId: ...)...")
            let signedTransaction = try unsignedTransaction.sign(
                with: privateKey,
                chainId: ethereumChainIdForSigning // <<< FIX 1b: Use correct variable
            )
            print("DEBUG: createGame -   Transaction signed. Signed Tx v: \(signedTransaction.v.quantity), r: \(signedTransaction.r.quantity), s: \(signedTransaction.s.quantity)")

            // g. Send
            print("DEBUG: createGame -   Sending signed raw transaction...")
            transactionHash = try await web3!.eth.sendRawTransaction(transaction: signedTransaction).wait()
            print("DEBUG: createGame -   sendRawTransaction SUCCEEDED. TxHash: \(transactionHash.hex())")

        } catch {
            print("DEBUG: createGame - FAILED during manual transaction cycle.")
            print("DEBUG: createGame - Error Type: \(String(reflecting: type(of: error)))")
            print("DEBUG: createGame - Localized Description: \(error.localizedDescription)")
            print("DEBUG: createGame - Full Error Details: \(error)")
            throw error
        }
        
        // --- Receipt Processing ---
        print("DEBUG: createGame - Tx sent via sendRawTransaction, getting receipt for hash: \(transactionHash.hex())")
        // --- Receipt Processing ---
                print("DEBUG: createGame - Tx sent via sendRawTransaction, getting receipt for hash: \(transactionHash.hex())")
                
                let receiptObject: EthereumTransactionReceiptObject? // Outer declaration

                do {
                    print("DEBUG: createGame - Attempting to fetch receipt for tx (\(transactionHash.hex())) with retries...")
                    
                    // Assign to the outer receiptObject
                    receiptObject = try await retryReceiptFetch(
                        txHash: transactionHash,
                        web3Instance: self.web3!.eth,
                        maxAttempts: 5,
                        initialDelaySeconds: 5.0,
                        maxDelaySeconds: 45.0,
                        backoffFactor: 2.0
                    )
                    
                    if receiptObject == nil {
                        print("DEBUG: createGame - retryReceiptFetch completed, but receiptObject is still nil (no receipt found).")
                        // The guard let receipt = receiptObject below will catch this and throw Err.txFail.
                    }

                } catch {
                    // This catch handles errors thrown BY retryReceiptFetch.
                    // If an error is thrown here, we won't reach the 'guard let receipt = receiptObject'
                    // because the function will exit via this throw.
                    print("DEBUG: createGame - FAILED during receipt fetching phase (retry mechanism threw an error). Hash: \(transactionHash.hex()). Error: \(error.localizedDescription)")
                    throw Err.txFail
                }

                // This guard now correctly refers to the 'receiptObject' that was assigned (or not) in the 'do' block.
                guard let receipt = receiptObject else {
                    print("DEBUG: createGame - Receipt was NIL after all attempts (retryReceiptFetch returned nil). Hash: \(transactionHash.hex()). Throwing Err.txFail.")
                    throw Err.txFail
                }
                
        
        guard let receipt = receiptObject else {
            print("DEBUG: createGame - Receipt was NIL after all attempts (or an error occurred that didn't assign it) for hash: \(transactionHash.hex()).")
            throw Err.txFail
        }

//        guard let receipt = receiptObject else {
//            print("DEBUG: createGame - Receipt was NIL for hash: \(transactionHash.hex()).")
//            throw Err.txFail
//        }

        print("DEBUG: createGame - Got Receipt for hash: \(transactionHash.hex()). Contents:")
        print("DEBUG: createGame -   Tx Index: \(receipt.transactionIndex.quantity)")
        print("DEBUG: createGame -   Block Hash: \(receipt.blockHash.hex())")
        print("DEBUG: createGame -   Block Number: \(receipt.blockNumber.quantity)")
        print("DEBUG: createGame -   Cumulative Gas Used: \(receipt.cumulativeGasUsed.quantity)")
        print("DEBUG: createGame -   Gas Used by Tx: \(receipt.gasUsed.quantity)")
        print("DEBUG: createGame -   Logs Bloom: \(receipt.logsBloom.hex())")

        if let contractAddr = receipt.contractAddress {
            print("DEBUG: createGame -   Contract Address Created: \(contractAddr.hex())")
        } else {
            print("DEBUG: createGame -   Contract Address Created: nil")
        }
        if let rootVal = receipt.root {
            print("DEBUG: createGame -   Root: \(rootVal.hex())")
        } else {
            print("DEBUG: createGame -   Root: nil")
        }
        if let statusVal = receipt.status {
            print("DEBUG: createGame -   Status: \(statusVal.quantity) (1=success, 0=fail)")
            if statusVal.quantity != BigUInt(1) {
                print("DEBUG: createGame - TRANSACTION FAILED ON-CHAIN (status is 0).")
            }
        } else {
            print("DEBUG: createGame -   Status: nil")
        }
            
        print("DEBUG: createGame -   Logs count: \(receipt.logs.count)")
        receipt.logs.enumerated().forEach { index, log in
            print("DEBUG: createGame -     Log[\(index)]: address=\(log.address.hex(eip55: true)), topics=\(log.topics.map { $0.hex() }), data=\(log.data.hex())")
        }

        guard let statusValue = receipt.status, statusValue.quantity == BigUInt(1) else {
            print("DEBUG: createGame - Guard for tx success failed. Status: \(receipt.status?.quantity.description ?? "nil"). Throwing Err.txFail for hash: \(transactionHash.hex())")
            throw Err.txFail
        }
        
        print("DEBUG: createGame - Tx successful (status 1), parsing logs.")
        
        let knownFactoryAddress = transactionTo
       
        let eventSignatureHex = "0x4f0d1d413a983b9df8ab6ab954635b186a1e9a09ee6dc1b43263ddbf48412267"
        // The following assumes `Bytes(hex: String)` exists or `String.bytesFromHex()`
        // This part is critical and depends on Web3.swift's utility for hex-to-bytes conversion.
        // A common pattern in Web3.swift for EthereumData from hex is often NOT direct.
        // It might be via `try EthereumData(ethereumValue: "0x...")` if that exists and handles hex.
        // Or, more fundamentally, convert hex string to Data, then Data to Bytes [UInt8].

        // Let's search for how Web3.swift typically does this for EthereumData.
        // EthereumData itself might have a failable initializer or a static method.
        // Given your EthereumData struct:
        // public init(_ bytes: Bytes)
        // We need to get Bytes from the hex string first.

        // String extension is common:
        // public func bytesFromHex() -> Bytes? { ... }
        // OR:
        // Data(hexString: String) // from a common Swift extension, then .bytes

        // Let's use a temporary placeholder for bytes conversion that SHOULD exist in a crypto library.
        // This will likely be something like:
        // guard let signatureBytes = Bytes(hex: eventSignatureHex) else { throw SomeError }
        // OR (if String has an extension):
        // guard let signatureBytes = eventSignatureHex.bytesFromHex() else { throw SomeError }

        // The simplest placeholder that should compile if an appropriate initializer exists:
        // (Web3.swift often uses `init(ethereumValue: String)` which can parse hex)
        let expectedEventSignature: EthereumData
        do {
            // Try a common Web3.swift pattern for creating EthereumData from a hex string.
            // This initializer might exist on EthereumData or be available through a typealias/extension.
            // It typically handles the "0x" prefix.
            expectedEventSignature = try EthereumData(ethereumValue: eventSignatureHex)
        } catch {
            print("DEBUG: createGame - FATAL: Could not create EthereumData from event signature hex. Error: \(error)")
            throw Err.decode // Or a more appropriate error
        }

        // FIX 2: Break up the log finding expression
        var foundGameCreatedLog: EthereumLogObject? = nil
        for log in receipt.logs {
            let addressMatches = (log.address.hex(eip55: true) == knownFactoryAddress.hex(eip55: true))
            let topicCountMatches = (log.topics.count == 2)
            let signatureMatches = (log.topics.first == expectedEventSignature)
            
            if addressMatches && topicCountMatches && signatureMatches {
                foundGameCreatedLog = log
                break
            }
        }

        guard let gameCreatedLog = foundGameCreatedLog else {
            print("DEBUG: createGame - GameCreated event log not found in receipt for hash: \(transactionHash.hex()). Expected from: \(knownFactoryAddress.hex(eip55: true)). Logs found: \(receipt.logs.count). Reviewing all logs:")
            receipt.logs.enumerated().forEach { index, log in
                print("DEBUG: createGame - All Receipt Logs[\(index)]: address=\(log.address.hex(eip55: true)), topics=\(log.topics.map { $0.hex() }), data=\(log.data.hex())")
            }
            throw Err.eventMiss
        }
        
        print("DEBUG: createGame - Found GameCreated event log. Topics: \(gameCreatedLog.topics.map { $0.hex() })")
        
        let gameAddressBytes = gameCreatedLog.topics[1]
        let newGameAddr = "0x" + gameAddressBytes.hex().suffix(40)

        print("DEBUG: createGame - Successfully decoded game address. New Game Address: \(newGameAddr)")
        
        self.currentGameAddress = newGameAddr
        print("DEBUG: createGame - currentGameAddress updated to: \(self.currentGameAddress ?? "nil")")
        return newGameAddr
    }
    
    
    
//    /// Make a move on the 3×3 board.
//    func makeMove(by player: Int, row: UInt8, col: UInt8) async throws {
//        guard let game,
//              let call = game["makeMove"]?(row, col) else { throw Err.noGame }
//
//        let key   = try privKey(player)
//        let hash  = try await call.send(gasLimit: 500_000, from: key.address).wait()
//
//        let rcpt  = try await web3!.eth
//            .getTransactionReceipt(transactionHash: EthereumData(hash)).wait()
//
//        guard rcpt?.status?.quantity == BigUInt(1) else { throw Err.txFail }
//    }
    
    // In BlockchainService.swift

    func makeMove(by player: Int, row: UInt8, col: UInt8) async throws { // No return value needed, throws on error
        // 1. Ensure game object is ready and get invocation
        guard let gameInstance = self.game else { // self.game should be the initialized MultiPlayerTicTacToe contract object
            print("DEBUG: makeMove - Guard failed: self.game object is nil.")
            throw Err.noGame // Error 1 (noGame)
        }
        // Prepare the 'makeMove(uint8,uint8)' contract call with parameters.
        // This returns 'any SolidityInvocation'.
        guard let invocation: SolidityInvocation = gameInstance["makeMove"]?(row, col) else { // Explicitly type as SolidityInvocation protocol
            print("DEBUG: makeMove - Guard failed: Could not create invocation for 'makeMove' with params (\(row), \(col)).")
            throw Err.noGame // Error 1 (noGame)
        }

        // 2. Extract the target contract address and the encoded call data
        //    Use methods/properties available directly on the SolidityInvocation protocol or its handler.
        guard let transactionTo: EthereumAddress = invocation.handler.address else { // Target address is from the invocation's handler
             print("DEBUG: makeMove - Guard failed: Invocation handler address is nil (this is gameInstance.address).")
             throw Err.noGame
        }
        guard let transactionData: EthereumData = invocation.encodeABI() else { // Get encoded data using encodeABI() method
            print("DEBUG: makeMove - Guard failed: Could not encode ABI for 'makeMove' invocation.")
            throw Err.noGame // Or a more specific encoding error
        }
        
        // 3. Get private key and derived 'from' address
        let privateKey: EthereumPrivateKey = try privKey(player)
        let fromAddress: EthereumAddress = privateKey.address
        
        print("DEBUG: makeMove - Player \(player + 1) (\(fromAddress.hex(eip55: true))) making move (\(row), \(col)) on Game: \(transactionTo.hex(eip55: true))")
        print("DEBUG: makeMove - Transaction Data: \(transactionData.hex())")

        // 4. Manually construct, sign, and send transaction
        let transactionHash: EthereumData
        do {
            print("DEBUG: makeMove - Manually constructing, signing, and sending 'makeMove' transaction...")

            // a. Get Nonce
            let nonce = try await web3!.eth.getTransactionCount(address: fromAddress, block: .pending).wait()
            
            // b. Get Gas Price
            let gasPrice = try await web3!.eth.gasPrice().wait()

            // c. Estimate Gas Limit
            //    Create EthereumCall object for estimation using 'to' and 'data' extracted above.
            let callForEstimation = EthereumCall(
                from: fromAddress,
                to: transactionTo,    // Use 'to' address from invocation.handler.address
                gasPrice: gasPrice,
                value: EthereumQuantity(quantity: 0), // makeMove is not payable
                data: transactionData  // Use 'data' from invocation.encodeABI()
            )
            print("DEBUG: makeMove -   Estimating gas for call: from=\(fromAddress.hex(eip55: true)), to=\(transactionTo.hex(eip55: true)), data=\(transactionData.hex())")
            let gasLimit = try await web3!.eth.estimateGas(call: callForEstimation).wait()
            
            print("DEBUG: makeMove -   Nonce: \(nonce.quantity), GasPrice: \(gasPrice.quantity), Estimated GasLimit: \(gasLimit.quantity)")
            
            // d. Define Chain ID for EIP-155 signing
            let chainIdBigUInt = useLocal ? BigUInt(cfg("HARDHAT_CHAIN_ID", "31337").replacingOccurrences(of: "L", with: ""))! : BigUInt(cfg("SEPOLIA_CHAIN_ID", "11155111").replacingOccurrences(of: "L", with: ""))!
            let ethereumChainIdForSigning = EthereumQuantity(quantity: chainIdBigUInt)
            print("DEBUG: makeMove -   Using Chain ID for signing: \(chainIdBigUInt)")
            
            // e. Create the Unsigned EthereumTransaction object using invocation.createTransaction
            //    This method populates 'to', 'data', etc., based on the invocation and provided params.
            guard let unsignedTransaction = invocation.createTransaction(
                nonce: nonce, gasPrice: gasPrice, maxFeePerGas: nil, maxPriorityFeePerGas: nil, gasLimit: gasLimit,
                from: fromAddress, value: EthereumQuantity(quantity: 0), accessList: [:], transactionType: .legacy
            ) else {
                 print("DEBUG: makeMove - Guard failed: Could not create EthereumTransaction from invocation.createTransaction.")
                 throw Err.noGame // Or more specific error like "encodingError"
            }
            print("DEBUG: makeMove -   Unsigned Tx (from invocation.createTransaction): to=\(unsignedTransaction.to?.hex(eip55: true) ?? "nil"), data=\(unsignedTransaction.data.hex())")

            // f. Sign the transaction using the .sign(with:chainId:) method ON the EthereumTransaction object
            print("DEBUG: makeMove -   Attempting to sign transaction using unsignedTransaction.sign(with: privateKey, chainId: ...)...")
            let signedTransaction = try unsignedTransaction.sign(
                with: privateKey,                   // The EthereumPrivateKey object
                chainId: ethereumChainIdForSigning  // The EthereumQuantity chainId
            )
            print("DEBUG: makeMove -   Transaction signed. Signed Tx v: \(signedTransaction.v.quantity), r: \(signedTransaction.r.quantity), s: \(signedTransaction.s.quantity)")

            // g. Send the signed raw transaction
            print("DEBUG: makeMove -   Sending signed raw transaction...")
            transactionHash = try await web3!.eth.sendRawTransaction(transaction: signedTransaction).wait()
            print("DEBUG: makeMove -   sendRawTransaction SUCCEEDED. TxHash: \(transactionHash.hex())")
        } catch {
            print("DEBUG: makeMove - FAILED during manual transaction cycle. Error: \(error.localizedDescription)")
            print("DEBUG: makeMove - Error Details: \(error)")
            throw error
        }
        
        // 5. Get receipt (using retry helper)
        print("DEBUG: makeMove - Tx sent (\(transactionHash.hex())), attempting to fetch receipt with retries...")
        let receiptObject: EthereumTransactionReceiptObject? = try await retryReceiptFetch(
            txHash: transactionHash, web3Instance: self.web3!.eth, maxAttempts: 5,
            initialDelaySeconds: 5.0, maxDelaySeconds: 45.0, backoffFactor: 2.0
        )

        // 6. Guard for successful transaction receipt and status
        guard let receipt = receiptObject, let status = receipt.status, status.quantity == BigUInt(1) else {
            print("DEBUG: makeMove - Receipt not found or tx failed on-chain for hash: \(transactionHash.hex()). Status: \(receiptObject?.status?.quantity.description ?? "nil receipt or status")")
            throw Err.txFail // Error 2 (txFail)
        }

        // Transaction for move was successful
        print("DEBUG: makeMove - Transaction for move successful. Hash: \(transactionHash.hex()), Status: 1. Logs count: \(receipt.logs.count)")
        
        // Correctly initialize expectedMoveMadeSig
        let moveMadeEventSignatureHex = "0x10ac166a969b6ae9b140c9d6b88c6c4e565e4fc22f858bf92f1542535f0f161a" // keccak256("MoveMade(address,uint8,uint8)")
        let expectedMoveMadeSig: EthereumData
        do {
            // Use the throwing initializer EthereumData(ethereumValue: String)
            expectedMoveMadeSig = try EthereumData(ethereumValue: moveMadeEventSignatureHex)
        } catch {
            print("DEBUG: makeMove - CRITICAL ERROR: Could not create EthereumData from MoveMade event signature hex '\(moveMadeEventSignatureHex)'. Error: \(error)")
            // If this fails, we cannot reliably parse MoveMade events.
            // Depending on requirements, you might throw, or log and continue without specific MoveMade parsing.
            throw Err.decode // Or a new, more specific error type like "ConfigurationError"
        }
        
        // Filter and print MoveMade logs
        receipt.logs.filter {
            $0.address.hex(eip55: true) == transactionTo.hex(eip55: true) && // Compare EIP55 checksummed addresses
            $0.topics.count > 0 && // Ensure there's at least one topic for the signature
            $0.topics.first == expectedMoveMadeSig
        }.enumerated().forEach { index, log in
            print("DEBUG: makeMove -     MoveMade Log[\(index)]: topics=\(log.topics.map { $0.hex() }), data=\(log.data.hex())")
        }
        // No return value needed for makeMove, success is implied by not throwing.
    }

//    /// Fetch the board (`address[3][3]` → `[[String]]`)
//    func board() async throws -> [[String]] {
//        guard let game,
//              let call = game["getBoardState"]?() else { throw Err.noGame }
//
//        let any = try await call.call().wait()
//        guard let raw = any as? [[EthereumAddress]] else { throw Err.decode }
//        return raw.map { $0.map { $0.hex(eip55: false) } }
//    }
    
    func board() async throws -> [[String]] {
        print("DEBUG: service.board() - Attempting to fetch board.")
        guard let gameInstance = self.game else {
            print("DEBUG: service.board() - FAILED: self.game object is nil.")
            throw Err.noGame
        }
        guard let call = gameInstance["getBoardState"]?() else {
            print("DEBUG: service.board() - FAILED: Could not create 'getBoardState' invocation.")
            throw Err.noGame
        }

        print("DEBUG: service.board() - Calling 'getBoardState' on game: \(gameInstance.address?.hex(eip55: true) ?? "N/A")")
        let resultFromCall = try await call.call().wait() // resultFromCall is [String: Any]? or similar from PromiseKit
        print("DEBUG: service.board() - 'getBoardState' call.call().wait() returned (type: \(type(of: resultFromCall))): \(String(describing: resultFromCall))")

        // The result from call.call().wait() for a contract call that returns values is typically [String: Any]
        // where keys are output names (or empty string for single unnamed output).
        guard let resultDictionary = resultFromCall as? [String: Any] else {
            print("DEBUG: service.board() - FAILED: Expected a Dictionary from call result, got \(type(of: resultFromCall)).")
            throw Err.decode
        }

        // The Solidity function `getBoardState() view returns (address[3][3])` has one unnamed output.
        // Web3.swift often returns such single, unnamed outputs with an empty string "" as the key.
        guard let boardDataUntyped = resultDictionary[""] else { // Access the value for the empty string key
            print("DEBUG: service.board() - FAILED: Could not find board data under the empty string key '\"\"' in the result dictionary. Keys: \(resultDictionary.keys)")
            throw Err.decode
        }
        
        print("DEBUG: service.board() - Extracted data under key '': \(String(describing: boardDataUntyped)) (type: \(type(of: boardDataUntyped)))")

        // Now, cast this specific data to [[EthereumAddress]]
        guard let rawBoard = boardDataUntyped as? [[EthereumAddress]] else {
            print("DEBUG: service.board() - FAILED to cast board data to [[EthereumAddress]]. Actual type of data under key '': \(type(of: boardDataUntyped)).")
            throw Err.decode // Error 4
        }
        
        // If the cast succeeds, rawBoard is [[EthereumAddress]]
        let boardHex = rawBoard.map { row in
            row.map { ethAddr in
                ethAddr.hex(eip55: false) // Use false for non-checksummed if your emoji func expects lowercase
            }
        }
        print("DEBUG: service.board() - Successfully fetched and decoded board: \(boardHex)")
        return boardHex
    }
//    
//    // BlockchainService.swift
//    func board() async throws -> [[String]] {
//        print("DEBUG: service.board() - Attempting to fetch board.") // We should see this log
//        guard let gameInstance = self.game else {
//            print("DEBUG: service.board() - FAILED: self.game object is nil.")
//            throw Err.noGame // Error 1
//        }
//        guard let call = gameInstance["getBoardState"]?() else { // This should be a SolidityReadInvocation
//            print("DEBUG: service.board() - FAILED: Could not create 'getBoardState' invocation.")
//            throw Err.noGame // Error 1
//        }
//
//        print("DEBUG: service.board() - Calling 'getBoardState' on game: \(gameInstance.address?.hex(eip55: true) ?? "N/A")")
//        let any = try await call.call().wait() // This makes the RPC call (eth_call)
//        print("DEBUG: service.board() - 'getBoardState' call returned: \(String(describing: any))") // <<< WHAT DOES THIS PRINT?
//        
//        // This is where Err.decode is thrown if the cast fails
//        guard let raw = any as? [[EthereumAddress]] else {
//            print("DEBUG: service.board() - FAILED to decode board data. Expected [[EthereumAddress]], got \(type(of: any)). Full data: \(String(describing: any))") // Added full data print
//            throw Err.decode // Error 4
//        }
//        let boardHex = raw.map { row in row.map { addr in addr.hex(eip55: false) } } // Use false for non-checksummed if that's what your emoji func expects
//        print("DEBUG: service.board() - Successfully fetched and decoded board: \(boardHex)")
//        return boardHex
//    }

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
    
    // In BlockchainService.swift

    private func buildFactory() {
        print("DEBUG: buildFactory - ENTER. factoryAddress: \(factoryAddress ?? "nil"), factoryABI is \(factoryABI == nil ? "nil" : "loaded")")
        print("DEBUG: buildFactory - web3 object is \(web3 == nil ? "nil" : "NOT nil") at this point.")
        
        guard let a = factoryAddress,
              let abiString = factoryABI, // Rename to abiString for clarity
              let ea  = try? EthereumAddress(hex: a, eip55: false)
        else {
            print("DEBUG: buildFactory guard failed. factoryAddress: \(factoryAddress ?? "nil"), factoryABI nil? \(factoryABI == nil)")
            factory = nil; return
        }

        guard let currentWeb3 = web3 else {
            print("DEBUG: buildFactory - web3 is NIL right before trying to create contract object.")
            factory = nil
            return
        }

        guard let abiData = abiString.data(using: .utf8) else {
            print("DEBUG: buildFactory - FAILED to convert ABI string to UTF8 Data.")
            factory = nil
            return
        }

        do {
            // --- Try to create the contract object ---
            factory = try currentWeb3.eth.Contract(
                json: abiData, // Use the Data object
                abiKey: nil,   // Correctly nil
                address: ea
            )
            // --- --- --- --- --- --- --- --- --- --- --
            
            if factory != nil {
                print("DEBUG: buildFactory - Successfully created FACTORY contract object for address: \(a)")
            } else {
                // This case should ideally not be hit if the try currentWeb3.eth.Contract throws on failure,
                // but good for defensive programming.
                print("DEBUG: buildFactory - Contract(...) returned nil WITHOUT throwing for FACTORY address: \(a)")
            }
            
        } catch {
            // This block will execute if 'try currentWeb3.eth.Contract(...)' throws an error
            print("DEBUG: buildFactory - FAILED to create FACTORY contract object for address: \(a).")
            print("DEBUG: buildFactory - Error during Contract creation: \(error.localizedDescription)")
            print("DEBUG: buildFactory - Underlying contract creation error details: \(error)")
            factory = nil
        }
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

    // In BlockchainService.swift

    private func buildGame() {
        print("DEBUG: buildGame - ENTER. currentGameAddress: \(currentGameAddress ?? "nil"), gameABI is \(gameABI == nil ? "nil" : "loaded")")
        print("DEBUG: buildGame - web3 object is \(web3 == nil ? "nil" : "NOT nil") at this point.")

        guard let a = currentGameAddress,
              let abiString = gameABI, // Rename to abiString for clarity
              let ea = try? EthereumAddress(hex: a, eip55: false)
        else {
            print("DEBUG: buildGame guard failed. currentGameAddress: \(currentGameAddress ?? "nil"), gameABI nil? \(gameABI == nil)")
            game = nil; return
        }

        guard let currentWeb3 = web3 else {
            print("DEBUG: buildGame - web3 is NIL right before trying to create contract object.")
            game = nil
            return
        }
        
        guard let abiData = abiString.data(using: .utf8) else {
            print("DEBUG: buildGame - FAILED to convert ABI string to UTF8 Data.")
            game = nil
            return
        }

        do {
            // --- Try to create the contract object ---
            game = try currentWeb3.eth.Contract(
                json: abiData, // Use the Data object
                abiKey: nil,   // Correctly nil
                address: ea
            )
            // --- --- --- --- --- --- --- --- --- --- --
            
            if game != nil {
                print("DEBUG: buildGame - Successfully created GAME contract object for address: \(a)")
            } else {
                print("DEBUG: buildGame - Contract(...) returned nil WITHOUT throwing for GAME address: \(a)")
            }

        } catch {
            print("DEBUG: buildGame - FAILED to create GAME contract object for address: \(a).")
            print("DEBUG: buildGame - Error during Contract creation: \(error.localizedDescription)")
            print("DEBUG: buildGame - Underlying contract creation error details: \(error)")
            game = nil
        }
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
        let lowercasedAddr = addr.lowercased()
           // Explicitly check for ZERO_ADDRESS (case-insensitive)
           if lowercasedAddr == ZERO_ADDRESS.lowercased() {
               return "" // Return an empty string for zero address
           }
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
