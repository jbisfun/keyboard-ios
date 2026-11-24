import AudioToolbox
import UIKit

/// KeyboardFeedbackManager: keypress haptics and audio.
@MainActor
enum KeyboardFeedback {
    private static let impact = UIImpactFeedbackGenerator(style: .light)
    private static let selection = UISelectionFeedbackGenerator()

    /// Haptic feedback for a standard keypress.
    static func vibrateIfNeeded() {
        if Config.shared.vibrateOnKeypress { impact.impactOccurred() }
    }

    /// Haptic feedback for cursor handle movement (HapticFeedbackConstants.TEXT_HANDLE_MOVE).
    static func performHapticHandleMove() {
        if Config.shared.vibrateOnKeypress { selection.selectionChanged() }
    }

    /// Keypress sound: "Follow system" uses the input click (honours the system "Keyboard clicks"
    /// switch), "Always on" plays the keyboard sounds directly.
    static func playKeypressSoundIfNeeded(_ code: Int) {
        switch Config.shared.soundOnKeypress {
        case .none: return
        case .system: UIDevice.current.playInputClick()
        case .always:
            let sound: SystemSoundID
            switch code {
            case KeyCode.delete: sound = 1155
            case KeyCode.enter, KeyCode.space: sound = 1156
            default: sound = 1104
            }
            AudioServicesPlaySystemSound(sound)
        }
    }

    static func performKeypressFeedback(_ code: Int) {
        vibrateIfNeeded()
        playKeypressSoundIfNeeded(code)
    }
}
