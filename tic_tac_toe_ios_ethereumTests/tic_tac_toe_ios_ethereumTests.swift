//
//  tic_tac_toe_ios_ethereumTests.swift
//  tic_tac_toe_ios_ethereumTests
//
//  Created by Agent Malone on 5/13/25.
//

import Testing
import Foundation
import Web3
import Web3ContractABI
import BigInt
@testable import tic_tac_toe_ios_ethereum

struct tic_tac_toe_ios_ethereumTests {

    // MARK: - Basic Functionality Tests
    
    @Test func testBlockchainServiceInitialization() async throws {
        let service = BlockchainService()
        
        // Test that service initializes with correct default values
        #expect(service.useLocal == true)
        #expect(service.factoryAddress != nil)
        #expect(service.currentGameAddress == nil)
        #expect(service.player1 != "–")
        #expect(service.player2 != "–")
        #expect(service.rpcURL != "–")
    }
    
    @Test func testNetworkSwitching() async throws {
        let service = BlockchainService()
        
        // Test switching to testnet
        service.useLocal = false
        
        // Allow some time for the reset to complete
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        #expect(service.useLocal == false)
        #expect(service.rpcURL.contains("sepolia"))
    }
    
    @Test func testEmojiForAddress() async throws {
        let service = BlockchainService()
        
        // Test zero address returns empty string
        let zeroAddressEmoji = service.emojiForAddress(ZERO_ADDRESS)
        #expect(zeroAddressEmoji == "")
        
        // Test non-zero address returns emoji
        let testAddress = "0x1234567890123456789012345678901234567890"
        let emoji = service.emojiForAddress(testAddress)
        #expect(emoji.count > 0)
        #expect(emoji != "❓")
        
        // Test consistency - same address should return same emoji
        let emoji2 = service.emojiForAddress(testAddress)
        #expect(emoji == emoji2)
        
        // Test different addresses return different emojis (with high probability)
        let differentAddress = "0x9876543210987654321098765432109876543210"
        let differentEmoji = service.emojiForAddress(differentAddress)
        #expect(differentEmoji != emoji)
    }
    
    // MARK: - Address Validation Tests
    
    @Test func testAddressValidation() async throws {
        let service = BlockchainService()
        
        // Test valid addresses
        let validAddresses = [
            "0x1234567890123456789012345678901234567890",
            "0xA0B53DbDb0052403E38BBC31f01367aC6782118E",
            "0x340ac014d800ac398af239cebc3a376eb71b0353"
        ]
        
        for address in validAddresses {
            let emoji = service.emojiForAddress(address)
            #expect(emoji != "❓")
        }
        
        // Test invalid addresses
        let invalidAddresses = [
            "0x123", // Too short
            "invalid", // Not hex
            "", // Empty
            "0x" // Just prefix
        ]
        
        for address in invalidAddresses {
            let emoji = service.emojiForAddress(address)
            #expect(emoji == "❓")
        }
    }
    
    // MARK: - Configuration Tests
    
    @Test func testDeploymentConfiguration() async throws {
        let service = BlockchainService()
        
        // Test that deployment addresses are loaded correctly
        #expect(service.factoryAddress != nil)
        #expect(service.factoryAddress?.count == 42) // 0x + 40 hex chars
        #expect(service.factoryAddress?.hasPrefix("0x") == true)
        
        // Test network switching updates deployment addresses
        let originalFactory = service.factoryAddress
        service.useLocal = false
        
        // Allow reset to complete
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Should still have a factory address (might be same for both networks)
        #expect(service.factoryAddress != nil)
        #expect(service.factoryAddress?.count == 42)
    }
    
    // MARK: - Error Handling Tests
    
    @Test func testErrorHandling() async throws {
        let service = BlockchainService()
        
        // Test that service handles missing game gracefully
        service.currentGameAddress = nil
        
        do {
            _ = try await service.board()
            #expect(false, "Should have thrown noGame error")
        } catch BlockchainService.Err.noGame {
            // Expected error
            #expect(true)
        } catch {
            #expect(false, "Should have thrown noGame error, got \(error)")
        }
    }
    
    // MARK: - Contract Address Tests
    
    @Test func testContractAddressValidation() async throws {
        let service = BlockchainService()
        
        // Test current deployment addresses match expected format
        let expectedGameAddress = "0x340AC014d800Ac398Af239Cebc3a376eb71B0353"
        let expectedFactoryAddress = "0xa0B53DbDb0052403E38BBC31f01367aC6782118E"
        
        // Check that our deployment addresses are in the expected format
        #expect(service.factoryAddress?.lowercased() == expectedFactoryAddress.lowercased())
        
        // Test that addresses are valid Ethereum addresses
        let factoryAddr = service.factoryAddress!
        #expect(factoryAddr.hasPrefix("0x"))
        #expect(factoryAddr.count == 42)
        
        // Test hex characters only
        let hexPart = String(factoryAddr.dropFirst(2))
        #expect(hexPart.allSatisfy { $0.isHexDigit })
    }
    
    // MARK: - Utility Function Tests
    
    @Test func testUtilityFunctions() async throws {
        let service = BlockchainService()
        
        // Test derived addresses are not empty
        #expect(service.player1 != "–")
        #expect(service.player2 != "–")
        #expect(service.player1 != service.player2)
        
        // Test addresses are in correct format
        #expect(service.player1.hasPrefix("0x"))
        #expect(service.player2.hasPrefix("0x"))
        #expect(service.player1.count == 42)
        #expect(service.player2.count == 42)
    }
    
    // MARK: - State Management Tests
    
    @Test func testStateManagement() async throws {
        let service = BlockchainService()
        
        // Test initial state
        #expect(service.useLocal == true)
        #expect(service.currentGameAddress == nil)
        
        // Test setting game address
        let testGameAddress = "0x1234567890123456789012345678901234567890"
        service.currentGameAddress = testGameAddress
        
        #expect(service.currentGameAddress == testGameAddress)
        
        // Test that network switching resets game address
        service.useLocal = false
        
        // Allow reset to complete
        try await Task.sleep(nanoseconds: 100_000_000)
        
        #expect(service.currentGameAddress == nil)
    }
    
    // MARK: - Integration Tests
    
    @Test func testBlockchainConnection() async throws {
        let service = BlockchainService()
        
        // Test blockchain connection check
        let connectionResult = await service.checkBlockchainConnection()
        
        // Should return a string with connection status
        #expect(connectionResult.contains("Blockchain Connection Check"))
        
        // Result should indicate success or failure
        #expect(connectionResult.contains("SUCCESS") || connectionResult.contains("FAILED"))
    }
    
    // MARK: - Performance Tests
    
    @Test func testPerformanceOfAddressGeneration() async throws {
        let service = BlockchainService()
        let testAddress = "0x1234567890123456789012345678901234567890"
        
        // Measure time for emoji generation
        let startTime = CFAbsoluteTimeGetCurrent()
        
        for _ in 0..<1000 {
            _ = service.emojiForAddress(testAddress)
        }
        
        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
        
        // Should complete 1000 operations in reasonable time (under 1 second)
        #expect(timeElapsed < 1.0)
    }
    
    // MARK: - Edge Case Tests
    
    @Test func testEdgeCases() async throws {
        let service = BlockchainService()
        
        // Test uppercase vs lowercase addresses
        let lowerAddress = "0x1234567890123456789012345678901234567890"
        let upperAddress = "0x1234567890123456789012345678901234567890".uppercased()
        
        let lowerEmoji = service.emojiForAddress(lowerAddress)
        let upperEmoji = service.emojiForAddress(upperAddress)
        
        // Should return same emoji regardless of case
        #expect(lowerEmoji == upperEmoji)
        
        // Test with and without 0x prefix
        let withPrefix = "0x1234567890123456789012345678901234567890"
        let withoutPrefix = "1234567890123456789012345678901234567890"
        
        let prefixEmoji = service.emojiForAddress(withPrefix)
        let noPrefixEmoji = service.emojiForAddress(withoutPrefix)
        
        // Should handle both cases gracefully
        #expect(prefixEmoji != "❓")
        #expect(noPrefixEmoji != "❓")
    }
    
    // MARK: - Constants Tests
    
    @Test func testConstants() async throws {
        // Test that zero address constant is correct
        #expect(ZERO_ADDRESS == "0x0000000000000000000000000000000000000000")
        #expect(ZERO_ADDRESS.count == 42)
        #expect(ZERO_ADDRESS.hasPrefix("0x"))
        
        // Test that zero address is all zeros
        let hexPart = String(ZERO_ADDRESS.dropFirst(2))
        #expect(hexPart.allSatisfy { $0 == "0" })
    }
    
    // MARK: - Deployment Address Tests
    
    @Test func testDeploymentAddresses() async throws {
        let service = BlockchainService()
        
        // Test local deployment
        service.useLocal = true
        try await Task.sleep(nanoseconds: 100_000_000)
        
        let localFactory = service.factoryAddress
        #expect(localFactory != nil)
        
        // Test testnet deployment
        service.useLocal = false
        try await Task.sleep(nanoseconds: 100_000_000)
        
        let testnetFactory = service.factoryAddress
        #expect(testnetFactory != nil)
        
        // Both should be valid addresses
        #expect(localFactory?.hasPrefix("0x") == true)
        #expect(testnetFactory?.hasPrefix("0x") == true)
    }
}

// MARK: - Test Extensions

extension Character {
    var isHexDigit: Bool {
        return "0123456789abcdefABCDEF".contains(self)
    }
}