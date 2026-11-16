import Foundation
import ObjectiveC.runtime
import Orion
import UIKit

struct LyssnaStartupBrandingGroup: HookGroup {}

/// Spotify presents a native startup controller after the system launch screen.
/// Replace only its centered logo, retaining the controller's loading lifecycle.
enum LyssnaStartupBranding {
    private static var stateKey: UInt8 = 0
    private static let image: UIImage? = Bundle.main.path(forResource: "LyssnaLaunchLogo", ofType: "png")
        .flatMap { UIImage(contentsOfFile: $0) }

    private final class State {
        weak var native: UIView?
        var originalAlpha: CGFloat = 1
        var diagnosticAttempts = 0
        let replacement = UIImageView()
        let mask = CAShapeLayer()
    }

    static func apply(to controller: UIViewController) {
        guard let root = controller.viewIfLoaded, root.bounds.width > 0, let image else { return }
        let state = objc_getAssociatedObject(controller, &stateKey) as? State ?? {
            let value = State()
            objc_setAssociatedObject(controller, &stateKey, value, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return value
        }()
        if state.native?.isDescendant(of: root) != true {
            state.native?.alpha = state.originalAlpha
            guard let native = logo(in: root, excluding: state.replacement) else {
                state.replacement.removeFromSuperview()
                if state.diagnosticAttempts < 3 {
                    state.diagnosticAttempts += 1
                    let children = root.subviews.prefix(6).map { "\(NSStringFromClass(type(of: $0))):\(NSCoder.string(for: $0.bounds))" }
                    writeDebugLog("[Startup][branding] Awaiting native logo; children=\(children.joined(separator: ", "))")
                }
                return
            }
            state.native = native
            state.originalAlpha = native.alpha
            state.replacement.image = image
            state.replacement.contentMode = .scaleAspectFit
            state.replacement.isUserInteractionEnabled = false
            state.replacement.accessibilityElementsHidden = true
            state.replacement.layer.mask = state.mask
            writeDebugLog("[Startup][branding] Replaced native launch logo: \(NSStringFromClass(type(of: native)))")
        }
        guard let native = state.native else { return }
        let nativeFrame = native.convert(native.bounds, to: root)
        native.alpha = 0
        if state.replacement.superview !== root { root.addSubview(state.replacement) }
        root.bringSubviewToFront(state.replacement)
        let side = min(max(0, root.bounds.width - 48), max(224, min(320, nativeFrame.width / 0.713)))
        state.replacement.frame = CGRect(x: nativeFrame.midX - side / 2, y: nativeFrame.midY - side / 2,
                                         width: side, height: side)
        // Exclude the PNG's dark square, preserving only the green foreground disc.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        state.mask.frame = state.replacement.bounds
        let inset = side * 146 / 1024
        state.mask.path = UIBezierPath(ovalIn: state.replacement.bounds.insetBy(dx: inset, dy: inset)).cgPath
        CATransaction.commit()
    }

    static func restore(_ controller: UIViewController) {
        guard let state = objc_getAssociatedObject(controller, &stateKey) as? State else { return }
        state.native?.alpha = state.originalAlpha
        state.replacement.removeFromSuperview()
    }

    private static func logo(in root: UIView, excluding replacement: UIView) -> UIView? {
        var queue = root.subviews
        var index = 0
        var best: UIView?
        var score: CGFloat = -1
        while index < queue.count, index < 256 {
            let view = queue[index]; index += 1
            guard view !== replacement else { continue }
            queue += view.subviews
            let size = view.bounds.size
            guard !view.isHidden, size.width >= 40, size.height >= 40,
                  size.width <= 320, size.height <= 320,
                  size.width / size.height > 0.65, size.width / size.height < 1.5 else { continue }
            let name = NSStringFromClass(type(of: view)).lowercased()
            let branded = name.contains("logo") || name.contains("encoreicon")
            guard branded || view is UIImageView else { continue }
            let rect = view.convert(view.bounds, to: root)
            guard abs(rect.midX - root.bounds.midX) < root.bounds.width * 0.25,
                  abs(rect.midY - root.bounds.midY) < root.bounds.height * 0.25 else { continue }
            let candidate = (branded ? 1000 : 0) + min(size.width, size.height)
            if candidate > score { best = view; score = candidate }
        }
        return best
    }
}

class LyssnaNativeLaunchControllerHook: ClassHook<UIViewController> {
    typealias Group = LyssnaStartupBrandingGroup
    // Verified in the Spotify 9.2.0 binary, separate from LaunchScreen.storyboardc.
    static let targetName = "_TtC30ContainerUI_RootUIInternalImpl20LaunchViewController"

    func viewDidLoad() {
        orig.viewDidLoad()
        LyssnaStartupBranding.apply(to: target)
    }

    func viewDidLayoutSubviews() {
        orig.viewDidLayoutSubviews()
        LyssnaStartupBranding.apply(to: target)
    }

    func viewDidDisappear(_ animated: Bool) {
        orig.viewDidDisappear(animated)
        LyssnaStartupBranding.restore(target)
    }
}

func activateLyssnaStartupBranding() {
    guard NSClassFromString(LyssnaNativeLaunchControllerHook.targetName) is UIViewController.Type else {
        writeDebugLog("[Startup][branding] Native launch controller unavailable")
        return
    }
    LyssnaStartupBrandingGroup().activate()
}
