import UIKit

/// The editor the keyboard types into (Android's InputConnection + EditorInfo): the extension's
/// UITextDocumentProxy, or an in-app text field / text view.
@MainActor
public protocol KeyboardTextTarget: AnyObject {
    var documentContextBeforeInput: String? { get }
    var documentContextAfterInput: String? { get }
    var selectedText: String? { get }
    var keyboardType: UIKeyboardType? { get }
    var returnKeyType: UIReturnKeyType? { get }
    var autocapitalizationType: UITextAutocapitalizationType? { get }
    func insertText(_ text: String)
    func deleteBackward()
    func adjustTextPosition(byCharacterOffset offset: Int)
    /// KEYCODE_ENTER / performEditorAction().
    func performReturn()
}

/// UIInputViewController.textDocumentProxy as a target.
@MainActor
public final class DocumentProxyTarget: KeyboardTextTarget {
    private let proxy: UITextDocumentProxy

    public init(proxy: UITextDocumentProxy) {
        self.proxy = proxy
    }

    public var documentContextBeforeInput: String? { proxy.documentContextBeforeInput }
    public var documentContextAfterInput: String? { proxy.documentContextAfterInput }
    public var selectedText: String? { proxy.selectedText }
    public var keyboardType: UIKeyboardType? { proxy.keyboardType }
    public var returnKeyType: UIReturnKeyType? { proxy.returnKeyType }
    public var autocapitalizationType: UITextAutocapitalizationType? { proxy.autocapitalizationType }
    public func insertText(_ text: String) { proxy.insertText(text) }
    public func deleteBackward() { proxy.deleteBackward() }
    public func adjustTextPosition(byCharacterOffset offset: Int) { proxy.adjustTextPosition(byCharacterOffset: offset) }
    public func performReturn() { proxy.insertText("\n") }
}

/// An in-app UITextField / UITextView as a target.
@MainActor
public final class TextInputTarget: KeyboardTextTarget {
    private weak var view: (UIView & UITextInput)?

    public init(_ view: UIView & UITextInput) {
        self.view = view
    }

    private func text(from start: UITextPosition?, to end: UITextPosition?) -> String? {
        guard let view, let start, let end, let range = view.textRange(from: start, to: end) else { return nil }
        return view.text(in: range)
    }

    public var documentContextBeforeInput: String? {
        text(from: view?.beginningOfDocument, to: view?.selectedTextRange?.start)
    }

    public var documentContextAfterInput: String? {
        text(from: view?.selectedTextRange?.end, to: view?.endOfDocument)
    }

    public var selectedText: String? {
        guard let range = view?.selectedTextRange, !range.isEmpty else { return nil }
        return view?.text(in: range)
    }

    public var keyboardType: UIKeyboardType? { (view as? UITextField)?.keyboardType ?? (view as? UITextView)?.keyboardType }
    public var returnKeyType: UIReturnKeyType? { (view as? UITextField)?.returnKeyType ?? (view as? UITextView)?.returnKeyType }
    public var autocapitalizationType: UITextAutocapitalizationType? {
        (view as? UITextField)?.autocapitalizationType ?? (view as? UITextView)?.autocapitalizationType
    }

    public func insertText(_ text: String) { view?.insertText(text) }
    public func deleteBackward() { view?.deleteBackward() }

    public func adjustTextPosition(byCharacterOffset offset: Int) {
        guard let view, let range = view.selectedTextRange,
              let position = view.position(from: offset < 0 ? range.start : range.end, offset: offset) else { return }
        view.selectedTextRange = view.textRange(from: position, to: position)
    }

    public func performReturn() {
        if let field = view as? UITextField {
            if field.delegate?.textFieldShouldReturn?(field) ?? true {
                field.sendActions(for: .editingDidEndOnExit)
            }
        } else {
            view?.insertText("\n")
        }
    }
}

extension KeyboardTextTarget {
    /// InputConnection.getCursorCapsMode() (TextUtils.getCapsMode) for the field's capitalization.
    func cursorCapsMode() -> Bool {
        guard let type = autocapitalizationType else { return false }
        let text = Array(documentContextBeforeInput ?? "")
        func isOpening(_ c: Character) -> Bool {
            c == "\"" || c == "'" || c.unicodeScalars.first?.properties.generalCategory == .openPunctuation
        }
        func isClosing(_ c: Character) -> Bool {
            c == "\"" || c == "'" || c.unicodeScalars.first?.properties.generalCategory == .closePunctuation
        }
        switch type {
        case .none: return false
        case .allCharacters: return true
        default: break
        }
        // Back over allowed opening punctuation.
        var i = text.count
        while i > 0 && isOpening(text[i - 1]) { i -= 1 }
        // Start of paragraph, with optional whitespace.
        var j = i
        while j > 0 && (text[j - 1] == " " || text[j - 1] == "\t") { j -= 1 }
        if j == 0 || text[j - 1] == "\n" { return true }
        if type == .words { return i != j }
        // There must be a space if not the start of paragraph.
        if i == j { return false }
        // Back over allowed closing punctuation.
        while j > 0 && isClosing(text[j - 1]) { j -= 1 }
        if j > 0 {
            let c = text[j - 1]
            if c == "." || c == "?" || c == "!" {
                // Do not capitalize if the word ends with a period but also contains a period (an abbreviation).
                if c == "." {
                    var k = j - 2
                    while k >= 0 {
                        if text[k] == "." { return false }
                        if !text[k].isLetter { break }
                        k -= 1
                    }
                }
                return true
            }
        }
        return false
    }
}
