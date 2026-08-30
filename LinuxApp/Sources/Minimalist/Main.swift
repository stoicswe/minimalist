import Adwaita
import MinimalistCore

@main
struct MinimalistLinux: App {

    let app = AdwaitaApp(id: "com.stoicswe.minimalist")

    var scene: Scene {
        Window(id: "main") { window in
            MainView(app: app, window: window)
        }
        .title("{m.txt}")
        .defaultSize(width: 1100, height: 720)
        // Ctrl+W closes the *tab* (GNOME convention, see PORTING.md), so
        // the window uses Ctrl+Shift+W and Ctrl+Q quits.
        .keyboardShortcut("w".ctrl().shift()) { $0.close() }
        .quitShortcut()
        .onClose {
            // Write the session snapshot and the quit-time "session end"
            // commit before the window goes away.
            SessionHook.shared.quit()
            return .close
        }
    }

}
