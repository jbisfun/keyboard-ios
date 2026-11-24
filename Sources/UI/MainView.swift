import FossifyCommons
import SwiftUI
import UIKit

/// A text field typing with the Fossify keyboard (its `inputView` is a KeyboardInputView), so the
/// keyboard works inside the app and the launcher without the system keyboard extension.
public struct KeyboardTextField: UIViewRepresentable {
    let placeholder: String
    let keyboardType: UIKeyboardType
    let capitalization: UITextAutocapitalizationType
    let secure: Bool
    let returnKey: UIReturnKeyType
    let textColor: Color
    var onOpenSettings: () -> Void
    var onManageClipboard: () -> Void

    public init(_ placeholder: String = "", keyboardType: UIKeyboardType = .default,
                capitalization: UITextAutocapitalizationType = .sentences, secure: Bool = false,
                returnKey: UIReturnKeyType = .default, textColor: Color = .primary,
                onOpenSettings: @escaping () -> Void = {}, onManageClipboard: @escaping () -> Void = {}) {
        self.placeholder = placeholder
        self.keyboardType = keyboardType
        self.capitalization = capitalization
        self.secure = secure
        self.returnKey = returnKey
        self.textColor = textColor
        self.onOpenSettings = onOpenSettings
        self.onManageClipboard = onManageClipboard
    }

    public func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.placeholder = placeholder
        field.keyboardType = keyboardType
        field.autocapitalizationType = capitalization
        field.isSecureTextEntry = secure
        field.returnKeyType = returnKey
        field.font = .systemFont(ofSize: 18)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.inputView = KeyboardInputView(target: TextInputTarget(field), onOpenSettings: onOpenSettings,
                                            onManageClipboard: onManageClipboard)
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.addTarget(context.coordinator, action: #selector(Coordinator.done(_:)), for: .editingDidEndOnExit)
        return field
    }

    public func updateUIView(_ field: UITextField, context: Context) {
        field.textColor = UIColor(textColor)
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    public final class Coordinator: NSObject {
        @objc func changed(_ field: UITextField) {
            (field.inputView as? KeyboardInputView)?.textDidChange()
        }

        @objc func done(_ field: UITextField) {
            field.resignFirstResponder()
        }
    }
}

/// MainActivity: "Change Keyboard" and the test fields (text, phone, email, password).
struct MainView: View {
    @Environment(Router.self) private var router
    @Environment(\.palette) private var palette
    @Environment(\.scenePhase) private var phase
    @State private var redirectionNote = false

    /// The keyboard extension ships in the standalone app only (not in the launcher).
    private var hasKeyboardExtension: Bool {
        guard let plugins = Bundle.main.builtInPlugInsURL,
              let items = try? FileManager.default.contentsOfDirectory(atPath: plugins.path) else { return false }
        return items.contains("KeyboardExtension.appex")
    }

    /// isKeyboardEnabled(): the enabled keyboards iOS lists in AppleKeyboards.
    private var isKeyboardEnabled: Bool {
        let enabled = UserDefaults.standard.object(forKey: "AppleKeyboards") as? [String] ?? []
        let id = (Bundle.main.bundleIdentifier ?? "") + ".extension"
        return enabled.contains(id)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                CloseAppButton()
                Text("Keyboard").font(.system(size: 21, weight: .medium)).padding(.leading, 12)
                Spacer()
                IconButton(icon: "gearshape") { launchSettings() }
                OverflowMenu {
                    Button("About") { router.push(.about) }
                }
            }
            .padding(.horizontal, 4)
            .frame(height: 56)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if hasKeyboardExtension {
                        Button {
                            Launcher.open(URL(string: UIApplication.openSettingsURLString))
                        } label: {
                            Text("Change Keyboard")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(palette.onPrimary)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Capsule().fill(palette.primaryColor))
                        }
                        .buttonStyle(PressedStyle())
                        .frame(maxWidth: .infinity)
                        .padding(12)
                    }
                    field(KeyboardTextField(capitalization: .sentences, textColor: palette.textColor,
                                            onOpenSettings: launchSettings, onManageClipboard: manageClipboard))
                    field(KeyboardTextField(keyboardType: .phonePad, capitalization: .none, textColor: palette.textColor,
                                            onOpenSettings: launchSettings, onManageClipboard: manageClipboard))
                    field(KeyboardTextField(keyboardType: .emailAddress, capitalization: .none, textColor: palette.textColor,
                                            onOpenSettings: launchSettings, onManageClipboard: manageClipboard))
                    field(KeyboardTextField(capitalization: .none, secure: true, textColor: palette.textColor,
                                            onOpenSettings: launchSettings, onManageClipboard: manageClipboard))
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(palette.backgroundColor.ignoresSafeArea())
        .onAppear(perform: checkKeyboardEnabled)
        .onChange(of: phase) { if phase == .active { checkKeyboardEnabled() } }
        .sheet(isPresented: $redirectionNote) {
            DialogFrame(title: nil, scroll: false) {
                Text("Please enable Fossify Keyboard on the next screen (Keyboards), to make it an available keyboard. Come back once enabled.")
                    .font(.system(size: 16))
                HStack {
                    Spacer()
                    Button("OK") {
                        redirectionNote = false
                        Launcher.open(URL(string: UIApplication.openSettingsURLString))
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(palette.primaryColor)
                }
                .padding(.top, 16)
            }
            .presentationDetents([.height(200)])
        }
    }

    private func field(_ field: KeyboardTextField) -> some View {
        VStack(spacing: 4) {
            field.frame(height: 40)
            Rectangle().fill(palette.primaryColor).frame(height: 1)
        }
        .padding(16)
    }

    private func checkKeyboardEnabled() {
        if hasKeyboardExtension && !isKeyboardEnabled { redirectionNote = true }
    }

    private func launchSettings() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        router.push(.settings)
    }

    private func manageClipboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        router.push(.manageClipboardItems)
    }
}
