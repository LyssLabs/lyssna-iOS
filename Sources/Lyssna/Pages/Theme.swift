import LyssnaC
import SwiftUI
import UIKit

enum Theme {
    static let spotifyGreen: Int = 0x1ED760
    static let launchAmoled = UserDefaults.amoled
    static let launchAccent = UserDefaults.accentRGB

    static var accent: UIColor { color(accentOrGreen(launchAccent)) }

    static func accentOrGreen(_ rgb: Int) -> Int { rgb >= 0 ? rgb : spotifyGreen }

    static func color(_ rgb: Int) -> UIColor {
        UIColor(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }

    static func rgb(of color: UIColor) -> Int {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Int(round(min(max(r, 0), 1) * 255)) << 16) | (Int(round(min(max(g, 0), 1) * 255)) << 8) | Int(round(min(max(b, 0), 1) * 255))
    }
}

func activateTheme() {
    guard Theme.launchAmoled || Theme.launchAccent >= 0 else { return }
    let start = CFAbsoluteTimeGetCurrent()
    let swaps = LyssnaInstallColorSwaps(Theme.launchAmoled, Theme.launchAccent)
    lyssnaLog("[Lyssna][Theme] AMOLED %d, accent %@, %d swaps (%.2f ms)", Theme.launchAmoled,
          Theme.launchAccent >= 0 ? String(format: "#%06X", Theme.launchAccent) : "default", swaps,
          (CFAbsoluteTimeGetCurrent() - start) * 1000)
    DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
        var grey = 0, green = 0, uiColor = 0
        LyssnaColorSwapStats(&grey, &green, &uiColor)
        lyssnaLog("[Lyssna][Theme] First 30 s: %d surfaces to black, %d layer greens and %d UIColor greens to accent", grey, green, uiColor)
    }
}

extension UserDefaults {
    static var amoled: Bool {
        get { container.bool(forKey: "lyssnaAmoled") }
        set { container.set(newValue, forKey: "lyssnaAmoled") }
    }

    static var accentRGB: Int {
        get { container.object(forKey: "lyssnaAccent") as? Int ?? -1 }
        set { newValue < 0 ? container.removeObject(forKey: "lyssnaAccent") : container.set(newValue, forKey: "lyssnaAccent") }
    }
}
