//
//  ContentView.swift
//  tic_tac_toe_ios_ethereum
//
//  Created by Agent Malone on 5/13/25.
//

import SwiftUI

struct ContentView: View {

    // ---------------------------------------------------------------------
    // MARK: - State
    // ---------------------------------------------------------------------
    @StateObject private var service = BlockchainService()         // backend

    @State private var status: String      = "App loaded. Select network and create/join game." // More informative initial status
    @State private var board:  [[String]]? = nil
    @State private var currentPlayerIdx   = 0 // Renamed for clarity from currentPlayer
    @State private var rowInput           = "0"
    @State private var colInput           = "0"
    @State private var gameAddressInput   = ""
    @State private var isLoading          = false

    // ---------------------------------------------------------------------
    // MARK: - Body
    // ---------------------------------------------------------------------
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 14) {

                    Text("Tic-Tac-Toe Matrix")
                        .font(.largeTitle.bold())
                        .foregroundColor(.matrixGreen)

                    networkControls()
                    factoryControls()

                    if service.currentGameAddress != nil {
                        moveControls()
                        boardView().padding(.top)
                    } else if isLoading && status.contains("Creating game") { // Show progress only for specific loading actions if needed
                        ProgressView("Creating Game...")
                            .progressViewStyle(CircularProgressViewStyle(tint: .matrixGreen))
                            .foregroundColor(.matrixGreen)
                    }

                    // Status Text Area
                    Text(status)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundColor(status.lowercased().contains("error") || status.lowercased().contains("failed")
                                         ? .matrixError
                                         : .matrixGreen)
                        .frame(minHeight: 40)
                        .padding(.horizontal) // Ensure text doesn't touch edges

                    debugControls().padding(.top)
                    diagnosticControls().padding(.top) // Kept for now
                }
                .padding()
            }
            .background(Color.matrixBlack.ignoresSafeArea())
            .navigationBarHidden(true)
            .preferredColorScheme(.dark)
            // React to service changes
            .onChange(of: service.currentGameAddress) { newGameAddress in
                print("DEBUG: ContentView - currentGameAddress changed to: \(newGameAddress ?? "nil")")
                gameAddressInput = newGameAddress ?? "" // Update text field when service's game address changes
                if newGameAddress != nil {
                    refreshBoard() // Refresh board when a new game address is set
                } else {
                    self.board = nil // Clear board if game address becomes nil
                    // Optionally set status here if needed, e.g., "Left game."
                }
            }
            .onChange(of: service.factoryAddress) { newFactoryAddress in
                let factoryStatus = newFactoryAddress == nil ? "Factory cleared." : "Factory: \(short(newFactoryAddress))"
                print("DEBUG: ContentView - factoryAddress changed. UI status: \(factoryStatus)")
                // Don't overwrite main status if it's showing an error or important message
                if !status.lowercased().contains("error") && !status.lowercased().contains("failed") {
                     // status = factoryStatus // Decided to let user actions primarily set status
                }
            }
            .onAppear { // Refresh board if there's already a game address when view appears
                if service.currentGameAddress != nil {
                    refreshBoard()
                }
            }
        }
    }

    // ---------------------------------------------------------------------
    // MARK: - Section builders
    // ---------------------------------------------------------------------
    @ViewBuilder
    private func networkControls() -> some View {
        HStack {
            Button {
                service.useLocal.toggle() // This triggers reset() in service, which should clear factory/game
                board = nil // Clear board immediately on network switch
                status = "Switched to \(service.useLocal ? "LOCAL" : "SEPOLIA"). Factory/Game reset."
                // service.reset() in useLocal.didSet will set new factoryAddress,
                // which will trigger its onChange and then buildFactory.
                // If service.currentGameAddress becomes nil, its onChange will clear board.
            } label: {
                // Show current network, make it clear it's a toggle
                let networkName = service.useLocal ? "LOCAL (Tap to switch to SEPOLIA)" : "SEPOLIA (Tap to switch to LOCAL)"
                Text(service.useLocal ? "LOCAL ✔" : "SEPOLIA ✔")
                    .frame(minWidth: 100) // Give button some width
            }
            .stylePrimary()

            Button {
                service.printDerivedAddresses()
                status = "Addresses printed to console."
            } label: { Text("Print Addrs") }
            .styleSecondary()
        }
    }

    @ViewBuilder
    private func factoryControls() -> some View {
        VStack(spacing: 8) {
            Text("Factory: \(short(service.factoryAddress))")
                .foregroundColor(.matrixGreen.opacity(0.8))
                .font(.footnote)

            Button {
                // Clear previous board and game address before creating a new one
                self.board = nil
                // service.currentGameAddress = nil // Let createGame handle setting new address
                
                runAction("Creating game on \(service.useLocal ? "Local" : "Sepolia")...") { // Initial status
                    let newGameAddress = try await service.createGame(by: 0)
                    // service.currentGameAddress will be set by the service, triggering onChange
                    return "SUCCESS: Game created! Address: \(short(newGameAddress))" // Explicit success message
                }
            } label: { Text("Create Game (P1)") }
            .stylePrimary()
            .disabled(service.factoryAddress == nil || isLoading)

            HStack {
                TextField("Game Address", text: $gameAddressInput)
                    .textFieldStyle(MatrixTextFieldStyle())
                    .autocapitalization(.none)
                    .onSubmit { // Allow submitting via keyboard return key
                        joinGameAction()
                    }


                Button {
                   joinGameAction()
                } label: { Text("Join") }
                .styleSecondary()
                .disabled(gameAddressInput.isEmpty || isLoading)
            }
        }
    }
    
    private func joinGameAction() {
        guard !isLoading else { return }
        let trimmedAddress = gameAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty else {
            status = "Error: Game address cannot be empty."
            return
        }
        guard trimmedAddress.hasPrefix("0x") && trimmedAddress.count == 42 else { // Basic validation
            status = "Error: Invalid game address format."
            return
        }
        
        isLoading = true
        status = "Joining game \(short(trimmedAddress))..."
        service.currentGameAddress = trimmedAddress // This will trigger onChange which calls refreshBoard
        // We expect refreshBoard to update the status upon completion or error
        // To prevent race conditions with status, let refreshBoard's runAction handle final status
        // For now, we can just let it load. If refreshBoard succeeds, its status will be set.
        // If it fails, its error will be set.
        // If we want an immediate "Joined" message before board loads:
        // status = "Joined game \(short(trimmedAddress)). Loading board..."
        // Then refreshBoard() will update it again.
        // The onChange for service.currentGameAddress already calls refreshBoard.
        // Defer isLoading = false to the refreshBoard's runAction
    }


    @ViewBuilder
    private func moveControls() -> some View {
        VStack(spacing: 10) {
            Text("Game: \(short(service.currentGameAddress))")
                .foregroundColor(.matrixGreen.opacity(0.8))
                .font(.footnote)

            Button {
                currentPlayerIdx = (currentPlayerIdx + 1) % 2 // Assuming 2 players
            } label: {
                let addr = currentPlayerIdx == 0 ? service.player1 : service.player2
                Text("Signer: P\(currentPlayerIdx + 1) (\(short(addr)))")
            }
            .styleSecondary()

            HStack {
                TextField("Row", text: $rowInput)
                    .textFieldStyle(MatrixTextFieldStyle())
                    .frame(width: 60)
                    .keyboardType(.numberPad)

                TextField("Col", text: $colInput)
                    .textFieldStyle(MatrixTextFieldStyle())
                    .frame(width: 60)
                    .keyboardType(.numberPad)

                Spacer()

                Button {
                    guard let r = UInt8(rowInput), let c = UInt8(colInput),
                          (0...2).contains(r), (0...2).contains(c) else {
                        status = "Error: Row/Col must be 0-2." ; return
                    }
                    runAction("Submitting move (P\(currentPlayerIdx+1): \(r),\(c))...") {
                        try await service.makeMove(by: currentPlayerIdx, row: r, col: c)
                        // After move, refresh board to show new state
                        let fetchedBoard = try await service.board() // Get board directly
                        self.board = fetchedBoard                   // Update local board state
                        
                        // Check game status after move
                        if try await service.readBool(fnName: "gameEnded") {
                            let winnerHex = try await service.readAddress(fnName: "winner")
                            if winnerHex.lowercased() == ZERO_ADDRESS.lowercased() {
                                return "GAME OVER: It's a Draw!"
                            } else if winnerHex.lowercased() == service.player1.lowercased() {
                                return "GAME OVER: Player 1 (\(short(service.player1))) WINS!"
                            } else if winnerHex.lowercased() == service.player2.lowercased() {
                                return "GAME OVER: Player 2 (\(short(service.player2))) WINS!"
                            } else {
                                return "GAME OVER: Winner is \(short(winnerHex))!"
                            }
                        }
                        return "Move (P\(currentPlayerIdx+1): \(r),\(c)) successful. Board updated."
                    }
                } label: { Text("Make Move") }
                .stylePrimary()
                .disabled(service.currentGameAddress == nil || isLoading)
            }
        }
    }

    @ViewBuilder
    private func boardView() -> some View {
        // Show loading indicator specifically for board loading if isLoading and board is nil
        if isLoading && status.contains("Loading board") && board == nil {
            ProgressView("Loading Board...")
                .progressViewStyle(CircularProgressViewStyle(tint: .matrixGreen))
                .foregroundColor(.matrixGreen)
        } else if let currentBoard = board { // Use a different name to avoid ambiguity
            VStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { r in
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { c in
                            Text(service.emojiForAddress(currentBoard[r][c]))
                                .font(.system(size: 30))
                                .frame(width: 60, height: 60)
                                .border(Color.matrixGreen.opacity(0.7))
                        }
                    }
                }
            }
        } else { // Board is nil, and not currently loading (or initial state)
            Text(service.currentGameAddress != nil ? "Board not loaded yet. Try Refresh." : "No game joined.")
                .foregroundColor(.matrixGreen.opacity(0.7))
                .padding()
        }
    }

    @ViewBuilder
    private func debugControls() -> some View {
        VStack(spacing: 6) {
            Text("Debug").foregroundColor(.matrixGreen)
            HStack {
                Button("🔄 Refresh Board") { // Changed label for clarity
                    refreshBoard()
                }
                .buttonStyle(MatrixSecondaryButtonStyle())
                .disabled(service.currentGameAddress == nil || isLoading)

                Button("gameEnded?") { // Changed label for clarity
                    guard service.currentGameAddress != nil else {
                        status = "No game joined to check status."; return
                    }
                    readValue("gameEnded") {
                        try await service.readBool(fnName: "gameEnded").description
                    }
                }
                .buttonStyle(MatrixSecondaryButtonStyle())
                .disabled(service.currentGameAddress == nil || isLoading)
            }
        }
    }

    @ViewBuilder
    private func diagnosticControls() -> some View { // Kept for now
        VStack {
            Button("Test Blockchain Connection") {
                Task {
                    // isLoading = true // This action sets its own isLoading
                    // status = "Checking blockchain connection..."
                    runAction("Checking blockchain connection...") { // Use runAction
                        // The work closure for runAction needs to return a String for status
                        let connectionStatus = await service.checkBlockchainConnection()
                        return connectionStatus // This string will be set as the UI status
                    }
                }
            }
            .styleSecondary() // Use secondary style for less emphasis
        }
    }

    // ---------------------------------------------------------------------
    // MARK: - Helper routines
    // ---------------------------------------------------------------------
    private func runAction(_ message: String,
                           work: @escaping () async throws -> String) {
        guard !isLoading else {
            print("DEBUG: runAction - Action '\(message)' skipped, already loading.")
            return
        }
        print("DEBUG: runAction - Starting action: '\(message)'")
        isLoading = true
        status = message // Set initial status message for the action
        Task { @MainActor in
            var finalStatus: String
            do {
                finalStatus = try await work() // work() returns the success message
                print("DEBUG: runAction - Action '\(message)' SUCCEEDED. Final status: '\(finalStatus)'")
            } catch let NError as NSError { // Catch NSError to access localizedDescription
                finalStatus = "Error (\(message.prefix(20))...): \(NError.localizedDescription)"
                print("DEBUG: runAction - Action '\(message)' FAILED. Error: \(NError.localizedDescription). Details: \(NError)")
            } catch { // Catch any other Swift error
                finalStatus = "Error (\(message.prefix(20))...): \(error)"
                print("DEBUG: runAction - Action '\(message)' FAILED. Generic Error: \(error)")
            }
            status = finalStatus
            isLoading = false
            print("DEBUG: runAction - Finished action: '\(message)'. isLoading set to false.")
        }
    }

    private func refreshBoard() {
        guard service.currentGameAddress != nil else {
            print("DEBUG: ContentView.refreshBoard - Skipped: currentGameAddress is nil.")
            self.board = nil // Ensure board is cleared
            // Do not set status here to avoid conflict if another action is in progress
            return
        }
        let gameAddrForLog = service.currentGameAddress ?? "nil_refresh_attempt" // Should not be nil due to guard
        print("DEBUG: ContentView.refreshBoard - Initiating for game: \(short(gameAddrForLog))")
        
        // Use runAction to handle loading state and status updates for board refresh
        runAction("Loading board for \(short(gameAddrForLog))...") {
            let fetchedBoard = try await service.board()
            self.board = fetchedBoard // Update the @State variable for the board
            return "Board refreshed for \(short(gameAddrForLog))."
        }
    }


    private func readValue(_ label: String,
                           get: @escaping () async throws -> String) {
        guard !isLoading else { return } // Prevent overlapping actions
        runAction("Reading \(label)…") {
            let valueRead = try await get()
            return "\(label): \(valueRead)" // This becomes the status
        }
    }

    private func short(_ addr: String?) -> String {
        guard let a = addr, a.count > 10 else { return addr ?? "—" }
        return "\(a.prefix(6))…\(a.suffix(4))"
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Quick style stubs so file compiles even if custom types absent
// (Assuming MatrixButtonStyle and MatrixSecondaryButtonStyle are defined elsewhere, e.g., Theme.swift)
// ─────────────────────────────────────────────────────────────────────────────
#if canImport(UIKit) // Or canImport(AppKit) for macOS
private extension Button {
    func stylePrimary() -> some View  { self.buttonStyle(MatrixButtonStyle()) }
    func styleSecondary() -> some View{ self.buttonStyle(MatrixSecondaryButtonStyle()) }
}
#else // Fallback for previews or other platforms
private extension Button {
    func stylePrimary()  -> some View { self.padding() } // Basic style for previews
    func styleSecondary() -> some View { self.padding() } // Basic style for previews
}
#endif

// ─────────────────────────────────────────────────────────────────────────────
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView().preferredColorScheme(.dark)
    }
}
