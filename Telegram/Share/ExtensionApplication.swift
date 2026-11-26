import UIKit

func extensionApplication(from responder: UIResponder) -> UIApplication? {
    var current: UIResponder? = responder
    while let candidate = current {
        if let application = candidate as? UIApplication {
            return application
        }
        current = candidate.next
    }
    return nil
}
