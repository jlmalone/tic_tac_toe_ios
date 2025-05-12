import SwiftUI

// Define our special Matrix colors
extension Color {
    static let matrixGreen = Color(red: 0, green: 1, blue: 0) // 00FF00
    static let matrixBlack = Color(red: 0, green: 0, blue: 0) // 000000
    static let matrixError = Color(red: 0.81, green: 0.4, blue: 0.47) // Like #CF6679
}

// --- Styles for UI elements ---

// How our text input boxes should look
struct MatrixTextFieldStyle: TextFieldStyle {
    @FocusState private var isFocused: Bool // Track if the text field is being typed into

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(10)
            .foregroundColor(.matrixGreen) // Text color
            .background(Color.matrixBlack) // Background inside the box
            .accentColor(.matrixGreen)     // Cursor color
            .focused($isFocused)           // Connect focus tracking
            .overlay( // The border around the box
                RoundedRectangle(cornerRadius: 5)
                    // Make border brighter green when typing, dimmer otherwise
                    .stroke(isFocused ? Color.matrixGreen : Color.matrixGreen.opacity(0.5), lineWidth: 1)
            )
            .onAppear {
                 // Fix for keyboard dismissal if needed, might not be necessary
                 // UIApplication.shared.addTapGestureRecognizer()
            }
    }
}

// How our main green buttons should look
struct MatrixButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            // Make button slightly dimmer green when pressed
            .background(configuration.isPressed ? Color.matrixGreen.opacity(0.7) : Color.matrixGreen)
            .foregroundColor(.matrixBlack) // Text color on the button
            .cornerRadius(5)
            .font(.system(size: 14, weight: .medium))
    }
}

// How our secondary buttons (like "Print Addrs") should look (green border, green text)
struct MatrixSecondaryButtonStyle: ButtonStyle {
     func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            // Make text slightly dimmer green when pressed
            .foregroundColor(configuration.isPressed ? Color.matrixGreen.opacity(0.7) : Color.matrixGreen)
            .background(Color.matrixBlack) // Background behind the text
            .overlay( // The border
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.matrixGreen.opacity(0.7), lineWidth: 1)
            )
             .font(.system(size: 14, weight: .medium))
    }
}

// Helper to dismiss keyboard when tapping outside text fields (add if needed)
/*
extension UIApplication {
    func addTapGestureRecognizer() {
        guard let window = connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first else { return }
        let tapGesture = UITapGestureRecognizer(target: window, action: #selector(UIView.endEditing))
        tapGesture.requiresExclusiveTouchType = false
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self // Requires conforming to UIGestureRecognizerDelegate
        window.addGestureRecognizer(tapGesture)
    }
}

extension UIApplication: UIGestureRecognizerDelegate {
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false // set to true if you want scroll views to work while keyboard is up
    }
}
*/
