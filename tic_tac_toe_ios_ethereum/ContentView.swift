//
//  ContentView.swift
//  tic_tac_toe_ios_ethereum
//
//  Created by Agent Malone on 5/13/25.
//

import SwiftUI
// Removed BigInt import as we use strings for now

// Use the placeholder zero address string defined in BlockchainService
// let ZERO_ADDRESS_STRING = "0x0000000000000000000000000000000000000000"

struct ContentView: View {
    // Create an instance of our (currently fake) BlockchainService
    // @StateObject keeps it alive for the whole view
    @StateObject private var blockchainService = BlockchainService()

    // --- State variables for the UI ---
    // These hold temporary information for text boxes, status messages, etc.
    @State private var status: String? = "App Loaded. Select Network (currently fake)."
    @State private var board: [[String]]? = nil // The 3x3 grid, starts empty
    @State private var currentPlayerIdx: Int = 0 // 0 for Player 1, 1 for Player 2
    @State private var rowInput: String = "0" // Text in the row input box
    @State private var colInput: String = "0" // Text in the column input box
    @State private var gameAddressInput: String = "" // Text in the game address input box
    @State private var isLoading: Bool = false // To show a spinner during fake delays

    // --- Computed properties for display ---
    // Get shortened versions of player addresses for display
    private var player1DisplayAddress: String {
        shortenAddress(blockchainService.player1Address)
    }
    private var player2DisplayAddress: String {
        shortenAddress(blockchainService.player2Address)
    }

    // Helper function to make addresses shorter (e.g., 0x123...abcd)
    private func shortenAddress(_ address: String?) -> String {
        guard let addr = address, addr.count > 10 else { return address ?? "N/A" }
        return "\(addr.prefix(6))...\(addr.suffix(4))"
    }

    // --- The main body of the UI ---
    var body: some View {
        NavigationView { // Provides a top bar area (though we hide it)
            ScrollView { // Allows scrolling if content gets too long
                VStack(spacing: 10) { // Arrange things vertically
                    
                    // Title Text
                    Text("Tic-Tac-Toe Matrix")
                        .font(.largeTitle)
                        .foregroundColor(.matrixGreen) // Use our theme color
                        .padding(.bottom)

                    // Section for Network switching and printing addresses
                    networkControls()

                    // Section for Factory and Game creation/joining
                    factoryAndGameControls()

                    // Only show move controls and board if a game address is set
                    if blockchainService.currentGameAddress != nil {
                        moveControls()
                        boardView()
                            .padding(.top) // Add space above the board
                    } else if isLoading {
                        // Show spinner if loading but no game address yet (e.g., during createGame)
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .matrixGreen))
                            .padding()
                    }


                    // Display status messages at the bottom
                    if let statusText = status {
                        Text(statusText)
                            .font(.caption)
                            .foregroundColor(statusText.lowercased().contains("error") ? .matrixError : .matrixGreen) // Use error color if needed
                            .padding(.top)
                            .multilineTextAlignment(.center)
                            .frame(minHeight: 40) // Give status text some space
                    }

                    // Section for Debug buttons
                    debugCallsView()
                        .padding(.top)

                }
                .padding() // Add padding around the main VStack content
            }
            .background(Color.matrixBlack.ignoresSafeArea()) // Set background to black
            .navigationBarHidden(true) // Hide the default top navigation bar
            .preferredColorScheme(.dark) // Hint to the system we prefer dark mode

            // --- Reactions to changes ---

             // When the current game address in the service changes...
            .onChange(of: blockchainService.currentGameAddress) { newGameAddress in
                 // Update the text field input
                 gameAddressInput = newGameAddress ?? ""
                 if newGameAddress != nil {
                     // If we have a new game, try to load its board state (fake load)
                     refreshBoardState()
                 } else {
                     board = nil // Clear the board if game address is removed
                 }
            }
            // When the factory address in the service changes...
            .onChange(of: blockchainService.factoryAddress) { newFactoryAddress in
                if newFactoryAddress == nil {
                    status = "Factory address cleared. (Dummy)"
                } else {
                    status = "Factory: \(shortenAddress(newFactoryAddress)) (Dummy/Loaded)"
                }
            }
            // Simple alert for errors (can be improved)
            .alert("Info / Error", isPresented: .constant(status?.lowercased().contains("error:") == true || status?.lowercased().contains("failed") == true), actions: {
                Button("OK") { status = nil } // Just dismiss
            }, message: {
                Text(status ?? "An unknown issue occurred.")
            })

        }
        // Make sure touches outside textfields dismiss the keyboard (uncomment if needed)
        // .onTapGesture {
        //     hideKeyboard()
        // }
    }

    // --- Helper Views for Sections ---

    // Builds the Network and Address buttons
    @ViewBuilder
    private func networkControls() -> some View {
        HStack { // Arrange horizontally
            // Button to toggle between Local/Sepolia (fake)
            Button(blockchainService.isLocal ? "LOCAL ✔" : "SEPOLIA ✔") {
                isLoading = true // Show spinner briefly
                blockchainService.isLocal.toggle() // Tell the service to switch
                // Reset UI state related to a specific network/game
                board = nil
                status = "Switched to \(blockchainService.isLocal ? "LOCAL" : "SEPOLIA") (Fake)"
                isLoading = false
            }
            .buttonStyle(MatrixButtonStyle()) // Use our green button style

            // Button to print addresses (fake)
            Button("Print Addrs") {
                blockchainService.printDerivedAddresses()
                status = "Printed fake addresses to console."
            }
            .buttonStyle(MatrixSecondaryButtonStyle()) // Use bordered style
        }
        // Reminder about deployment
        Text("NOTE: Contract deployment (npx tsx) must be done manually from your desktop.")
            .font(.caption2)
            .foregroundColor(.matrixError.opacity(0.8))
            .multilineTextAlignment(.center)
            .padding(.vertical, 5)
    }

    // Builds the Factory and Game controls
    @ViewBuilder
    private func factoryAndGameControls() -> some View {
        // Display the current factory address (fake)
        Text("Factory: \(shortenAddress(blockchainService.factoryAddress) )")
             .foregroundColor(.matrixGreen.opacity(0.8))
             .font(.footnote)
             .padding(.bottom, 5)

        // Button to "load" factory (just updates status for now)
        Button("Load Factory Info") {
            if let factory = blockchainService.factoryAddress {
                status = "Factory: \(shortenAddress(factory)) (Dummy/Loaded)"
            } else {
                status = "Fake factory address not found."
            }
        }
        .buttonStyle(MatrixButtonStyle())

        // Button to create a game (fake)
        Button("Create Game (P1)") {
            // Run the fake blockchain action
            performBlockchainAction(loadingMessage: "Creating fake game...") {
                // Tell the service to create a game
                if let newGameAddrHex = try await blockchainService.createGameByPlayer(playerIndex: 0) {
                    // If it "succeeds", update status
                    return "Fake game created: \(shortenAddress(newGameAddrHex))"
                } else {
                    return "Error: Fake game creation failed." // Should not happen with fake func yet
                }
            }
        }
        .buttonStyle(MatrixButtonStyle())
        // Disable button if no factory address or if already loading
        .disabled(blockchainService.factoryAddress == nil || isLoading)

        // Text field for manually entering/seeing game address
        HStack {
            TextField("Game Address", text: $gameAddressInput)
                .textFieldStyle(MatrixTextFieldStyle()) // Use our matrix text box style
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .keyboardType(.asciiCapable) // Allow hex characters

            // Button to "join" the game entered in the text field
            Button("Join Game") {
                // Basic check if it looks like an address (can be improved)
                if gameAddressInput.hasPrefix("0x") && gameAddressInput.count > 10 {
                    // Tell the service to use this address
                    blockchainService.currentGameAddress = gameAddressInput
                    status = "Joined fake game: \(shortenAddress(gameAddressInput))"
                    // Try to refresh the board for the newly joined game (fake)
                    refreshBoardState()
                } else {
                    status = "Error: Invalid game address format entered."
                }
            }
            .buttonStyle(MatrixSecondaryButtonStyle())
            // Disable if text field is empty
            .disabled(gameAddressInput.isEmpty)
        }
        .padding(.top, 5)
    }

    // Builds the controls for making a move
    @ViewBuilder
    private func moveControls() -> some View {
        VStack { // Arrange vertically
             // Display current game address
             Text("Current Game: \(shortenAddress(blockchainService.currentGameAddress))")
                 .foregroundColor(.matrixGreen.opacity(0.8))
                 .font(.footnote)

            // Button to switch the current player (signer)
            HStack {
                Button("Signer: P\(currentPlayerIdx + 1) (\(currentPlayerIdx == 0 ? player1DisplayAddress : player2DisplayAddress))") {
                    currentPlayerIdx = (currentPlayerIdx + 1) % blockchainService.getPlayerCount()
                    status = "Switched signer to Player \(currentPlayerIdx + 1)"
                }
                .buttonStyle(MatrixSecondaryButtonStyle())
            }
            .padding(.bottom, 5)

            // Row/Col input boxes and Make Move button
            HStack {
                // Row input
                TextField("Row", text: $rowInput)
                    .textFieldStyle(MatrixTextFieldStyle())
                    .keyboardType(.numberPad) // Show number pad keyboard
                    .frame(width: 70) // Fixed width

                // Column input
                TextField("Col", text: $colInput)
                    .textFieldStyle(MatrixTextFieldStyle())
                    .keyboardType(.numberPad)
                    .frame(width: 70)

                Spacer() // Pushes button to the right

                // Make Move button (fake)
                Button("Make Move") {
                    // Get row/col numbers from the text fields
                    guard let r = Int(rowInput), let c = Int(colInput),
                          (0...2).contains(r), (0...2).contains(c) else {
                        status = "Error: Invalid row/col (must be 0-2)."
                        return
                    }
                    // Run the fake blockchain action
                    performBlockchainAction(loadingMessage: "Submitting fake move...") {
                        // Tell the service to make the move
                        _ = try await blockchainService.makeMove(playerIndex: currentPlayerIdx, row: r, col: c)
                        
                        // After fake move, refresh the board (fake)
                        await refreshBoardState(calledFromMove: true)

                        // Check fake game status after move
                        let ended = try await blockchainService.readBool(fnName: "gameEnded")
                        let winnerHex = try await blockchainService.readAddress(fnName: "winner")

                        if ended {
                             if winnerHex.lowercased() == ZERO_ADDRESS_STRING_PLACEHOLDER.lowercased() {
                                return "Fake Draw!"
                            } else if winnerHex.lowercased() == blockchainService.player1Address?.lowercased() {
                                return "Fake: Player 1 (\(player1DisplayAddress)) wins!"
                            } else if winnerHex.lowercased() == blockchainService.player2Address?.lowercased() {
                                return "Fake: Player 2 (\(player2DisplayAddress)) wins!"
                            } else {
                                return "Fake Game over. Winner: \(shortenAddress(winnerHex))"
                            }
                        } else {
                            return "Fake Move OK. Next player."
                        }
                    }
                }
                .buttonStyle(MatrixButtonStyle())
                // Disable if no game address or already loading
                .disabled(blockchainService.currentGameAddress == nil || isLoading)
            }
        }
    }

    // Builds the 3x3 Tic Tac Toe board display
    @ViewBuilder
    private func boardView() -> some View {
         // Show spinner if loading the board
         if isLoading && board == nil {
             ProgressView()
                 .progressViewStyle(CircularProgressViewStyle(tint: .matrixGreen))
                 .padding()
         } else if let currentBoard = board { // If board data exists
             VStack(spacing: 4) { // Vertical stack for rows, small spacing
                 ForEach(0..<3, id: \.self) { rowIndex in // Loop 3 times for rows
                     HStack(spacing: 4) { // Horizontal stack for cells in a row
                         ForEach(0..<3, id: \.self) { colIndex in // Loop 3 times for columns
                             // Get the owner address from the board data
                             let owner = currentBoard[rowIndex][colIndex]
                             // Get the display mark (X, O, or empty)
                             let mark = blockchainService.emojiForAddress(owner)

                             // Display the cell content in a bordered box
                             Text(mark)
                                 .font(.system(size: 30)) // Mark size
                                 .frame(width: 60, height: 60) // Cell size
                                 .background(Color.matrixBlack) // Cell background
                                 // Cell border
                                 .border(Color.matrixGreen.opacity(0.7), width: 1)
                                 .foregroundColor(.matrixGreen) // Mark color
                         }
                     }
                 }
             }
         } else {
              // Message if board hasn't loaded or no game
              Text("Board not loaded or no active game.")
                 .foregroundColor(.matrixGreen.opacity(0.7))
                 .padding()
         }
    }

    // Builds the Debug call buttons
    @ViewBuilder
    private func debugCallsView() -> some View {
        VStack {
            Text("Debug Calls (Fake)")
                .font(.headline)
                .foregroundColor(.matrixGreen)
                .padding(.bottom, 5)

            HStack {
                Button("🔄 Refresh Board") { refreshBoardState() }
                Button("🏁 gameEnded") {
                    // Read the fake "gameEnded" value
                    readContractValue(description: "Fake Game Ended?") {
                        // Ask the service for the fake value
                        try await blockchainService.readBool(fnName: "gameEnded").description
                    }
                }
            }
            .buttonStyle(MatrixSecondaryButtonStyle())

            HStack {
                Button("👤 lastPlayer") {
                     readContractValue(description: "Fake Last Player") {
                         shortenAddress(try await blockchainService.readAddress(fnName: "lastPlayer"))
                    }
                }
                Button("🏆 winner") {
                    readContractValue(description: "Fake Winner") {
                         shortenAddress(try await blockchainService.readAddress(fnName: "winner"))
                    }
                }
            }
            .buttonStyle(MatrixSecondaryButtonStyle())

            HStack {
                 Button("📍 currentGame") {
                    status = "Current fake game: \(shortenAddress(blockchainService.currentGameAddress))"
                }
                Button("🏭 factoryAddr") {
                    status = "Fake Factory: \(shortenAddress(blockchainService.factoryAddress))"
                }
            }
            .buttonStyle(MatrixSecondaryButtonStyle())
        }
        // Disable most debug buttons if no game address is set
        .disabled(blockchainService.currentGameAddress == nil && !(status?.contains("currentGame") == true || status?.contains("factoryAddr") == true ))
    }


    // --- Helper Functions for Actions ---

    // Shows spinner, runs fake async task, handles fake errors, hides spinner
    private func performBlockchainAction(loadingMessage: String, action: @escaping () async throws -> String) {
        guard !isLoading else { return } // Prevent multiple actions at once
        
        isLoading = true
        status = loadingMessage
        // Dismiss keyboard if it's open before starting action
        hideKeyboard()

        Task { // Run the async work in the background
            do {
                let successMessage = try await action() // Call the provided fake action
                status = successMessage // Update status with success message
            } catch {
                // Handle fake errors
                print("🚨 FAKE Error: \(error)")
                let nsError = error as NSError
                var errorMessage = "Error: \(nsError.localizedDescription)"
                // Simplify error messages for the fake service
                if let desc = nsError.userInfo[NSLocalizedDescriptionKey] as? String {
                     errorMessage = "Error: \(desc)"
                }
                status = errorMessage // Show the error message
            }
            isLoading = false // Hide spinner when done
        }
    }

    // Specific helper to refresh the board state (fake)
    private func refreshBoardState(calledFromMove: Bool = false) {
        guard blockchainService.currentGameAddress != nil else {
            if !calledFromMove { // Don't show error if just called after a move failed on no game addr
                 status = "No active game to refresh board for."
            }
            board = nil
            return
        }
        
        // Don't show "refreshing" message if just called after making a move
        let loadingMsg = calledFromMove ? status ?? "Loading board after move..." : "Refreshing fake board..."
        
        // Use the general action performer
        performBlockchainAction(loadingMessage: loadingMsg) {
            let newBoard = try await blockchainService.getBoardState() // Get fake board
            await MainActor.run { self.board = newBoard } // Update the @State property
            // Only update status if not called from move (move func sets its own status)
            return calledFromMove ? status ?? "Board updated." : "Fake board refreshed."
        }
    }

    // Helper to read a single value for debug buttons
    private func readContractValue(description: String, valueFetch: @escaping () async throws -> String) {
        guard blockchainService.currentGameAddress != nil else {
            status = "No active game for debug call."
            return
        }
        // Use the general action performer
        performBlockchainAction(loadingMessage: "Reading \(description)...") {
            let value = try await valueFetch() // Get the fake value
            return "\(description): \(value)" // Return the result for status display
        }
    }
    
    // Helper to dismiss the keyboard
    private func hideKeyboard() {
         UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// --- Preview Provider (for Xcode Canvas) ---
// This lets you see a preview of your UI in Xcode without running on a phone
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .preferredColorScheme(.dark) // Make preview dark like our theme
    }
}
