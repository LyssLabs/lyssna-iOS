import Orion
import StoreKit

struct RatingPromptBlockGroup: HookGroup {}

class StoreReviewHook: ClassHook<SKStoreReviewController> {
    typealias Group = RatingPromptBlockGroup

    class func requestReview() {
        RatingPromptBlock.blocked("requestReview")
    }

    class func requestReviewInScene(_ scene: UIWindowScene) {
        RatingPromptBlock.blocked("requestReviewInScene")
    }
}

enum RatingPromptBlock {
    static let launchEnabled = UserDefaults.blockRatingPrompts
    private static var count = 0

    static func blocked(_ method: String) {
        count += 1
        lyssnaLog("[Lyssna][Privacy] Blocked rating prompt (%@, %d total)", method, count)
    }
}

extension UserDefaults {
    static var blockRatingPrompts: Bool {
        get { container.bool(forKey: "lyssnaBlockRatingPrompts") }
        set { container.set(newValue, forKey: "lyssnaBlockRatingPrompts") }
    }
}

func activateRatingPromptBlock() {
    guard RatingPromptBlock.launchEnabled else { return }
    let start = CFAbsoluteTimeGetCurrent()
    RatingPromptBlockGroup().activate()
    lyssnaLog("[Lyssna][Privacy] Rating prompt block on (%.2f ms)", (CFAbsoluteTimeGetCurrent() - start) * 1000)
}
