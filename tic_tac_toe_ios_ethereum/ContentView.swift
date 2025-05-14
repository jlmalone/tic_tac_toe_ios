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

    @State private var status: String      = "App loaded."
    @State private var board:  [[String]]? = nil
    @State private var currentPlayer      = 0
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
                    } else if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .matrixGreen))
                    }

                    Text(status)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundColor(status.lowercased().contains("error")
                                         ? .matrixError
                                         : .matrixGreen)
                        .frame(minHeight: 40)

                    debugControls().padding(.top)
                    diagnosticControls().padding(.top) // <-- ADD THIS
                }
                .padding()
            }
            .background(Color.matrixBlack.ignoresSafeArea())
            .navigationBarHidden(true)
            .preferredColorScheme(.dark)
            // react to service changes
            .onChange(of: service.currentGameAddress) { addr in
                gameAddressInput = addr ?? ""
                if addr != nil { refreshBoard() } else { board = nil }
            }
            .onChange(of: service.factoryAddress) { f in
                status = f == nil ? "Factory cleared." : "Factory: \(short(f))"
            }
        }
    }
    
    // For example, add it to your networkControls or create a new small section
    private func diagnosticControls() -> some View { // New function
        VStack {
            Button("Test Blockchain Connection") {
                Task {
                    isLoading = true // Optional: show loading indicator
                    status = "Checking blockchain connection..."
                    status = await service.checkBlockchainConnection()
                    isLoading = false // Optional: hide loading indicator
                }
            }
            .stylePrimary() // Or .styleSecondary()
        }
    }

    // ---------------------------------------------------------------------
    // MARK: - Section builders
    // ---------------------------------------------------------------------
    private func networkControls() -> some View {
        HStack {
            Button {
                service.useLocal.toggle()
                board = nil
                status = "Switched to \(service.useLocal ? "LOCAL" : "SEPOLIA")."
            } label: {
                Text(service.useLocal ? "LOCAL ✔" : "SEPOLIA ✔")
            }
            .stylePrimary()

            Button {
                service.printDerivedAddresses()
                status = "Addresses printed to console."
            } label: { Text("Print Addrs") }
            .styleSecondary()
        }
    }

    private func factoryControls() -> some View {
        VStack(spacing: 8) {
            Text("Factory: \(short(service.factoryAddress))")
                .foregroundColor(.matrixGreen.opacity(0.8))
                .font(.footnote)

            Button {
                runAction("Creating game…") {
                    let addr = try await service.createGame(by: 0)
                    return "Game created: \(short(addr))"
                }
            } label: { Text("Create Game (P1)") }
            .stylePrimary()
            .disabled(service.factoryAddress == nil || isLoading)

            HStack {
                TextField("Game Address", text: $gameAddressInput)
                    .textFieldStyle(MatrixTextFieldStyle())
                    .autocapitalization(.none)

                Button {
                    guard gameAddressInput.hasPrefix("0x"),
                          gameAddressInput.count > 10 else {
                        status = "Invalid address."
                        return
                    }
                    service.currentGameAddress = gameAddressInput
                    status = "Joined game \(short(gameAddressInput))"
                    refreshBoard()
                } label: { Text("Join") }
                .styleSecondary()
                .disabled(gameAddressInput.isEmpty)
            }
        }
    }

    private func moveControls() -> some View {
        VStack(spacing: 10) {

            Text("Game: \(short(service.currentGameAddress))")
                .foregroundColor(.matrixGreen.opacity(0.8))
                .font(.footnote)

            Button {
                currentPlayer = (currentPlayer + 1) % 2
            } label: {
                let addr = currentPlayer == 0 ? service.player1 : service.player2
                Text("Signer: P\(currentPlayer + 1) (\(short(addr)))")
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
                    guard let r = Int(rowInput),
                          let c = Int(colInput),
                          (0...2).contains(r), (0...2).contains(c) else {
                        status = "Row/Col must be 0-2." ; return
                    }
                    runAction("Submitting…") {
                        try await service.makeMove(by: currentPlayer,
                                                   row: UInt8(r), col: UInt8(c))
                        await refreshBoard()
                        if try await service.readBool(fnName: "gameEnded") {
                            let win = try await service
                                .readAddress(fnName: "winner")
                                .lowercased()
                            if win == ZERO_ADDRESS.lowercased() { return "Draw!" }
                            if win == service.player1.lowercased() { return "Player 1 wins!" }
                            if win == service.player2.lowercased() { return "Player 2 wins!" }
                            return "Winner: \(short(win))"
                        }
                        return "Move OK."
                    }
                } label: { Text("Make Move") }
                .stylePrimary()
                .disabled(isLoading)
            }
        }
    }

    @ViewBuilder
    private func boardView() -> some View {
        if let b = board {
            VStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { r in
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { c in
                            Text(service.emojiForAddress(b[r][c]))
                                .font(.system(size: 30))
                                .frame(width: 60, height: 60)
                                .border(Color.matrixGreen.opacity(0.7))
                        }
                    }
                }
            }
        } else if isLoading {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .matrixGreen))
        } else {
            Text("Board not loaded.")
                .foregroundColor(.matrixGreen.opacity(0.7))
        }
    }


    private func debugControls() -> some View {
        VStack(spacing: 6) {
            Text("Debug").foregroundColor(.matrixGreen)

            HStack {
                Button("Refresh") {
                    refreshBoard()
                }
                .buttonStyle(MatrixSecondaryButtonStyle())

                Button("gameEnded") {
                    readValue("gameEnded") {
                        try await service.readBool(fnName: "gameEnded").description
                    }
                }
                .buttonStyle(MatrixSecondaryButtonStyle())
            }
        }
    }

    // ---------------------------------------------------------------------
    // MARK: - Helper routines
    // ---------------------------------------------------------------------
    private func runAction(_ message: String,
                           work: @escaping () async throws -> String) {
        guard !isLoading else { return }
        isLoading = true
        status = message
        Task { @MainActor in
            defer { isLoading = false }
            do   { status = try await work() }
            catch { status = "Error: \((error as NSError).localizedDescription)" }
        }
    }

    private func refreshBoard() {
        runAction("Loading board…") {
            board = try await service.board()
            return "Board refreshed."
        }
    }

    private func readValue(_ label: String,
                           get: @escaping () async throws -> String) {
        runAction("Reading \(label)…") { "\(label): \(try await get())" }
    }

    private func short(_ addr: String?) -> String {
        guard let a = addr, a.count > 10 else { return addr ?? "—" }
        return "\(a.prefix(6))…\(a.suffix(4))"
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Quick style stubs so file compiles even if custom types absent
// ─────────────────────────────────────────────────────────────────────────────
#if canImport(UIKit)
private extension Button {
    func stylePrimary() -> some View  { self.buttonStyle(MatrixButtonStyle()) }
    func styleSecondary() -> some View{ self.buttonStyle(MatrixSecondaryButtonStyle()) }
}
#else
private extension Button {
    func stylePrimary()  -> some View { self }
    func styleSecondary() -> some View { self }
}
#endif

// ─────────────────────────────────────────────────────────────────────────────
struct ContentView_Previews: PreviewProvider {
    static var previews: some View { ContentView().preferredColorScheme(.dark) }
}
