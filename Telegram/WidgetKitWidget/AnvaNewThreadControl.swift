import AnvaNewThreadIntents
import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct AnvaNewThreadControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "anva.new-thread") {
            ControlWidgetButton(action: AnvaNewThreadIntent()) {
                Label("New Thread", systemImage: "square.and.pencil")
            }
        }
        .displayName("New Thread")
        .description("Start a new thread with your most recently active bot.")
    }
}
