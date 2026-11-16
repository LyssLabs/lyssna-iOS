//
//  LyssnaFlex.x.swift
//
//  Auto-opens FLEX explorer on first key window. Dormant unless libFLEX.dylib
//  is LC-loaded into the app (wrapper --flex flag). Safe to keep compiled in.
//
import Foundation
import Orion
import UIKit

struct LyssnaFlexAutoOpenGroup: HookGroup {}

private var flexAutoOpenedOnce = false

class UIWindowFlexAutoOpenHook: ClassHook<UIWindow> {
    typealias Group = LyssnaFlexAutoOpenGroup

    func becomeKeyWindow() {
        orig.becomeKeyWindow()

        guard !flexAutoOpenedOnce else { return }
        guard let mgrClass = NSClassFromString("FLEXManager") as? NSObject.Type else { return }
        let sharedSel = NSSelectorFromString("sharedManager")
        guard mgrClass.responds(to: sharedSel) else { return }
        guard let mgr = mgrClass.perform(sharedSel)?.takeUnretainedValue() as? NSObject else { return }
        let showSel = NSSelectorFromString("showExplorer")
        guard mgr.responds(to: showSel) else { return }

        flexAutoOpenedOnce = true
        NSLog("[LyssnaFlex] key window up — scheduling showExplorer")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            mgr.perform(showSel)
            NSLog("[LyssnaFlex] showExplorer invoked")
        }
    }
}

func activateLyssnaFlexGesture() {
    guard NSClassFromString("FLEXManager") != nil else {
        NSLog("[LyssnaFlex] libFLEX NOT loaded — auto-open dormant (run without --skip-build to bake libFLEX into baseline)")
        return
    }
    NSLog("[LyssnaFlex] libFLEX loaded — auto-open armed")
    LyssnaFlexAutoOpenGroup().activate()
}
