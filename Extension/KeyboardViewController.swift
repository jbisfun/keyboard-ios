import KeyboardKit
import UIKit

/// The system keyboard extension (SimpleKeyboardIME): KeyboardKit's keyboard typing into the host app.
@objc(KeyboardViewController)
final class KeyboardViewController: UIInputViewController {
    private var keyboardView: KeyboardInputView?

    override func viewDidLoad() {
        super.viewDidLoad()
        let keyboard = KeyboardInputView(
            target: DocumentProxyTarget(proxy: textDocumentProxy),
            onOpenSettings: { [weak self] in self.map { openContainingApp("settings", from: $0) } },
            onManageClipboard: { [weak self] in self.map { openContainingApp("clipboard", from: $0) } })
        keyboard.hostedInExtension = true
        keyboard.onAdvanceInputMode = { [weak self] in self?.advanceToNextInputMode() }
        keyboardView = keyboard
        inputView = keyboard
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        keyboardView?.showsInputModeSwitch = needsInputModeSwitchKey
        keyboardView?.startInput()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        keyboardView?.textDidChange()
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        keyboardView?.textDidChange()
    }
}
