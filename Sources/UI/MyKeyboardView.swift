import FossifyCommons
import UIKit

/// What MyKeyboardView reports (OnKeyboardActionListener + the dialogs it opens).
@MainActor
protocol KeyboardActionListener: AnyObject {
    func onPress(_ code: Int)
    func onKey(_ code: Int)
    func onActionUp()
    func moveCursorLeft()
    func moveCursorRight()
    func onText(_ text: String)
    /// SwitchLanguageDialog.
    func showSwitchLanguageDialog()
    func openEmojiPalette()
}

/// The keyboard colors (getKeyboardBackgroundColor, getStrokeColor, getKeyColor, ...).
struct KeyboardColors: Equatable {
    var text: UInt32
    var background: UInt32
    var keyboardBackground: UInt32
    var primary: UInt32
    var stroke: UInt32
    var keyColor: UInt32
    var keyColorPressed: UInt32
    var showKeyBorders: Bool

    static func resolve(dark: Bool, showKeyBorders: Bool) -> KeyboardColors {
        let palette = Palette.resolve(BaseConfig.shared, scheme: dark ? .dark : .light)
        let background = palette.background
        // getProperPrimaryColor()
        var primary = palette.primary
        if primary.isWhite && background.isWhite { primary = 0xFF2D2D2D } else if primary.isBlack && background.isBlack { primary = 0xFFFFFFFF }
        // getKeyboardBackgroundColor(): use darker background color when key borders are enabled
        var keyboardBackground = background.darkened(by: 2)
        if showKeyBorders {
            let darker = keyboardBackground.darkened(by: 2)
            keyboardBackground = darker == 0xFFFFFFFF ? 0xFFEEEEEE : darker
        }
        // getStrokeColor()
        let lighter = background.lightened()
        let stroke: UInt32 = lighter == 0xFFFFFFFF || lighter == 0xFF000000 ? 0x55808080 : lighter
        // getKeyColor()
        let keyColor = keyboardBackground == 0xFF000000 ? keyboardBackground.contrastARGB.alphaAdjusted(0.1) : keyboardBackground.lightened()
        return KeyboardColors(text: palette.text, background: background, keyboardBackground: keyboardBackground, primary: primary,
                              stroke: stroke, keyColor: keyColor, keyColorPressed: keyColor.alphaAdjusted(0.2),
                              showKeyBorders: showKeyBorders)
    }
}

extension UIColor {
    convenience init(argb: UInt32) {
        self.init(red: CGFloat((argb >> 16) & 0xFF) / 255, green: CGFloat((argb >> 8) & 0xFF) / 255,
                  blue: CGFloat(argb & 0xFF) / 255, alpha: CGFloat((argb >> 24) & 0xFF) / 255)
    }
}

/// minikeyboard_background: the key preview and the long press popup.
final class PopupBackgroundView: UIView {
    func apply(_ colors: KeyboardColors) {
        backgroundColor = UIColor(argb: colors.background)
        layer.borderColor = UIColor(argb: colors.stroke).cgColor
        layer.borderWidth = 1
        layer.cornerRadius = 8
    }
}

/// Port of MyKeyboardView: draws the keys of a MyKeyboard and turns touches into key events,
/// with the key preview, long press popups (accents, tools), repeating keys and space bar cursor control.
@MainActor
final class MyKeyboardView: UIView {
    private static let notAKey = -1
    private static let delayAfterPreview = 0.1
    private static let debounceTime = 0.07
    private static let repeatInterval = 0.05 // ~20 keys per second
    private static let repeatStartDelay = 0.4
    private static let longPressTimeout = 0.4
    private static let verticalCorrection: CGFloat = -10
    private static let popupMaxMoveDistance: CGFloat = 60
    private static let spaceMoveThreshold: CGFloat = 8
    private static let keyTextSize: CGFloat = 22
    private static let previewTextSize: CGFloat = 26
    private static let labelTextSize: CGFloat = 16
    private static let spaceBarTextSize: CGFloat = 13
    private static let topSmallNumberSize: CGFloat = 10

    weak var listener: KeyboardActionListener?
    /// Where the key preview and popups are shown (the whole keyboard incl. the toolbar).
    weak var popupHost: UIView?
    let isMini: Bool

    private(set) var keyboard: MyKeyboard?
    private(set) var keys: [MyKeyboard.Key] = []
    var colors = KeyboardColors.resolve(dark: false, showKeyBorders: true) {
        didSet { setNeedsDisplay() }
    }

    private var currentKeyIndex = notAKey
    private var currentKey = notAKey
    private var lastKey = notAKey
    private var repeatKeyIndex = notAKey
    private var downTime: TimeInterval = 0
    private var lastMoveTime: TimeInterval = 0
    private var lastKeyTime: TimeInterval = 0
    private var currentKeyTime: TimeInterval = 0
    private var lastCodeX: CGFloat = 0
    private var lastCodeY: CGFloat = 0
    private var lastX: CGFloat = 0
    private var lastY: CGFloat = 0
    private var abortKey = false
    private var cursorControlActive = false
    private var lastSpaceMoveX: CGFloat = 0
    private var ignoreTouches = false
    private var activeTouches = Set<UITouch>()
    private var primaryTouch: UITouch?

    private var longPressWork: DispatchWorkItem?
    private var repeatWork: DispatchWorkItem?
    private var removePreviewWork: DispatchWorkItem?

    private lazy var previewView: PopupBackgroundView = {
        let v = PopupBackgroundView()
        v.isUserInteractionEnabled = false
        v.addSubview(previewLabel)
        return v
    }()
    private let previewLabel: UILabel = {
        let l = UILabel()
        l.textAlignment = .center
        return l
    }()

    private var miniContainer: PopupBackgroundView?
    private var miniKeyboard: MyKeyboardView?
    private var miniKeyboardOnScreen = false
    private var miniSelectedKeyIndex = -1

    init(isMini: Bool = false) {
        self.isMini = isMini
        super.init(frame: .zero)
        isOpaque = false
        backgroundColor = .clear
        isMultipleTouchEnabled = !isMini
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError() }

    /// setKeyboard().
    func setKeyboard(_ keyboard: MyKeyboard) {
        if self.keyboard != nil { showPreview(MyKeyboardView.notAKey) }
        removeMessages()
        dismissPopupKeyboard()
        self.keyboard = keyboard
        keys = keyboard.keys
        invalidateIntrinsicContentSize()
        setNeedsDisplay()
        updateAccessibility()
        // Switching to a different keyboard should abort any pending keys
        abortKey = true
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: keyboard?.minWidth ?? 0, height: keyboard?.height ?? 0)
    }

    func invalidateAllKeys() {
        setNeedsDisplay()
    }

    private var isShifted: Bool { (keyboard?.shiftState ?? .off) > .off }

    @discardableResult
    func setShifted(_ state: ShiftState) -> Bool {
        let changed = keyboard?.setShifted(state) == true
        if changed { setNeedsDisplay() }
        return changed
    }

    private func adjustCase(_ label: String) -> String {
        guard let keyboard, !label.isEmpty, keyboard.shiftState != .off, label.count < 3,
              let first = label.first, first.isLowercase else { return label }
        if Config.shared.keyboardLanguage == KeyboardLanguage.turkishQ {
            return label.uppercased(with: Locale(identifier: "tr"))
        }
        return label.uppercased(with: Locale.current)
    }

    // MARK: drawing (onBufferDraw)

    override func draw(_ rect: CGRect) {
        guard keyboard != nil else { return }
        for key in keys { drawKey(key) }
        // Overlay a dark rectangle to dim the keyboard
        if miniKeyboardOnScreen {
            UIColor(argb: colors.keyboardBackground.alphaAdjusted(0.6)).setFill()
            UIRectFillUsingBlendMode(bounds, .normal)
        }
    }

    private func fill(_ rect: CGRect, radius: CGFloat, _ color: UInt32) {
        UIColor(argb: color).setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: radius).fill()
    }

    private func drawKey(_ key: MyKeyboard.Key) {
        let code = key.code
        let frame = CGRect(x: key.x, y: key.y, width: key.width, height: key.height)
        let label = adjustCase(key.label)
        let borders = colors.showKeyBorders && !isMini

        // setupKeyBackground()
        if key.focused {
            fill(frame, radius: 8, key.pressed ? colors.primary.alphaAdjusted(0.8) : colors.primary)
        } else if code == KeyCode.enter {
            let color = key.pressed ? colors.primary.alphaAdjusted(0.8) : colors.primary
            if borders {
                fill(frame.insetBy(dx: 2, dy: 4), radius: 8, color)
            } else {
                fill(frame.insetBy(dx: 2, dy: 8), radius: 16, color)
            }
        } else if code == KeyCode.space && key.label.count > 1 && !borders {
            fill(frame.insetBy(dx: 2, dy: 8), radius: 16, key.pressed ? 0xFF757575 : 0xFF616161)
        } else if borders {
            fill(frame.insetBy(dx: 2, dy: 4), radius: 8, key.pressed ? colors.keyColorPressed : colors.keyColor)
        }

        let textColor: UInt32
        if key.pressed {
            textColor = colors.text.alphaAdjusted(0.5)
        } else if code == KeyCode.space && label.count > 1 {
            textColor = colors.text.alphaAdjusted(0.75)
        } else {
            textColor = colors.text
        }

        if !label.isEmpty {
            // For characters, use large font. For labels like "Done", use small font.
            let font: UIFont
            if code == KeyCode.space && key.label.count > 1 {
                font = .systemFont(ofSize: MyKeyboardView.spaceBarTextSize)
            } else if label.count > 1 {
                font = .systemFont(ofSize: MyKeyboardView.labelTextSize, weight: .bold)
            } else {
                font = .systemFont(ofSize: isMini ? MyKeyboardView.previewTextSize : MyKeyboardView.keyTextSize)
            }
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor(argb: textColor)]
            let rows = label.components(separatedBy: "\n")
            let size = font.pointSize
            let startY = key.height / 2 + (size + font.descender) / 2 - (size / 2) * CGFloat(rows.count - 1)
            for (index, row) in rows.enumerated() {
                let text = NSAttributedString(string: row, attributes: attributes)
                let w = text.size().width
                let baseline = key.y + startY + size * CGFloat(index)
                text.draw(at: CGPoint(x: key.x + (key.width - w) / 2, y: baseline - font.ascender))
            }

            if !key.topSmallNumber.isEmpty
                && !(Config.shared.showNumbersRow && key.topSmallNumber.range(of: "^[0-9]$", options: .regularExpression) != nil) {
                let smallFont = UIFont.systemFont(ofSize: MyKeyboardView.topSmallNumberSize)
                let color = key.pressed ? textColor : colors.text.alphaAdjusted(0.8)
                let text = NSAttributedString(string: key.topSmallNumber,
                                              attributes: [.font: smallFont, .foregroundColor: UIColor(argb: color)])
                let w = text.size().width
                let baseline = key.y + MyKeyboardView.topSmallNumberSize + 5
                text.draw(at: CGPoint(x: key.x + key.width - w - 5, y: baseline - smallFont.ascender))
            }

            // Draw secondary icons for label-based keys
            drawSecondaryIcon(key, textColor: textColor)
        } else if let icon = key.icon, let keyboard {
            let iconColor: UInt32
            if code == KeyCode.enter {
                iconColor = colors.primary.contrastARGB
            } else {
                iconColor = textColor
            }
            let symbol = icon.symbol(shift: keyboard.shiftState)
            let hasSecondary = key.secondaryIcon != nil
            // When secondary icon exists, shrink main icon to 90%
            drawSymbol(symbol, color: iconColor, pointSize: hasSecondary ? 18 : 20, center: CGPoint(x: frame.midX, y: frame.midY))
            if hasSecondary {
                drawSecondaryIcon(key, textColor: code == KeyCode.enter ? iconColor : textColor)
            }
        }
    }

    private func drawSymbol(_ name: String, color: UInt32, pointSize: CGFloat, center: CGPoint) {
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        guard let image = UIImage(systemName: name, withConfiguration: config)?
            .withTintColor(UIColor(argb: color), renderingMode: .alwaysOriginal) else { return }
        image.draw(at: CGPoint(x: center.x - image.size.width / 2, y: center.y - image.size.height / 2))
    }

    private func drawSecondaryIcon(_ key: MyKeyboard.Key, textColor: UInt32) {
        guard let icon = key.secondaryIcon else { return }
        let color = key.pressed ? textColor : colors.text.alphaAdjusted(0.6)
        let size: CGFloat = 10
        drawSymbol(icon.symbol(), color: color, pointSize: size,
                   center: CGPoint(x: key.x + key.width - 4 - size / 2 - 2, y: key.y + 5 + size / 2 + 2))
    }

    // MARK: key preview

    private func showPreview(_ keyIndex: Int) {
        let oldKeyIndex = currentKeyIndex
        currentKeyIndex = keyIndex
        guard Config.shared.showPopupOnKeypress else { return }
        // If key changed and preview is on ...
        if oldKeyIndex != currentKeyIndex {
            if keyIndex == MyKeyboardView.notAKey {
                schedule(&removePreviewWork, after: MyKeyboardView.delayAfterPreview) { [weak self] in
                    self?.previewView.isHidden = true
                }
            } else {
                showKey(keyIndex)
            }
        }
    }

    private func showKey(_ keyIndex: Int) {
        guard keys.indices.contains(keyIndex), let host = popupHost else { return }
        let key = keys[keyIndex]
        if key.code == KeyCode.space { return } // no popup for the language label
        removePreviewWork?.cancel()
        guard !key.label.isEmpty, key.code != KeyCode.modeChange, key.code != KeyCode.symbolsModeChange,
              key.code != KeyCode.shift else {
            previewView.isHidden = true
            return
        }
        previewLabel.font = key.label.count > 1 ? .systemFont(ofSize: MyKeyboardView.keyTextSize, weight: .bold)
            : .systemFont(ofSize: MyKeyboardView.previewTextSize)
        previewLabel.text = adjustCase(key.label)
        previewLabel.textColor = UIColor(argb: colors.text)
        previewView.apply(colors)
        let popupWidth = max(previewLabel.intrinsicContentSize.width + 16, key.width)
        let popupHeight = MyKeyboard.keyHeight
        var origin = convert(CGPoint(x: key.x, y: key.y - popupHeight), to: host)
        // If the popup cannot be shown above the key, put it on the side
        if origin.y < 0 {
            origin.x += key.x + key.width <= bounds.width / 2 ? key.width * 2.5 : -key.width * 2.5
            origin.y += popupHeight
        }
        if previewView.superview !== host { host.addSubview(previewView) }
        host.bringSubviewToFront(previewView)
        previewView.frame = CGRect(x: origin.x, y: origin.y, width: popupWidth, height: popupHeight)
        previewLabel.frame = previewView.bounds
        previewView.isHidden = false
    }

    // MARK: long press popups

    private func openPopupIfRequired(_ location: CGPoint) -> Bool {
        guard keys.indices.contains(currentKey) else { return false }
        let result = onLongPress(keys[currentKey], location)
        if result {
            abortKey = true
            showPreview(MyKeyboardView.notAKey)
        }
        return result
    }

    private func onLongPress(_ popupKey: MyKeyboard.Key, _ location: CGPoint) -> Bool {
        if popupKey.code == KeyCode.space {
            return onSpaceBarLongPressed()
        } else if popupKey.code == KeyCode.emojiOrLanguage {
            setCurrentKeyPressed(false)
            if Config.shared.showEmojiKey {
                listener?.openEmojiPalette()
            } else {
                listener?.showSwitchLanguageDialog()
            }
            return true
        }
        guard let layout = popupKey.popupLayout, let host = popupHost else { return false }
        let config = Config.shared
        // For 'number' and 'phone' keyboards the count of popup keys might be bigger than count of keys in the main keyboard.
        let popupKeyWidth: CGFloat
        let mini: MyKeyboard
        if let characters = popupKey.popupCharacters {
            popupKeyWidth = calcKeyWidth(popupKey, containerWidth: bounds.width)
            mini = MyKeyboard(characters: characters, keyWidth: popupKeyWidth, config: config)
        } else if layout != "template" {
            popupKeyWidth = popupKey.width
            mini = MyKeyboard(layout: layout, enterKeyType: .none, width: bounds.width, config: config)
        } else {
            return false
        }

        let container = PopupBackgroundView()
        container.apply(colors)
        container.isUserInteractionEnabled = false
        let miniView = MyKeyboardView(isMini: true)
        miniView.colors = colors
        miniView.setKeyboard(mini)
        container.addSubview(miniView)
        let miniWidth = mini.minWidth, miniHeight = mini.height

        let popupKeyCount = popupKey.popupCharacters?.count ?? mini.keys.count
        let widthToUse = miniWidth - CGFloat(popupKeyCount / 2) * popupKeyWidth
        let x = popupKey.x + popupKeyWidth - widthToUse
        let y = popupKey.y - miniHeight
        let xOffset = max(0, x)
        // make sure we highlight the proper key right after long pressing it, before any move event occurs
        let miniKeyboardX = xOffset + miniWidth <= bounds.width ? xOffset : bounds.width - miniWidth
        var origin = convert(CGPoint(x: miniKeyboardX, y: y), to: host)
        origin.y = max(0, origin.y)
        container.frame = CGRect(origin: origin, size: CGSize(width: miniWidth, height: miniHeight))
        miniView.frame = container.bounds

        let keysCnt = mini.keys.count
        var selected = Int(floor((location.x - miniKeyboardX) / popupKeyWidth))
        if keysCnt > maxKeysPerMiniRow { selected += maxKeysPerMiniRow }
        selected = max(0, min(selected, keysCnt - 1))
        for (i, key) in mini.keys.enumerated() { key.focused = i == selected }
        miniSelectedKeyIndex = selected
        miniView.setShifted(isShifted ? .onPermanent : .off)
        miniView.setNeedsDisplay()

        host.addSubview(container)
        miniContainer = container
        miniKeyboard = miniView
        miniKeyboardOnScreen = true
        setNeedsDisplay()
        return true
    }

    /// Popup Key width depends on popup keys count.
    private func calcKeyWidth(_ key: MyKeyboard.Key, containerWidth: CGFloat) -> CGFloat {
        let count = key.popupCharacters?.count ?? 0
        return CGFloat(count) > (containerWidth / key.width).rounded(.down) ? containerWidth / CGFloat(count) : key.width
    }

    private func dismissPopupKeyboard() {
        guard let container = miniContainer else { return }
        container.removeFromSuperview()
        miniContainer = nil
        miniKeyboard = nil
        miniKeyboardOnScreen = false
        setCurrentKeyPressed(false)
        setNeedsDisplay()
    }

    private func onSpaceBarLongPressed() -> Bool {
        guard !cursorControlActive else { return false }
        setCurrentKeyPressed(false)
        repeatKeyIndex = MyKeyboardView.notAKey
        repeatWork?.cancel()
        KeyboardFeedback.vibrateIfNeeded()
        listener?.showSwitchLanguageDialog()
        return true
    }

    // MARK: touches

    private enum Action { case down, pointerDown(CGPoint), move, up, cancel }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            activeTouches.insert(touch)
            if let primary = primaryTouch {
                onTouchEvent(.pointerDown(touch.location(in: self)), primary.location(in: self), touch.timestamp)
            } else {
                primaryTouch = touch
                onTouchEvent(.down, touch.location(in: self), touch.timestamp)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let primary = primaryTouch, touches.contains(primary) {
            onTouchEvent(.move, primary.location(in: self), primary.timestamp)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        activeTouches.subtract(touches)
        guard activeTouches.isEmpty, let last = touches.first else { return }
        let touch = primaryTouch.flatMap { touches.contains($0) ? $0 : nil } ?? last
        primaryTouch = nil
        onTouchEvent(.up, touch.location(in: self), touch.timestamp)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        activeTouches.subtract(touches)
        guard activeTouches.isEmpty else { return }
        primaryTouch = nil
        onTouchEvent(.cancel, touches.first?.location(in: self) ?? .zero, touches.first?.timestamp ?? 0)
    }

    private func onTouchEvent(_ action: Action, _ location: CGPoint, _ time: TimeInterval) {
        if ignoreTouches {
            if case .up = action {
                ignoreTouches = false
                // fix a glitch with long pressing backspace, then clicking some letter
                if repeatKeyIndex != MyKeyboardView.notAKey, keys.indices.contains(repeatKeyIndex),
                   keys[repeatKeyIndex].code == KeyCode.delete {
                    repeatWork?.cancel()
                    repeatKeyIndex = MyKeyboardView.notAKey
                }
            }
            return
        }

        // handle moving between alternative popup characters by swiping
        if let mini = miniKeyboard, let container = miniContainer {
            switch action {
            case .move:
                let origin = container.convert(CGPoint.zero, to: self)
                let keysCnt = mini.keys.count
                let lastRowKeyCount = keysCnt > maxKeysPerMiniRow ? max(keysCnt % maxKeysPerMiniRow, 1) : keysCnt
                let widthPerKey = keysCnt > maxKeysPerMiniRow ? container.bounds.width / CGFloat(maxKeysPerMiniRow)
                    : container.bounds.width / CGFloat(lastRowKeyCount)
                var selected = Int(floor((location.x - origin.x) / widthPerKey))
                if keysCnt > maxKeysPerMiniRow {
                    selected = max(0, selected) + maxKeysPerMiniRow
                }
                selected = max(0, min(selected, keysCnt - 1))
                if selected != miniSelectedKeyIndex {
                    for (i, key) in mini.keys.enumerated() { key.focused = i == selected }
                    miniSelectedKeyIndex = selected
                    mini.setNeedsDisplay()
                }
                if origin.x - location.x > MyKeyboardView.popupMaxMoveDistance
                    || location.x - (origin.x + container.bounds.width) > MyKeyboardView.popupMaxMoveDistance {
                    dismissPopupKeyboard()
                }
            case .up, .cancel:
                if let focused = mini.keys.first(where: { $0.focused }) {
                    listener?.onKey(focused.code)
                }
                miniSelectedKeyIndex = -1
                dismissPopupKeyboard()
            default: break
            }
        }

        onModifiedTouchEvent(action, location, time)
    }

    private func onModifiedTouchEvent(_ action: Action, _ location: CGPoint, _ eventTime: TimeInterval) {
        var touchX = location.x
        var touchY = location.y
        if touchY >= -MyKeyboardView.verticalCorrection {
            touchY += MyKeyboardView.verticalCorrection
        }
        let keyIndex = pressedKeyIndex(touchX, touchY)

        // Ignore all motion events until a DOWN.
        if abortKey {
            switch action {
            case .down, .cancel: break
            default: return
            }
        }
        if miniKeyboardOnScreen {
            if case .cancel = action {} else { return }
        }

        switch action {
        case .pointerDown(let second):
            // if the user presses a key while still holding down the previous, type in both chars and ignore the later gestures
            ignoreTouches = true
            longPressWork?.cancel()
            dismissPopupKeyboard()
            detectAndSendKey(keyIndex)
            let secondKeyIndex = pressedKeyIndex(second.x, second.y)
            showPreview(secondKeyIndex)
            detectAndSendKey(secondKeyIndex)
            if keys.indices.contains(secondKeyIndex) {
                listener?.onPress(keys[secondKeyIndex].code)
            }
            showPreview(MyKeyboardView.notAKey)
            setCurrentKeyPressed(false)
            return

        case .down:
            abortKey = false
            lastCodeX = touchX
            lastCodeY = touchY
            lastKeyTime = 0
            currentKeyTime = 0
            lastKey = MyKeyboardView.notAKey
            currentKey = keyIndex
            downTime = eventTime
            lastMoveTime = downTime

            let onPressKey = keyIndex != MyKeyboardView.notAKey ? keys[keyIndex].code : 0
            listener?.onPress(onPressKey)

            var wasHandled = false
            if currentKey >= 0 && keys[currentKey].repeatable {
                repeatKeyIndex = currentKey
                scheduleRepeat(after: MyKeyboardView.repeatStartDelay)
                // if the user long presses space bar, move the cursor after swiping left/right
                if keys[currentKey].code == KeyCode.space {
                    lastSpaceMoveX = -1
                    cursorControlActive = false
                } else {
                    repeatKey()
                }
                // Delivering the key could have caused an abort
                if abortKey {
                    repeatKeyIndex = MyKeyboardView.notAKey
                    wasHandled = true
                }
            }

            if !wasHandled && currentKey != MyKeyboardView.notAKey {
                scheduleLongPress(location)
            }

            if !isMini {
                showPreview(keyIndex)
                setCurrentKeyPressed(true)
            }

        case .move:
            var continueLongPress = false
            if keyIndex != MyKeyboardView.notAKey {
                if currentKey == MyKeyboardView.notAKey {
                    currentKey = keyIndex
                    currentKeyTime = eventTime - downTime
                } else if keyIndex == currentKey {
                    currentKeyTime += eventTime - lastMoveTime
                    continueLongPress = true
                } else if repeatKeyIndex == MyKeyboardView.notAKey {
                    setCurrentKeyPressed(false)
                    lastKey = currentKey
                    lastCodeX = lastX
                    lastCodeY = lastY
                    lastKeyTime = currentKeyTime + eventTime - lastMoveTime
                    currentKey = keyIndex
                    currentKeyTime = 0
                    setCurrentKeyPressed(true)
                }
            }

            // activate cursor control immediately on sufficient movement
            if keys.indices.contains(currentKey), keys[currentKey].code == KeyCode.space, lastSpaceMoveX != 0 {
                if lastSpaceMoveX == -1 { lastSpaceMoveX = lastX }
                let diff = lastX - lastSpaceMoveX
                let threshold = MyKeyboardView.spaceMoveThreshold
                if diff < -threshold {
                    for _ in 0..<Int((-diff / threshold).rounded(.down)) { listener?.moveCursorLeft() }
                    lastSpaceMoveX = lastX
                    if !cursorControlActive { longPressWork?.cancel() }
                    cursorControlActive = true
                } else if diff > threshold {
                    for _ in 0..<Int((diff / threshold).rounded(.down)) { listener?.moveCursorRight() }
                    lastSpaceMoveX = lastX
                    if !cursorControlActive { longPressWork?.cancel() }
                    cursorControlActive = true
                }
            } else if !continueLongPress {
                // Cancel old long-press, start new long-press if key has changed
                longPressWork?.cancel()
                if keyIndex != MyKeyboardView.notAKey { scheduleLongPress(location) }
                if !isMini { showPreview(currentKey) }
                lastMoveTime = eventTime
            }

        case .up:
            setCurrentKeyPressed(false)
            lastSpaceMoveX = 0
            removeMessages()
            if keyIndex == currentKey {
                currentKeyTime += eventTime - lastMoveTime
            } else {
                lastKey = currentKey
                lastKeyTime = currentKeyTime + eventTime - lastMoveTime
                currentKey = keyIndex
                currentKeyTime = 0
            }
            if currentKeyTime < lastKeyTime && currentKeyTime < MyKeyboardView.debounceTime && lastKey != MyKeyboardView.notAKey {
                currentKey = lastKey
                touchX = lastCodeX
                touchY = lastCodeY
            }
            showPreview(MyKeyboardView.notAKey)

            let currentKeyCode = keys.indices.contains(currentKey) ? keys[currentKey].code : nil
            // If we're not on a repeating key (which sends on a DOWN event)
            if repeatKeyIndex == MyKeyboardView.notAKey && !miniKeyboardOnScreen && !abortKey {
                detectAndSendKey(currentKey)
            } else if currentKeyCode == KeyCode.space && !cursorControlActive {
                detectAndSendKey(currentKey)
            }
            repeatKeyIndex = MyKeyboardView.notAKey
            listener?.onActionUp()
            cursorControlActive = false

        case .cancel:
            cursorControlActive = false
            lastSpaceMoveX = 0
            removeMessages()
            dismissPopupKeyboard()
            abortKey = true
            showPreview(MyKeyboardView.notAKey)
            setCurrentKeyPressed(false)
        }

        lastX = touchX
        lastY = touchY
    }

    private func pressedKeyIndex(_ x: CGFloat, _ y: CGFloat) -> Int {
        keys.firstIndex { $0.isInside(x, y) } ?? MyKeyboardView.notAKey
    }

    private func detectAndSendKey(_ index: Int) {
        guard keys.indices.contains(index) else { return }
        listener?.onKey(keys[index].code)
    }

    @discardableResult
    private func repeatKey() -> Bool {
        guard keys.indices.contains(repeatKeyIndex) else { return false }
        if keys[repeatKeyIndex].code != KeyCode.space {
            detectAndSendKey(currentKey)
        }
        return true
    }

    private func setCurrentKeyPressed(_ pressed: Bool) {
        guard keys.indices.contains(currentKey) else { return }
        keys[currentKey].pressed = pressed
        setNeedsDisplay(CGRect(x: keys[currentKey].x, y: keys[currentKey].y, width: keys[currentKey].width, height: keys[currentKey].height))
    }

    // MARK: timers (the Handler messages)

    private func schedule(_ slot: inout DispatchWorkItem?, after delay: TimeInterval, _ block: @escaping @MainActor () -> Void) {
        slot?.cancel()
        let work = DispatchWorkItem { MainActor.assumeIsolated { block() } }
        slot = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func scheduleLongPress(_ location: CGPoint) {
        schedule(&longPressWork, after: MyKeyboardView.longPressTimeout) { [weak self] in
            _ = self?.openPopupIfRequired(location)
        }
    }

    private func scheduleRepeat(after delay: TimeInterval) {
        schedule(&repeatWork, after: delay) { [weak self] in
            guard let self, self.repeatKey() else { return }
            self.scheduleRepeat(after: MyKeyboardView.repeatInterval)
        }
    }

    private func removeMessages() {
        repeatWork?.cancel()
        longPressWork?.cancel()
    }

    /// The emoji palette's backspace repeats like the keyboard's delete key.
    func startDeleteRepeat() {
        repeatKeyIndex = keys.firstIndex { $0.code == KeyCode.delete } ?? MyKeyboardView.notAKey
        currentKey = repeatKeyIndex
        KeyboardFeedback.vibrateIfNeeded()
        listener?.onKey(KeyCode.delete)
        scheduleRepeat(after: MyKeyboardView.repeatStartDelay)
    }

    func stopDeleteRepeat() {
        repeatWork?.cancel()
        repeatKeyIndex = MyKeyboardView.notAKey
    }

    /// closing(): the keyboard went away.
    func closing() {
        previewView.isHidden = true
        removeMessages()
        dismissPopupKeyboard()
        abortKey = true
    }

    // MARK: accessibility (AccessHelper)

    private func updateAccessibility() {
        let showEmojiKey = Config.shared.showEmojiKey
        accessibilityElements = keys.map { key in
            let element = KeyAccessibilityElement(accessibilityContainer: self)
            element.accessibilityLabel = key.accessibilityLabel(showEmojiKey: showEmojiKey)
            element.accessibilityFrameInContainerSpace = CGRect(x: key.x, y: key.y, width: key.width, height: key.height)
            element.accessibilityTraits = .keyboardKey
            let code = key.code
            element.activate = { [weak self] in
                self?.listener?.onPress(code)
                self?.listener?.onKey(code)
                self?.listener?.onActionUp()
            }
            return element
        }
    }
}

private final class KeyAccessibilityElement: UIAccessibilityElement {
    var activate: (() -> Void)?

    override func accessibilityActivate() -> Bool {
        activate?()
        return true
    }
}
