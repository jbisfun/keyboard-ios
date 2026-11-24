import FossifyCommons
import SwiftUI

private extension Color {
    init(_ argb: UInt32) { self.init(argb: argb) }
}

/// toolbar_holder: clear clipboard, the current clip, (next keyboard), clipboard manager, settings.
struct KeyboardToolbar: View {
    let state: KeyboardState
    unowned let keyboard: KeyboardInputView

    var body: some View {
        let c = state.colors
        HStack(spacing: 0) {
            if state.clipboardValue != nil {
                toolbarIcon("trash", hint: "Clear clipboard data") { keyboard.clearClipboardContent() }
                    .transition(.opacity)
            }
            Spacer(minLength: 4)
            if let value = state.clipboardValue {
                Text(value.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: 16))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(Color(c.text))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(c.background)))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(c.stroke), lineWidth: 1))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        keyboard.onText(value)
                        KeyboardFeedback.vibrateIfNeeded()
                    }
                    .transition(.opacity)
            }
            Spacer(minLength: 4)
            if state.showsInputModeSwitch {
                toolbarIcon("globe", hint: "Next keyboard") { keyboard.advanceInputMode() }
            }
            toolbarIcon("doc.on.clipboard", hint: "Clipboard") {
                KeyboardFeedback.vibrateIfNeeded()
                keyboard.openClipboardManager()
            }
            toolbarIcon("gearshape", hint: "Settings") { keyboard.openSettings() }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(c.keyboardBackground))
        .overlay(alignment: .top) {
            if state.showsDivider { Rectangle().fill(Color(c.stroke)).frame(height: 1) }
        }
    }

    private func toolbarIcon(_ name: String, hint: String, action: @escaping () -> Void) -> some View {
        Image(systemName: name)
            .font(.system(size: 19))
            .foregroundStyle(Color(state.colors.text))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .onLongPressGesture { keyboard.showToast(hint) }
            .accessibilityLabel(hint)
            .accessibilityAddTraits(.isButton)
    }
}

/// emoji_palette_holder, clipboard_manager_holder and SwitchLanguageDialog, drawn over the keys.
struct KeyboardPanels: View {
    let state: KeyboardState
    unowned let keyboard: KeyboardInputView

    var body: some View {
        ZStack {
            switch state.panel {
            case .emoji: EmojiPalette(state: state, keyboard: keyboard)
            case .clipboard: ClipboardManager(state: state, keyboard: keyboard)
            case .none: Color.clear
            }
            if state.showLanguageDialog {
                SwitchLanguageDialog(state: state, keyboard: keyboard)
            }
        }
    }
}

/// The top bar of the emoji palette and the clipboard manager.
private struct PanelTopBar<Trailing: View>: View {
    let state: KeyboardState
    let title: String
    let onClose: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        let c = state.colors
        HStack(spacing: 0) {
            Image(systemName: "arrow.left")
                .font(.system(size: 19))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .onTapGesture {
                    KeyboardFeedback.vibrateIfNeeded()
                    onClose()
                }
            Text(title).font(.system(size: 20)).lineLimit(1).padding(.leading, 4)
            Spacer()
            trailing()
        }
        .foregroundStyle(Color(c.text))
        .padding(.horizontal, 4)
        .frame(height: 46)
        .background(Color(c.keyboardBackground))
    }
}

private struct HeaderOffsetKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

/// The emoji palette (EmojisAdapter + emoji_categories_strip).
private struct EmojiPalette: View {
    let state: KeyboardState
    unowned let keyboard: KeyboardInputView
    @State private var activeCategory: String?
    @State private var backspacePressed = false

    var body: some View {
        let c = state.colors
        VStack(spacing: 0) {
            PanelTopBar(state: state, title: "Emojis", onClose: keyboard.closeEmojiPalette) { EmptyView() }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 42), spacing: 0)], alignment: .leading, spacing: 0) {
                        ForEach(state.emojiCategories, id: \.0) { category, emojis in
                            Section {
                                ForEach(emojis, id: \.emoji) { emoji in
                                    Text(emoji.emoji)
                                        .font(.system(size: 30))
                                        .frame(width: 42, height: 46)
                                        .contentShape(Rectangle())
                                        .onTapGesture { keyboard.emojiPicked(emoji) }
                                }
                            } header: {
                                Text(Emojis.title(category).uppercased())
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color(c.text.alphaAdjusted(0.6)))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 4)
                                    .padding(.top, 4)
                                    .padding(.bottom, 2)
                                    .id(category)
                                    .background(GeometryReader { g in
                                        Color.clear.preference(key: HeaderOffsetKey.self,
                                                               value: [category: g.frame(in: .named("emojis")).minY])
                                    })
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .coordinateSpace(name: "emojis")
                .onPreferenceChange(HeaderOffsetKey.self) { offsets in
                    let order = state.emojiCategories.map(\.0)
                    if let top = order.last(where: { (offsets[$0] ?? .infinity) <= 1 }) ?? order.first(where: { offsets[$0] != nil }) {
                        activeCategory = top
                    }
                }
                .background(Color(c.background))

                // emoji_palette_bottom_bar
                HStack(spacing: 0) {
                    Text("ABC")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 52, height: 42)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            KeyboardFeedback.vibrateIfNeeded()
                            keyboard.closeEmojiPalette()
                        }
                    HStack(spacing: 0) {
                        ForEach(state.emojiCategories.map(\.0), id: \.self) { category in
                            Image(systemName: Emojis.icon(category))
                                .font(.system(size: 15))
                                .foregroundStyle(category == (activeCategory ?? state.emojiCategories.first?.0)
                                                 ? Color(c.primary) : Color(c.text.alphaAdjusted(0.8)))
                                .frame(maxWidth: .infinity, minHeight: 42)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    activeCategory = category
                                    proxy.scrollTo(category, anchor: .top)
                                }
                        }
                    }
                    Image(systemName: "delete.left")
                        .font(.system(size: 19))
                        .frame(width: 52, height: 42)
                        .opacity(backspacePressed ? 0.6 : 1)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                if !backspacePressed {
                                    backspacePressed = true
                                    keyboard.startDeleteRepeat()
                                }
                            }
                            .onEnded { _ in
                                backspacePressed = false
                                keyboard.stopDeleteRepeat()
                            })
                }
                .foregroundStyle(Color(c.text))
                .frame(height: 46)
                .background(Color(c.keyboardBackground))
            }
        }
    }
}

/// The clipboard manager (ClipsKeyboardAdapter in a 2-column staggered grid).
private struct ClipboardManager: View {
    let state: KeyboardState
    unowned let keyboard: KeyboardInputView

    var body: some View {
        let c = state.colors
        VStack(spacing: 0) {
            PanelTopBar(state: state, title: "Clipboard", onClose: keyboard.closeClipboardManager) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 19))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .onTapGesture { keyboard.manageClipboardItems() }
                    .onLongPressGesture { keyboard.showToast("Manage clipboard items") }
            }
            .overlay(alignment: .top) {
                if state.showsDivider { Rectangle().fill(Color(c.stroke)).frame(height: 1) }
            }
            Group {
                if state.clipSections.isEmpty {
                    VStack(spacing: 12) {
                        Text("Your clipboard is empty.").font(.system(size: 18))
                        Text("Once you copy some text, it will show up here. You can also pin clips so they won't disappear later.")
                            .font(.system(size: 14))
                    }
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(c.text))
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(state.clipSections) { section in
                                if let label = section.label { sectionLabel(label, isCurrent: section.isCurrent) }
                                staggered(section.clips)
                            }
                        }
                        .padding(4)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(c.background))
        }
    }

    private func sectionLabel(_ label: String, isCurrent: Bool) -> some View {
        let c = state.colors
        return HStack(spacing: 0) {
            Text(label).font(.system(size: 14)).padding(8)
            Image(systemName: isCurrent ? "pin" : "pin.fill")
                .font(.system(size: 14))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .onTapGesture { if isCurrent { keyboard.pinCurrentClip() } }
                .onLongPressGesture { if isCurrent { keyboard.showToast("Pin text") } }
        }
        .foregroundStyle(Color(c.text))
        .opacity(0.8)
    }

    /// StaggeredGridLayoutManager(spanCount = 2): each clip goes to the shorter column.
    private func staggered(_ clips: [Clip]) -> some View {
        var columns: [[Clip]] = [[], []]
        var heights: [Int] = [0, 0]
        for clip in clips {
            let lines = min(10, clip.value.count / 18 + clip.value.filter { $0 == "\n" }.count + 1)
            let i = heights[0] <= heights[1] ? 0 : 1
            columns[i].append(clip)
            heights[i] += lines + 2
        }
        return HStack(alignment: .top, spacing: 0) {
            ForEach(0..<2, id: \.self) { i in
                VStack(spacing: 0) {
                    ForEach(columns[i]) { clip in clipView(clip) }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    private func clipView(_ clip: Clip) -> some View {
        let c = state.colors
        return Text(clip.value)
            .font(.system(size: 14))
            .lineLimit(10)
            .foregroundStyle(Color(c.text))
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(c.background)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(c.stroke), lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture {
                keyboard.onText(clip.value)
                KeyboardFeedback.vibrateIfNeeded()
            }
            .padding(4)
    }
}

/// SwitchLanguageDialog: pick one of the selected keyboard languages.
private struct SwitchLanguageDialog: View {
    let state: KeyboardState
    unowned let keyboard: KeyboardInputView

    var body: some View {
        let c = state.colors
        let config = Config.shared
        ZStack {
            Color.black.opacity(0.4)
                .contentShape(Rectangle())
                .onTapGesture { keyboard.dismissLanguageDialog() }
            VStack(alignment: .leading, spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(config.selectedLanguagesSorted, id: \.self) { language in
                                let on = language == config.keyboardLanguage
                                HStack(spacing: 16) {
                                    Image(systemName: on ? "largecircle.fill.circle" : "circle")
                                        .font(.system(size: 20))
                                        .foregroundStyle(on ? Color(c.primary) : Color(c.text.alphaAdjusted(0.65)))
                                    Text(KeyboardLanguage.title(language))
                                    Spacer()
                                }
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                                .onTapGesture { keyboard.selectLanguage(language) }
                                .id(language)
                            }
                        }
                    }
                    .onAppear { proxy.scrollTo(config.keyboardLanguage, anchor: .bottom) }
                }
                HStack {
                    Spacer()
                    Text("Manage keyboard languages")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(c.primary))
                        .padding(.vertical, 8)
                        .onTapGesture { keyboard.openSettings() }
                }
            }
            .foregroundStyle(Color(c.text))
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color(c.background)))
            .padding(24)
        }
    }
}
