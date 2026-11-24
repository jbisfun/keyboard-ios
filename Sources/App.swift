import FossifyCommons
import Observation
import SwiftUI
import UIKit

enum Route: Hashable {
    case settings
    case manageClipboardItems
    case customizeColors
    case about
}

@MainActor
@Observable
final class Router {
    var path: [Route] = []
    var toast: String?

    func push(_ r: Route) { path.append(r) }
}

/// The whole app as one view: the standalone app's window content, and what
/// the launcher presents.
public struct KeyboardRoot: View {
    @State private var router = Router()

    public init() {}

    public var body: some View {
        RootView()
            .environment(router)
            .environment(Config.shared)
            .environment(ClipsStore.shared)
            .fossifyTheme()
    }
}

struct RootView: View {
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var phase

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            MainView()
                .navigationDestination(for: Route.self) { route in
                    Group {
                        switch route {
                        case .settings: SettingsView()
                        case .manageClipboardItems: ManageClipboardItemsView()
                        case .customizeColors: CustomizeColorsView()
                        case .about: AboutView(app: .keyboard)
                        }
                    }
                    .toolbar(.hidden, for: .navigationBar)
                    .paletteBackground()
                }
                .toolbar(.hidden, for: .navigationBar)
        }
        .toast($router.toast)
        // fossify-keyboard://settings and ://clipboard, opened by the keyboard extension's buttons.
        .onOpenURL { url in
            guard url.scheme == KeyboardRoot.urlScheme else { return }
            switch url.host {
            case "settings": router.path = [.settings]
            case "clipboard": router.path = [.manageClipboardItems]
            default: break
            }
        }
        .onChange(of: phase) {
            if phase == .active {
                Config.shared.reload()
                ClipsStore.shared.reload()
            }
            Config.shared.exportColors()
        }
    }
}

extension KeyboardRoot {
    nonisolated static let urlScheme = "fossify-keyboard"
}

/// Opens the containing app from the keyboard extension (keyboards have no extensionContext.open).
@MainActor
public func openContainingApp(_ path: String, from responder: UIResponder) {
    guard let url = URL(string: "\(KeyboardRoot.urlScheme)://\(path)") else { return }
    var current: UIResponder? = responder
    while let r = current {
        if let app = r as? UIApplication {
            app.open(url)
            return
        }
        current = r.next
    }
}
