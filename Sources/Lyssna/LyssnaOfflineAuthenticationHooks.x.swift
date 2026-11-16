import Foundation
import Orion

// LyssnaOfflineAuthentication needs Spotify's own request headers for the offline device manager.
// The capture normally rides on the Premium bootstrap hooks (PremiumBootstrapGroup), which
// are only active on the 9.1 hook path with Premium patching on. This group repeats the
// capture alone, without touching any response, and is activated only when that group is not.
struct LyssnaOfflineAuthenticationCaptureGroup: HookGroup { }

class LyssnaOfflineDataLoaderServiceCaptureHook: ClassHook<NSObject> {
    typealias Group = LyssnaOfflineAuthenticationCaptureGroup
    static let targetName = "SPTDataLoaderService"

    func URLSession(
        _ session: URLSession,
        task: URLSessionDataTask,
        didCompleteWithError error: Error?
    ) {
        LyssnaOfflineAuthentication.capture(task.currentRequest, session: session)
        orig.URLSession(session, task: task, didCompleteWithError: error)
    }
}

class LyssnaOfflineHttpClientCaptureHook: ClassHook<NSObject> {
    typealias Group = LyssnaOfflineAuthenticationCaptureGroup
    static let targetName = "Connectivity_HttpClientKit.HttpClientURLSession"

    func URLSession(
        _ session: URLSession,
        task: URLSessionDataTask,
        didCompleteWithError error: Error?
    ) {
        LyssnaOfflineAuthentication.capture(task.currentRequest, session: session)
        orig.URLSession(session, task: task, didCompleteWithError: error)
    }
}

func activateLyssnaOfflineAuthenticationCapture() {
    // The Premium bootstrap hooks already call the capture when they are active.
    guard !(Lyssna.hookTarget == .v91 && UserDefaults.patchType.isPatching) else { return }
    LyssnaOfflineAuthenticationCaptureGroup().activate()
    writeDebugLog("[INIT] Activated LyssnaOfflineAuthenticationCaptureGroup")
}
