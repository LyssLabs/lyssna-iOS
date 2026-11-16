import Foundation
import ObjectiveC.runtime
import Orion
import UIKit

struct LyssnaStartupBrandingGroup: HookGroup {}

/// Bind Spotify's actual startup image view. Its bounds can cover the screen,
/// so a centered-small-subview search does not reliably find the visible logo.
enum LyssnaStartupBranding {
    private static var controllerKey: UInt8 = 0
    private static var imageViewKey: UInt8 = 0
    private static let artwork: UIImage? = Bundle.main.path(forResource: "LyssnaLaunchLogo", ofType: "png")
        .flatMap { UIImage(contentsOfFile: $0) }

    private final class State {
        weak var imageView: UIImageView?
        var originalImage: UIImage?
        var originalContentMode: UIView.ContentMode = .scaleToFill
        var rendered: UIImage?
        var renderedSize = CGSize.zero
        var active = false
        var diagnosticAttempts = 0
    }

    static func apply(to controller: UIViewController) {
        guard let root = controller.viewIfLoaded, artwork != nil else { return }
        let state = objc_getAssociatedObject(controller, &controllerKey) as? State ?? {
            let value = State()
            objc_setAssociatedObject(controller, &controllerKey, value, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return value
        }()
        guard let view = nativeImageView(in: controller, root: root) else {
            if state.diagnosticAttempts < 3 {
                state.diagnosticAttempts += 1
                writeDebugLog("[Startup][branding] Waiting for native startup image view; root=\(NSStringFromClass(type(of: root)))")
            }
            return
        }
        if state.imageView !== view || !state.active {
            unbind(state)
            state.imageView = view
            state.originalImage = view.image
            state.originalContentMode = view.contentMode
            state.active = true
            state.rendered = nil
            state.renderedSize = .zero
            objc_setAssociatedObject(view, &imageViewKey, state, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            view.stopAnimating()
            view.animationImages = nil
            view.highlightedAnimationImages = nil
            writeDebugLog("[Startup][branding] Bound native lazy startup image view; bounds=\(NSCoder.string(for: view.bounds))")
        }
        refresh(view)
    }

    static func refresh(_ view: UIImageView) {
        guard let state = objc_getAssociatedObject(view, &imageViewKey) as? State, state.active,
              let image = render(for: view, state: state) else { return }
        view.contentMode = .scaleToFill
        if view.image !== image { view.image = image }
    }

    /// Restrict interception to the image view explicitly bound by our launch
    /// controller. Other UIImageViews keep their native images and layout.
    static func replacement(for view: UIImageView, incoming: UIImage?) -> UIImage? {
        guard let state = objc_getAssociatedObject(view, &imageViewKey) as? State, state.active else { return nil }
        if incoming !== state.rendered { state.originalImage = incoming }
        return render(for: view, state: state)
    }

    static func restore(_ controller: UIViewController) {
        guard let state = objc_getAssociatedObject(controller, &controllerKey) as? State else { return }
        unbind(state)
    }

    private static func unbind(_ state: State) {
        state.active = false
        if let view = state.imageView {
            objc_setAssociatedObject(view, &imageViewKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            view.contentMode = state.originalContentMode
            view.image = state.originalImage
        }
        state.rendered = nil
    }

    private static func nativeImageView(in controller: UIViewController, root: UIView) -> UIImageView? {
        // Verified in Spotify 9.2.0's ObjC class/ivar metadata. Resolve the
        // runtime offset rather than copying an offset from the input binary.
        if let ivar = class_getInstanceVariable(type(of: controller), "$__lazy_storage_$_imageView"),
           let value = object_getIvar(controller, ivar) as? UIImageView,
           value === root || value.isDescendant(of: root) { return value }
        // Include the root itself and full-screen image views; neither has to
        // satisfy an arbitrary logo-size or center-distance threshold.
        var queue = [root]
        var index = 0
        while index < queue.count, index < 128 {
            let view = queue[index]; index += 1
            if let imageView = view as? UIImageView { return imageView }
            queue += view.subviews
        }
        return nil
    }

    private static func render(for view: UIImageView, state: State) -> UIImage? {
        let size = view.bounds.size
        guard size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0, size.width <= 4096, size.height <= 4096,
              let artwork else { return nil }
        if state.renderedSize == size, let rendered = state.rendered { return rendered }
        // Keep the visible disc near the storyboard's 160pt diameter even
        // when the native UIImageView is a full-screen canvas.
        let side = min(224, min(size.width, size.height) / 0.713)
        let rect = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
        let rendered = UIGraphicsImageRenderer(size: size).image { context in
            context.cgContext.addEllipse(in: rect.insetBy(dx: side * 146 / 1024, dy: side * 146 / 1024))
            context.cgContext.clip()
            artwork.draw(in: rect)
        }.withRenderingMode(.alwaysOriginal)
        state.renderedSize = size
        state.rendered = rendered
        return rendered
    }
}

class LyssnaNativeLaunchControllerHook: ClassHook<UIViewController> {
    typealias Group = LyssnaStartupBrandingGroup
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

class LyssnaNativeLaunchImageHook: ClassHook<UIImageView> {
    typealias Group = LyssnaStartupBrandingGroup

    func setImage(_ image: UIImage?) {
        orig.setImage(LyssnaStartupBranding.replacement(for: target, incoming: image) ?? image)
    }

    func layoutSubviews() {
        orig.layoutSubviews()
        LyssnaStartupBranding.refresh(target)
    }
}

func activateLyssnaStartupBranding() {
    guard let _ = NSClassFromString(LyssnaNativeLaunchControllerHook.targetName) as? UIViewController.Type else {
        writeDebugLog("[Startup][branding] Native launch controller unavailable")
        return
    }
    LyssnaStartupBrandingGroup().activate()
    writeDebugLog("[Startup][branding] Activated native startup image binding")
}
