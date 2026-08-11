import Foundation

enum NagareAppGroup {
#if DEBUG
    static let identifier = "group.ilia.page.nagare.dev"
#else
    static let identifier = "group.ilia.page.nagare"
#endif
}
