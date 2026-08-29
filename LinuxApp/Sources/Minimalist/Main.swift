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
        .closeShortcut()
        .quitShortcut()
    }

}
