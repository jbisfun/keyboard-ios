# keyboard-ios

[Fossify Keyboard](https://github.com/FossifyOrg/Keyboard) re-created for iOS in SwiftUI and UIKit.

    idl build -c release     # -> build/release/FossifyKeyboard.ipa (ad-hoc signed; re-sign to install)
    idl install "<device>" FossifyKeyboard

The IPA contains the app and `KeyboardExtension.appex`, a system keyboard (Settings > General > Keyboard > Keyboards > Add New Keyboard > Fossify Keyboard, then allow Full Access). Both share `KeyboardKit`, whose `KeyboardInputView` is also the `inputView` of the app's own text fields, so the keyboard works inside the app (and the launcher) without enabling it.

Ported: every upstream layout and language (the 50 key layouts are read from the upstream XML, with numbers, phone and three symbol pages), shift / double-tap caps lock and sentence capitalization, long-press popups with accents and the tools popup, key preview popups, repeating delete, space bar cursor control, long-press space to switch the language, the emoji / language switch key, Vietnamese Telex, the emoji palette with categories and recently used emojis, the toolbar with the current clip, the clipboard manager with current and pinned clips, Manage clipboard items (add, edit, delete, reorder, import / export JSON), and all settings: colors, keyboard language, manage keyboard languages, key borders, numbers row, emoji / language switch key, keyboard height, popup on keypress, vibration, sound on keypress (off / follow system / always), sentence capitalization, show clipboard content.

Differences forced by iOS: system-wide use needs the keyboard extension with Full Access (clipboard, sounds, haptics, settings shared through an App Group); the extension's settings and clipboard buttons open the app; no voice typing method or autofill suggestions; a "next keyboard" globe button appears when iOS asks for one; previews of the top row show beside the key (keyboards cannot draw above themselves); "Change Keyboard" opens Settings; no in-app language switch; icons are SF Symbols.

GPL-3.0, like the original.
