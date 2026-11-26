import Foundation
import AppBundle
import TelegramCore
import TelegramPresentationData

public struct AnvaStrings {
    private let strings: PresentationStrings
    private let bundledLocalization: Bundle?

    init(strings: PresentationStrings) {
        self.strings = strings
        let languageCodes = [strings.primaryComponent.languageCode, strings.baseLanguageCode]
        self.bundledLocalization = languageCodes.contains { code in
            code.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first == "zh"
        } ? Self.chineseBundle : nil
    }

    private static let englishBundle = getAppBundle().url(forResource: "en", withExtension: "lproj").flatMap(Bundle.init(url:))
    private static let chineseBundle = getAppBundle().url(forResource: "zh-Hans", withExtension: "lproj").flatMap(Bundle.init(url:))

    private func localized(_ key: String, fallbackValue: String? = nil) -> String {
        if let value = self.strings.primaryComponent.dict[key] ?? self.strings.secondaryComponent?.dict[key] {
            return value
        }
        let fallback = fallbackValue ?? Self.englishBundle?.localizedString(forKey: key, value: nil, table: "Anva")
        return self.bundledLocalization?.localizedString(forKey: key, value: fallback, table: "Anva") ?? fallback ?? key
    }

    public static func newThreadMenuTitle(strings: PresentationStrings) -> String {
        return Self(strings: strings).localized("Anva.NewThreadMenuAction", fallbackValue: strings.Chat_NewThreadInfo_Title)
    }

    public static func messageActionsTitle(strings: PresentationStrings) -> String {
        return Self(strings: strings).localized("Anva.MessageActions", fallbackValue: "Message Actions")
    }

    var homeTitle: String {
        return self.localized("Anva.Home")
    }

    var markAllAsRead: String {
        return self.localized("Anva.MarkAllAsRead", fallbackValue: self.strings.ChatList_Context_MarkAllAsRead)
    }

    var botsTitle: String {
        return self.localized("Anva.Bots")
    }

    var managedBotsEmptyTitle: String {
        return self.localized("Anva.ManagedBotsEmpty")
    }

    var managedBotsErrorTitle: String {
        return self.localized("Anva.ManagedBotsError")
    }

    var searchPlaceholder: String {
        return self.localized("Anva.SearchPlaceholder")
    }

    var messageSearchResults: String {
        return self.localized("Anva.MessageSearchResults")
    }

    var emptyTitle: String {
        return self.localized("Anva.EmptyTitle")
    }

    var emptyBody: String {
        return self.localized("Anva.EmptyBody")
    }

    var emptyAction: String {
        return self.localized("Anva.EmptyAction")
    }

    var noResults: String {
        return self.localized("Anva.NoResults")
    }

    var unknownBot: String {
        return self.localized("Anva.Bot")
    }

    var noMessages: String {
        return self.localized("Anva.NoMessages")
    }

    func youPrefix(_ text: String) -> String {
        return self.localized("Anva.YouPrefix").replacingOccurrences(of: "%@", with: text)
    }

    var pin: String {
        return self.strings.ChatList_Context_Pin
    }

    var unpin: String {
        return self.strings.ChatList_Context_Unpin
    }

    var rename: String {
        return self.localized("Anva.Rename")
    }

    var remove: String {
        return self.localized("Anva.Remove")
    }

    var renameTitle: String {
        return self.localized("Anva.RenameTitle")
    }

    var renamePlaceholder: String {
        return self.localized("Anva.RenamePlaceholder")
    }

    var cancel: String {
        return self.strings.Common_Cancel
    }

    var save: String {
        return self.strings.Common_Save
    }

    var close: String {
        return self.strings.Common_Close
    }

    var pickerTitle: String {
        return self.localized("Anva.EmptyAction")
    }

    var pickerBotSubtitle: String {
        return self.localized("Anva.Bot")
    }

    var pickerEmptyTitle: String {
        return self.localized("Anva.PickerEmptyTitle")
    }

    func mediaLabel(for media: EngineMedia) -> String {
        switch media {
        case .image:
            return self.localized("Anva.MediaPhoto")
        case let .file(file):
            if file.isVideoSticker || file.isAnimatedSticker || file.isSticker {
                return self.localized("Anva.MediaSticker")
            } else if file.isAnimated {
                return "[GIF]"
            } else if file.isVideo {
                return self.localized("Anva.MediaVideo")
            } else if file.isVoice {
                return self.localized("Anva.MediaVoice")
            } else if file.isMusic {
                return self.localized("Anva.MediaAudio")
            } else {
                return self.localized("Anva.MediaFile")
            }
        case .geo:
            return self.localized("Anva.MediaLocation")
        case .contact:
            return self.localized("Anva.MediaContact")
        case .poll:
            return self.localized("Anva.MediaPoll")
        case .webpage:
            return self.localized("Anva.MediaLink")
        case .todo:
            return self.localized("Anva.MediaChecklist")
        case .story:
            return self.localized("Anva.MediaStory")
        case .invoice:
            return self.localized("Anva.MediaInvoice")
        case .dice:
            return self.localized("Anva.MediaDice")
        case .game:
            return self.localized("Anva.MediaGame")
        case .action:
            return ""
        case .expiredContent, .unsupported, .webFile, .giveaway, .giveawayResults, .paidContent, .liveStream, .widget, .custom:
            return self.localized("Anva.MediaMessage")
        }
    }

    func formatTimestamp(_ timestamp: Int32, now: Int32 = Int32(Date().timeIntervalSince1970)) -> String {
        if timestamp <= 0 {
            return ""
        }
        let delta = now - timestamp
        if delta >= 0 && delta < 60 {
            return self.localized("Anva.JustNow")
        }

        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let nowDate = Date(timeIntervalSince1970: TimeInterval(now))
        let calendar = Calendar.current

        if calendar.isDate(date, inSameDayAs: nowDate) {
            return AnvaStrings.timeFormatter.string(from: date)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: nowDate), calendar.isDate(date, inSameDayAs: yesterday) {
            return self.localized("Anva.Yesterday")
        }

        let dateYear = calendar.component(.year, from: date)
        let nowYear = calendar.component(.year, from: nowDate)
        if dateYear == nowYear {
            return AnvaStrings.monthDayFormatter.string(from: date)
        }
        return AnvaStrings.yearMonthDayFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter
    }()

    private static let yearMonthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()
}
