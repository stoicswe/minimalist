import Adwaita
import CAdw
import Foundation

/// Audio and video playback, the Linux answer to the macOS AVKit
/// viewers: a `GtkVideo` with its built-in transport controls (which
/// also handle space = play/pause). Audio files get the same widget —
/// GTK shows just the controls when there's no picture.
struct MediaPlayer: AdwaitaWidget {

    /// Absolute path of the media file.
    var path: String

    func container<Data>(data: WidgetData, type: Data.Type) -> ViewStorage where Data: ViewRenderData {
        let video = gtk_video_new()
        gtk_video_set_autoplay(video?.opaque(), 0)
        gtk_widget_set_hexpand(video, 1)
        gtk_widget_set_vexpand(video, 1)
        let storage = ViewStorage(video?.opaque())
        update(storage, data: data, updateProperties: true, type: type)
        return storage
    }

    func update<Data>(
        _ storage: ViewStorage,
        data: WidgetData,
        updateProperties: Bool,
        type: Data.Type
    ) where Data: ViewRenderData {
        guard updateProperties, storage.fields["path"] as? String != path else { return }
        storage.fields["path"] = path
        gtk_video_set_filename(storage.opaquePointer, path)
    }
}
