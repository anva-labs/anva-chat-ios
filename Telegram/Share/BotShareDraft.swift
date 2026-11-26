import UIKit
import UniformTypeIdentifiers

@MainActor
enum BotShareDraft {
    static func open(from controller: UIViewController, botPeerId: Int64) {
        let items = controller.extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        let attachments = items.flatMap { $0.attachments ?? [] }
        Task { [weak controller] in
            guard let controller else {
                return
            }
            if let url = await self.sharedWebURL(in: attachments) {
                self.open(URLQueryItem(name: "url", value: url.absoluteString), from: controller, botPeerId: botPeerId)
                return
            }

            let photos = attachments.compactMap { provider -> (NSItemProvider, String)? in
                guard let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) else {
                    return nil
                }
                return (provider, type)
            }
            if !photos.isEmpty {
                do {
                    let directory = try await self.stagePhotos(photos)
                    self.open(URLQueryItem(name: "photos", value: directory.lastPathComponent), from: controller, botPeerId: botPeerId) {
                        try? FileManager.default.removeItem(at: directory)
                    }
                } catch {
                    self.showError(NSLocalizedString("Couldn’t prepare the shared photos", comment: "Photo share error"), from: controller)
                }
                return
            }

            if let url = await self.sharedWebURL(inTextFrom: items, attachments: attachments) {
                self.open(URLQueryItem(name: "url", value: url.absoluteString), from: controller, botPeerId: botPeerId)
            } else {
                self.showError(NSLocalizedString("Share a photo or text containing a web link", comment: "No supported content in the share action input"), from: controller)
            }
        }
    }

    private static func sharedWebURL(in attachments: [NSItemProvider]) async -> URL? {
        for attachment in attachments {
            if let url = await self.load(NSURL.self, from: attachment), let webURL = self.webURL(url as URL) {
                return webURL
            }
        }
        return nil
    }

    private static func sharedWebURL(inTextFrom items: [NSExtensionItem], attachments: [NSItemProvider]) async -> URL? {
        for attachment in attachments {
            if let text = await self.load(NSAttributedString.self, from: attachment), let url = self.webURL(in: text) {
                return url
            }
            if let text = await self.load(NSString.self, from: attachment), let url = self.webURL(in: NSAttributedString(string: text as String)) {
                return url
            }
        }
        for item in items {
            if let text = item.attributedContentText, let url = self.webURL(in: text) {
                return url
            }
        }
        return nil
    }

    private static func load<T: NSItemProviderReading>(_ type: T.Type, from attachment: NSItemProvider) async -> T? {
        guard attachment.canLoadObject(ofClass: type) else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            attachment.loadObject(ofClass: type) { object, _ in
                continuation.resume(returning: object as? T)
            }
        }
    }

    private static func webURL(in text: NSAttributedString) -> URL? {
        let range = NSRange(location: 0, length: text.length)
        var link: URL?
        text.enumerateAttribute(.link, in: range) { value, _, stop in
            let url = (value as? URL) ?? (value as? String).flatMap { URL(string: $0) }
            if let url, let webURL = self.webURL(url) {
                link = webURL
                stop.pointee = true
            }
        }
        if let link {
            return link
        }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        return detector.matches(in: text.string, range: range)
            .lazy.compactMap { $0.url.flatMap(self.webURL) }
            .first
    }

    private static func webURL(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else {
            return nil
        }
        return url
    }

    private static func stagePhotos(_ photos: [(NSItemProvider, String)]) async throws -> URL {
        guard photos.count <= 10, let extensionId = Bundle.main.bundleIdentifier,
              let suffix = extensionId.lastIndex(of: "."),
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.\(extensionId[..<suffix])") else {
            throw CocoaError(.fileWriteNoPermission)
        }

        let fileManager = FileManager.default
        let directory = container.appendingPathComponent("telegram-data/share/ask-my-bot", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            for (index, photo) in photos.enumerated() {
                let (provider, type) = photo
                let destination = directory.appendingPathComponent("\(index)")
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                        guard let url else {
                            continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                            return
                        }
                        do {
                            // The provider deletes its temporary file when this callback returns.
                            try FileManager.default.copyItem(at: url, to: destination)
                            continuation.resume()
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
            return directory
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
    }

    private static func open(_ item: URLQueryItem, from controller: UIViewController, botPeerId: Int64, onFailure: (() -> Void)? = nil) {
        guard let application = extensionApplication(from: controller) else {
            onFailure?()
            self.showError(from: controller)
            return
        }
        var components = URLComponents()
        components.scheme = "anva"
        components.host = "ask_my_bot"
        components.queryItems = [item, URLQueryItem(name: "bot", value: String(botPeerId))]
        guard let target = components.url else {
            onFailure?()
            self.showError(from: controller)
            return
        }

        application.open(target, options: [:]) { [weak controller] opened in
            if opened {
                controller?.extensionContext?.completeRequest(returningItems: nil)
            } else {
                onFailure?()
                if let controller {
                    self.showError(from: controller)
                }
            }
        }
    }

    private static func showError(_ title: String = NSLocalizedString("Couldn’t open the shared content in Anva", comment: "Share action error"), from controller: UIViewController) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Close", comment: "Dismiss share action"), style: .cancel) { [weak controller] _ in
            controller?.extensionContext?.completeRequest(returningItems: nil)
        })
        controller.present(alert, animated: true)
    }
}
