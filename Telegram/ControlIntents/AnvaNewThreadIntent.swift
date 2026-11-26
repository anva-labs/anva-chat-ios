import AppIntents

#if ANVA_MAIN_APP
import TelegramUI
#endif

@available(iOS 18.0, *)
public struct AnvaNewThreadIntent: AppIntent {
    public static let title: LocalizedStringResource = "New Thread"
    public static let openAppWhenRun = true

    @available(iOS 26.0, *)
    public static let supportedModes: IntentModes = .foreground(.immediate)

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        #if ANVA_MAIN_APP
        openAnvaNewThreadFromControl()
        #endif
        return .result()
    }
}
