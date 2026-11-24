import FossifyCommons
import Observation
import SwiftUI
import UIKit

/// What the SwiftUI parts of the keyboard (toolbar, emoji palette, clipboard manager, dialogs) show.
@MainActor
@Observable
final class KeyboardState {
    enum Panel { case none, emoji, clipboard }

    struct ClipSection: Identifiable {
        var id: String { label ?? "clips" }
        var label: String?
        var isCurrent = false
        var clips: [Clip]
    }

    var colors = KeyboardColors.resolve(dark: false, showKeyBorders: true)
    var clipboardValue: String?
    var panel = Panel.none
    var showLanguageDialog = false
    var clipSections: [ClipSection] = []
    var emojiCategories: [(String, [EmojiData])] = []
    var showsInputModeSwitch = false
    var toast: String?

    /// topKeyboardDivider.beGoneIf(wasDarkened).
    var showsDivider: Bool { colors.background == colors.background.darkened() }
}

/// The keyboard (SimpleKeyboardIME + keyboard_view_keyboard.xml): toolbar with the clipboard content,
/// the keys, the emoji palette and the clipboard manager. Used as the `inputView` of in-app text fields
/// and as the view of the keyboard extension.
@MainActor
public final class KeyboardInputView: UIInputView, UIInputViewAudioFeedback, KeyboardActionListener {
    /// How quickly do we have to double tap shift to enable permanent caps lock.
    private static let shiftPermToggleSpeed: TimeInterval = 0.5
    private static let toolbarHeight: CGFloat = 46

    public let target: KeyboardTextTarget
    private let onOpenSettings: () -> Void
    private let onManageClipboard: () -> Void

    /// Set by the keyboard extension: settings and colors come from the app group, and the
    /// keyboard pins its own height.
    public var hostedInExtension = false {
        didSet {
            guard hostedInExtension, selfHeight == nil else { return }
            selfHeight = heightAnchor.constraint(equalToConstant: intrinsicContentSize.height)
            selfHeight?.priority = UILayoutPriority(999)
            selfHeight?.isActive = true
        }
    }
    private var selfHeight: NSLayoutConstraint?
    /// The extension shows a "next keyboard" button when iOS asks for one.
    public var showsInputModeSwitch: Bool {
        get { state.showsInputModeSwitch }
        set { state.showsInputModeSwitch = newValue }
    }
    public var onAdvanceInputMode: (() -> Void)?

    let state = KeyboardState()
    private let config = Config.shared
    private let keyboardView = MyKeyboardView()
    private var toolbarHost: UIHostingController<KeyboardToolbar>!
    private var panelsHost: UIHostingController<KeyboardPanels>!
    private let toastLabel = UILabel()
    private var keyboardHeight: NSLayoutConstraint!

    private var keyboard: MyKeyboard?
    private var keyboardMode = KeyboardMode.letters
    private var lastShiftPressTS: TimeInterval = 0
    private var switchToLetters = false
    private var enterKeyType = EnterKeyType.none
    private var isTextClass = true
    private var lastWidth: CGFloat = 0
    private var pasteboardChangeCount = -1
    private var pasteboardTimer: Timer?

    public var enableInputClicksWhenVisible: Bool { true }

    /// - Parameters:
    ///   - target: the editor to type into.
    ///   - onOpenSettings: the settings cog / tools popup / "Manage keyboard languages".
    ///   - onManageClipboard: the clipboard manager's "Manage clipboard items".
    public init(target: KeyboardTextTarget, onOpenSettings: @escaping () -> Void = {}, onManageClipboard: @escaping () -> Void = {}) {
        self.target = target
        self.onOpenSettings = onOpenSettings
        self.onManageClipboard = onManageClipboard
        super.init(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 300), inputViewStyle: .default)
        allowsSelfSizing = true
        autoresizingMask = .flexibleHeight
        setupViews()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: KeyboardInputView, _: UITraitCollection) in
            self.setupKeyboard()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        keyboardView.listener = self
        keyboardView.popupHost = self
        keyboardView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(keyboardView)

        toolbarHost = UIHostingController(rootView: KeyboardToolbar(state: state, keyboard: self))
        panelsHost = UIHostingController(rootView: KeyboardPanels(state: state, keyboard: self))
        for host in [toolbarHost.view!, panelsHost.view!] {
            host.backgroundColor = .clear
            host.translatesAutoresizingMaskIntoConstraints = false
            addSubview(host)
        }
        toolbarHost.safeAreaRegions = []
        panelsHost.safeAreaRegions = []
        panelsHost.view.isHidden = true

        toastLabel.isUserInteractionEnabled = false
        toastLabel.font = .systemFont(ofSize: 14)
        toastLabel.textColor = .white
        toastLabel.textAlignment = .center
        toastLabel.numberOfLines = 2
        toastLabel.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        toastLabel.layer.cornerRadius = 16
        toastLabel.clipsToBounds = true
        toastLabel.isHidden = true
        toastLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toastLabel)

        keyboardHeight = keyboardView.heightAnchor.constraint(equalToConstant: 240)
        let bottom = keyboardView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor)
        bottom.priority = .defaultHigh
        NSLayoutConstraint.activate([
            toolbarHost.view.topAnchor.constraint(equalTo: topAnchor),
            toolbarHost.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            toolbarHost.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            toolbarHost.view.heightAnchor.constraint(equalToConstant: KeyboardInputView.toolbarHeight),
            keyboardView.topAnchor.constraint(equalTo: toolbarHost.view.bottomAnchor),
            keyboardView.leadingAnchor.constraint(equalTo: leadingAnchor),
            keyboardView.trailingAnchor.constraint(equalTo: trailingAnchor),
            keyboardHeight, bottom,
            panelsHost.view.topAnchor.constraint(equalTo: topAnchor),
            panelsHost.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            panelsHost.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            panelsHost.view.bottomAnchor.constraint(equalTo: keyboardView.bottomAnchor),
            toastLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            toastLabel.bottomAnchor.constraint(equalTo: keyboardView.bottomAnchor, constant: -24),
            toastLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -48),
            toastLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 32),
        ])
        reloadKeyboard()
        setupKeyboard()
    }

    // MARK: lifecycle (onStartInput / onStartInputView / onVisibilityChanged)

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            startInput()
            pasteboardTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkPasteboard() }
            }
        } else {
            pasteboardTimer?.invalidate()
            pasteboardTimer = nil
            keyboardView.closing()
            state.panel = .none
            state.showLanguageDialog = false
            updatePanelsVisibility()
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width > 0 && bounds.width != lastWidth {
            lastWidth = bounds.width
            reloadKeyboard()
        }
    }

    /// onStartInput(): pick the layout for the field and re-read the settings.
    public func startInput() {
        if hostedInExtension {
            config.reload()
            config.importColors()
        } else {
            config.exportColors()
        }
        ClipsStore.shared.reload()
        state.panel = .none
        state.showLanguageDialog = false
        updatePanelsVisibility()
        switch target.keyboardType {
        case .numberPad?, .decimalPad?, .asciiCapableNumberPad?: isTextClass = false
        case .phonePad?: isTextClass = false
        case .numbersAndPunctuation?: isTextClass = false
        default: isTextClass = true
        }
        enterKeyType = EnterKeyType(target.returnKeyType)
        reloadKeyboard()
        setupKeyboard()
        updateShiftKeyState()
        pasteboardChangeCount = -1
        checkPasteboard()
    }

    /// The editor's text or selection changed (onUpdateSelection).
    public func textDidChange() {
        if (target.selectedText ?? "").isEmpty, state.panel == .clipboard {
            closeClipboardManager()
        }
        updateShiftKeyState()
    }

    /// setupKeyboard(): colors, borders, clipboard and emojis.
    func setupKeyboard() {
        let dark = traitCollection.userInterfaceStyle == .dark
        let colors = KeyboardColors.resolve(dark: dark, showKeyBorders: config.showKeyBorders)
        state.colors = colors
        keyboardView.colors = colors
        backgroundColor = UIColor(argb: colors.keyboardBackground)
        handleClipboard()
        setupStoredClips()
        setupEmojis()
    }

    private func updatePanelsVisibility() {
        panelsHost.view.isHidden = state.panel == .none && !state.showLanguageDialog
    }

    // MARK: keyboards

    private func width() -> CGFloat {
        bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width
    }

    private func constructKeyboard(_ layout: String) -> MyKeyboard {
        adjustBottomRow(MyKeyboard(layout: layout, enterKeyType: enterKeyType, width: width(), config: config))
    }

    private func createNewKeyboard() -> MyKeyboard {
        let layout: String
        switch target.keyboardType {
        case .numberPad?, .decimalPad?, .asciiCapableNumberPad?:
            keyboardMode = .numbers
            layout = "keys_numbers"
        case .phonePad?:
            keyboardMode = .phone
            layout = "keys_phone"
        case .numbersAndPunctuation?:
            keyboardMode = .symbols
            layout = "keys_symbols"
        default:
            keyboardMode = .letters
            layout = KeyboardLanguage.layout(config.keyboardLanguage)
        }
        return constructKeyboard(layout)
    }

    private func setKeyboard(_ keyboard: MyKeyboard) {
        self.keyboard = keyboard
        keyboardView.setKeyboard(keyboard)
        keyboardHeight.constant = keyboard.height
        invalidateIntrinsicContentSize()
        selfHeight?.constant = intrinsicContentSize.height
        closeClipboardManager()
    }

    public override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric,
               height: KeyboardInputView.toolbarHeight + (keyboard?.height ?? 240) + safeAreaInsets.bottom)
    }

    public override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        invalidateIntrinsicContentSize()
        selfHeight?.constant = intrinsicContentSize.height
    }

    /// reloadKeyboard().
    func reloadKeyboard() {
        setKeyboard(createNewKeyboard())
        updateShiftKeyState()
    }

    /// adjustBottomRow(): language label on the space bar, emoji / language key, tools popup.
    private func adjustBottomRow(_ keyboard: MyKeyboard) -> MyKeyboard {
        let keys = keyboard.keys
        let spaceKeyIndex = keys.firstIndex { $0.code == KeyCode.space }
        if let spaceKeyIndex, keys[spaceKeyIndex].label.isEmpty {
            keys[spaceKeyIndex].label = config.selectedLanguages.count > 1 ? KeyboardLanguage.title(config.keyboardLanguage) : ""
        }
        guard keyboardMode == .letters else { return keyboard }
        if let emojiKeyIndex = keys.firstIndex(where: { $0.code == KeyCode.emojiOrLanguage }), let spaceKeyIndex {
            let emojiKey = keys[emojiKeyIndex], spaceKey = keys[spaceKeyIndex]
            emojiKey.secondaryIcon = nil
            if config.showEmojiKey {
                // no-op
            } else if config.showLanguageSwitchKey {
                emojiKey.icon = .language
            } else {
                // both emoji and language keys are disabled
                spaceKey.width += emojiKey.width + emojiKey.gap
                spaceKey.x = emojiKey.x
                keyboard.keys.remove(at: emojiKeyIndex)
            }
        }
        // When emoji key is enabled, show settings-only popup with no hint on tools key
        if config.showEmojiKey, let toolsKey = keyboard.keys.first(where: { $0.role == keyRoleTools }) {
            toolsKey.popupLayout = "popup_tools"
            toolsKey.secondaryIcon = nil
        }
        return keyboard
    }

    private func updateShiftKeyState() {
        guard let keyboard, keyboard.shiftState != .onPermanent else { return }
        if config.enableSentencesCapitalization && target.cursorCapsMode() {
            keyboard.setShifted(.onOneChar)
        } else {
            keyboard.setShifted(.off)
        }
        keyboardView.invalidateAllKeys()
    }

    // MARK: OnKeyboardActionListener

    func onPress(_ code: Int) {
        if code != 0 {
            KeyboardFeedback.performKeypressFeedback(code)
        }
    }

    func onKey(_ code: Int) {
        guard let keyboard else { return }
        if code != KeyCode.shift { lastShiftPressTS = 0 }

        switch code {
        case KeyCode.delete:
            // deleteBackward removes the selection or the last grapheme cluster (BreakIterator)
            target.deleteBackward()
            updateShiftKeyState()

        case KeyCode.shift:
            if keyboardMode == .letters {
                let now = Date().timeIntervalSince1970
                if keyboard.shiftState == .onPermanent {
                    keyboard.shiftState = .off
                } else if now - lastShiftPressTS < KeyboardInputView.shiftPermToggleSpeed {
                    keyboard.shiftState = .onPermanent
                } else if keyboard.shiftState == .onOneChar {
                    keyboard.shiftState = .off
                } else {
                    keyboard.shiftState = .onOneChar
                }
                lastShiftPressTS = now
            } else {
                let layout: String
                if keyboardMode == .symbols {
                    keyboardMode = .symbolsShift
                    layout = "keys_symbols_shift"
                } else {
                    keyboardMode = .symbols
                    layout = "keys_symbols"
                }
                setKeyboard(constructKeyboard(layout))
            }
            keyboardView.invalidateAllKeys()

        case KeyCode.enter:
            target.performReturn()
            updateShiftKeyState()

        case KeyCode.symbolsModeChange:
            let layout: String
            if keyboardMode == .symbols || keyboardMode == .symbolsShift {
                keyboardMode = .symbolsAlt
                layout = "keys_symbols_alt"
            } else {
                keyboardMode = .symbols
                layout = "keys_symbols"
            }
            setKeyboard(constructKeyboard(layout))

        case KeyCode.modeChange:
            let layout: String
            if keyboardMode == .letters {
                keyboardMode = .symbols
                layout = "keys_symbols"
            } else {
                keyboardMode = .letters
                layout = KeyboardLanguage.layout(config.keyboardLanguage)
            }
            setKeyboard(constructKeyboard(layout))
            updateShiftKeyState()

        case KeyCode.emojiOrLanguage:
            if config.showEmojiKey {
                openEmojiPalette()
            } else if config.showLanguageSwitchKey {
                let sorted = config.selectedLanguagesSorted
                if sorted.count > 1 {
                    let currentIndex = sorted.firstIndex(of: config.keyboardLanguage) ?? -1
                    config.keyboardLanguage = sorted[(currentIndex + 1) % sorted.count]
                    reloadKeyboard()
                }
            }

        case KeyCode.popupEmoji:
            openEmojiPalette()

        case KeyCode.popupSettings:
            openSettings()

        default:
            guard code > 0, let scalar = UnicodeScalar(UInt32(code)) else { return }
            var char = String(Character(scalar))
            let originalText = target.documentContextBeforeInput

            if Character(scalar).isLetter && keyboard.shiftState > .off {
                char = config.keyboardLanguage == KeyboardLanguage.turkishQ ? char.uppercased(with: Locale(identifier: "tr")) : char.uppercased()
            }

            // If the keyboard is set to symbols and the user presses space, we usually should switch back to the letters keyboard.
            // However, avoid doing that in cases when the field for example requires numbers as the input.
            // We can detect that by the text not changing on pressing Space.
            if keyboardMode != .letters && isTextClass && code == KeyCode.space {
                target.insertText(char)
                if originalText != target.documentContextBeforeInput {
                    switchToLetters = keyboardMode != .symbolsAlt
                }
            } else if let originalText, !originalText.isEmpty, config.keyboardLanguage == KeyboardLanguage.vietnameseTelex {
                if telex(originalText, char) { return }
                target.insertText(char)
                updateShiftKeyState()
            } else {
                target.insertText(char)
                updateShiftKeyState()
            }
        }
    }

    /// Vietnamese Telex: replace the end of the current word using the composition rules.
    private func telex(_ originalText: String, _ char: String) -> Bool {
        let rules = VietnameseTelex.rules
        let fullText = originalText + char
        let lastIndexEmpty = fullText.contains(" ") ? fullText.distance(from: fullText.startIndex, to: fullText.lastIndex(of: " ")!) : 0
        let word = Array(String(fullText.dropFirst(lastIndexEmpty)).trimmingCharacters(in: .whitespaces))
        var predictWord = ""
        for i in stride(from: word.count - 1, through: 0, by: -1) {
            predictWord.append(word[i])
            predictWord = String(predictWord.reversed()) // StringBuilder.reverse() works in place
            if let replacement = rules[predictWord] {
                // setComposingRegion(len - match, len) + setComposingText(): the typed char isn't in the field yet
                for _ in 0..<(predictWord.count - 1) { target.deleteBackward() }
                target.insertText(replacement)
                return true
            }
        }
        return false
    }

    func onActionUp() {
        guard switchToLetters else { return }
        keyboardMode = .letters
        let keyboard = constructKeyboard(KeyboardLanguage.layout(config.keyboardLanguage))
        if keyboard.shiftState != .onPermanent && target.cursorCapsMode() {
            keyboard.setShifted(.onOneChar)
        }
        setKeyboard(keyboard)
        switchToLetters = false
    }

    func moveCursorLeft() { moveCursor(-1) }
    func moveCursorRight() { moveCursor(1) }

    private func moveCursor(_ offset: Int) {
        if offset < 0 && (target.documentContextBeforeInput ?? "").isEmpty { return }
        if offset > 0 && (target.documentContextAfterInput ?? "").isEmpty { return }
        target.adjustTextPosition(byCharacterOffset: offset)
        KeyboardFeedback.performHapticHandleMove()
        updateShiftKeyState()
    }

    func onText(_ text: String) {
        target.insertText(text)
    }

    func showSwitchLanguageDialog() {
        state.showLanguageDialog = true
        updatePanelsVisibility()
    }

    // MARK: toolbar, panels and dialogs

    func openEmojiPalette() {
        state.panel = .emoji
        updatePanelsVisibility()
        setupEmojis()
    }

    func closeEmojiPalette() {
        if state.panel == .emoji { state.panel = .none }
        updatePanelsVisibility()
    }

    func openClipboardManager() {
        state.panel = .clipboard
        updatePanelsVisibility()
        setupStoredClips()
    }

    func closeClipboardManager() {
        if state.panel == .clipboard { state.panel = .none }
        updatePanelsVisibility()
    }

    func dismissLanguageDialog() {
        state.showLanguageDialog = false
        updatePanelsVisibility()
    }

    func selectLanguage(_ language: Int) {
        config.keyboardLanguage = language
        dismissLanguageDialog()
        reloadKeyboard()
    }

    func openSettings() {
        KeyboardFeedback.vibrateIfNeeded()
        dismissLanguageDialog()
        onOpenSettings()
    }

    func manageClipboardItems() {
        onManageClipboard()
    }

    func advanceInputMode() {
        onAdvanceInputMode?()
    }

    func startDeleteRepeat() { keyboardView.startDeleteRepeat() }
    func stopDeleteRepeat() { keyboardView.stopDeleteRepeat() }

    func showToast(_ text: String) {
        toastLabel.text = "  \(text)  "
        toastLabel.isHidden = false
        bringSubviewToFront(toastLabel)
        let shown = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            if self?.toastLabel.text == "  \(shown)  " { self?.toastLabel.isHidden = true }
        }
    }

    func emojiPicked(_ emoji: EmojiData) {
        onText(emoji.emoji)
        KeyboardFeedback.vibrateIfNeeded()
        config.addRecentEmoji(emoji.emoji)
        setupEmojis()
    }

    private func setupEmojis() {
        let recent = config.recentlyUsedEmojis
        Task.detached(priority: .userInitiated) { [weak self] in
            let categories = Emojis.categories(recent: recent)
            await MainActor.run { self?.state.emojiCategories = categories }
        }
    }

    // MARK: clipboard

    private func checkPasteboard() {
        let count = UIPasteboard.general.changeCount
        guard count != pasteboardChangeCount else { return }
        pasteboardChangeCount = count
        handleClipboard()
        setupStoredClips()
    }

    /// handleClipboard(): show the current clip on the toolbar.
    private func handleClipboard() {
        let clip = config.showClipboardContent ? currentClip() : nil
        withAnimation(.easeIn(duration: 0.15)) {
            state.clipboardValue = clip?.isEmpty == false ? clip : nil
        }
    }

    func clearClipboardContent() {
        KeyboardFeedback.vibrateIfNeeded()
        UIPasteboard.general.items = []
        pasteboardChangeCount = UIPasteboard.general.changeCount
        withAnimation(.easeIn(duration: 0.15)) { state.clipboardValue = nil }
        setupStoredClips()
    }

    /// setupStoredClips(): the current clip (unless pinned) and the pinned ones.
    func setupStoredClips() {
        let content = currentClip()
        let pinned = ClipsStore.shared.clips
        let currentPinnedToo = pinned.contains { content?.isEmpty == false && $0.value.trimmingCharacters(in: .whitespacesAndNewlines) == content }
        var sections: [KeyboardState.ClipSection] = []
        if !currentPinnedToo, let content, !content.isEmpty {
            sections.append(.init(label: "Current", isCurrent: true, clips: [Clip(id: -1, value: content)]))
            sections.append(.init(label: "Pinned", clips: pinned))
        } else if !pinned.isEmpty {
            sections.append(.init(label: nil, clips: pinned))
        }
        state.clipSections = sections
    }

    func pinCurrentClip() {
        guard let clip = currentClip() else { return }
        ClipsStore.shared.insertClip(clip)
        setupStoredClips()
        showToast("Text has been pinned")
        KeyboardFeedback.vibrateIfNeeded()
    }
}
