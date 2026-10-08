import SwiftUI
import UIKit

/// A text field that never brings up the system keyboard — same trick the
/// stock Phone app's dial field uses. Digits come from the on-screen dial
/// pad; the system's own Paste/Select menu still works via long-press since
/// that's driven by UITextField's edit-menu, not by inputView.
struct NoKeyboardTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""

    func makeUIView(context: Context) -> UITextField {
        let field = InputlessTextField()
        field.font = .ink(28, bold: true)
        field.textColor = Ink.inkUI
        field.tintColor = Ink.inkUI
        field.adjustsFontSizeToFitWidth = true
        field.minimumFontSize = 16
        field.textAlignment = .center
        field.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [
            .foregroundColor: Ink.inkUI.withAlphaComponent(0.42),
            .font: UIFont.ink(18)
        ])
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        @objc func textChanged(_ sender: UITextField) {
            // Pasted numbers often carry formatting spaces/dashes (e.g. "+371 2
            // 2105594") that make an invalid SIP URI and silently kill the call.
            let sanitized = (sender.text ?? "").dialSanitized
            if sender.text != sanitized {
                sender.text = sanitized
            }
            text.wrappedValue = sanitized
        }
    }
}

extension String {
    var dialSanitized: String {
        filter { $0.isNumber || $0 == "+" || $0 == "*" || $0 == "#" }
    }
}

private final class InputlessTextField: UITextField {
    override var inputView: UIView? {
        get { UIView(frame: .zero) }
        set {}
    }
    override var inputAccessoryView: UIView? {
        get { nil }
        set {}
    }
}
