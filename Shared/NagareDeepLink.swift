import Foundation

enum NagareDeepLink {
#if DEBUG
    static let scheme = "nagare-dev"
#else
    static let scheme = "nagare"
#endif

    static let quickAddURL = URL(
        string: "\(scheme)://quick-add"
    )!

    static func destination(
        for url: URL
    ) -> NagareAppDestination? {
        guard url.scheme == scheme else {
            return nil
        }

        switch url.host {
        case "quick-add":
            return .quickAdd
        default:
            return nil
        }
    }
}
