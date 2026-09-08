// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

#if VORSSAINT_DEVELOPMENT
import AppKit
import SwiftUI
import QuartzCore

/// Exercises the production window host without touching preferences, files,
/// clipboard, keyboard input or hardware controls. The test window is invisible.
enum NotchPresentationProbe {
    static func runAndExit() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        guard let screen = NSScreen.main else { print("NOTCH PROBE FAILED: no display"); exit(1) }
        let geometry = NotchGeometry(screen: screen.frame, safeAreaTop: screen.safeAreaInsets.top,
                                     cameraWidth: screen.safeAreaInsets.top > 0 ? 210 : 0)
        let host = NotchWindowHost(content: AnyView(Color.black), geometry: geometry, size: geometry.collapsed)
        host.panel.alphaValue = 0
        host.panel.ignoresMouseEvents = true
        host.panel.orderFrontRegardless()
        var failures: [String] = []
        if geometry.isNotched, let mask = host.panel.contentView?.layer?.mask as? CAShapeLayer,
           let path = mask.path {
            if !path.contains(CGPoint(x: 12, y: 1))
                || path.contains(CGPoint(x: 12, y: geometry.collapsed.height - 1)) {
                failures.append("physical silhouette is inverted")
            }
        }
        var nativeResizes = 0
        let resizeObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification,
                                                                     object: host.panel, queue: nil) { _ in
            nativeResizes += 1
        }
        defer { NotificationCenter.default.removeObserver(resizeObserver) }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        var samples = 0
        var maxAnchorError: CGFloat = 0
        var maxContentError: CGFloat = 0
        var canvasChangedSize = false
        func sample() {
            samples += 1
            if host.contentCanvasSize != host.panel.frame.size { canvasChangedSize = true }
            maxAnchorError = max(maxAnchorError, abs(host.panel.frame.maxY - (screen.frame.maxY - geometry.topInset)))
            maxContentError = max(maxContentError, abs(host.contentTopOnScreen - host.panel.frame.maxY))
            if abs(host.visibleFrame.maxY - host.panel.frame.maxY) > 0.5 {
                failures.append("visible silhouette detached from window top")
            }
            if !host.panel.frame.insetBy(dx: -0.5, dy: -0.5).contains(host.visibleFrame) {
                failures.append("visible silhouette exceeded its backing area")
            }
        }
        func advance(_ seconds: TimeInterval) {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end {
                RunLoop.current.run(until: min(end, Date().addingTimeInterval(0.008)))
                sample()
            }
        }
        host.present(size: geometry.expanded, geometry: geometry, animated: true, transitionContent: .reveal)
        if !reduceMotion, host.panel.contentView?.layer?.sublayers?.first(where: { $0.name == "notch.contentCover" })?.animation(forKey: "notch.opacity") == nil {
            failures.append("opening content has no reveal transition")
        }
        advance(0.09)
        let intermediate = host.visibleFrame
        if intermediate.height <= geometry.collapsed.height || intermediate.height >= geometry.expanded.height {
            if !reduceMotion { failures.append("opening has no intermediate frames") }
        }
        if !reduceMotion {
            if host.panel.frame.size != geometry.expanded { failures.append("opening did not reserve its backing area") }
            let outside = CGPoint(x: host.panel.frame.minX + 12, y: host.panel.frame.minY + 4)
            if host.contains(outside) { failures.append("transparent transition area accepted an interaction") }
            if let canvas = host.panel.contentView {
                let point = host.panel.convertPoint(fromScreen: outside)
                if canvas.hitTest(point) != nil { failures.append("native hit testing escaped the animated silhouette") }
                let inside = CGPoint(x: intermediate.midX, y: intermediate.midY)
                if !host.contains(inside) || canvas.hitTest(host.panel.convertPoint(fromScreen: inside)) == nil {
                    failures.append("visible transition content could not receive an interaction")
                }
            }
        }
        advance(0.52)
        if nativeResizes > 2 { failures.append("opening resized its native window every frame: \(nativeResizes)") }
        let openingResizes = nativeResizes
        host.present(size: geometry.notice, geometry: geometry, animated: true, transitionContent: .dismiss)
        var completedActions = 0
        host.whenSettled { completedActions += 1 }
        if !reduceMotion, completedActions != 0 { failures.append("screen action ran before the closing transition finished") }
        let beforeBurst = host.resizeCount
        for _ in 0..<1000 { host.present(size: geometry.notice, geometry: geometry, animated: true) }
        if host.resizeCount != beforeBurst { failures.append("value burst restarted the resize") }
        advance(0.08)
        if !reduceMotion, host.panel.contentView?.layer?.sublayers?.first(where: { $0.name == "notch.contentCover" })?.opacity != 1 {
            failures.append("closing left content visible under the moving clip")
        }
        if host.panel.contentView?.subviews.first?.alphaValue != 1 {
            failures.append("closing disabled the hosting view's interaction frame")
        }
        advance(0.52)
        if host.panel.frame != geometry.frame(for: geometry.notice) { failures.append("notice did not settle") }
        if host.panel.contentView?.layer?.sublayers?.first(where: { $0.name == "notch.contentCover" })?.opacity != 0 {
            failures.append("settled content remained hidden")
        }
        if completedActions != 1 { failures.append("transition completion did not run exactly once") }
        let beforeContentTransition = nativeResizes
        host.present(size: geometry.notice, geometry: geometry, animated: true, transitionContent: .replace)
        if !reduceMotion, host.panel.contentView?.subviews.first?.layer?.animation(forKey: kCATransition) == nil {
            failures.append("same-size content changes have no transition")
        }
        if nativeResizes != beforeContentTransition { failures.append("content transition resized the window") }
        for _ in 0..<6 {
            host.present(size: geometry.expanded, geometry: geometry, animated: true)
            advance(0.04)
            let beforeReverse = host.visibleFrame
            host.present(size: geometry.collapsed, geometry: geometry, animated: true)
            if !reduceMotion, abs(beforeReverse.height - host.visibleFrame.height) > 0.5 {
                failures.append("reversing the animation jumped to an endpoint")
            }
            advance(0.04)
        }
        advance(0.60)
        if host.panel.frame != geometry.frame(for: geometry.collapsed) { failures.append("interrupted motion did not settle") }
        if maxAnchorError > 0.5 { failures.append("window detached from top: \(maxAnchorError)") }
        if canvasChangedSize { failures.append("content canvas escaped its stable native backing area") }
        if maxContentError > 0.5 { failures.append("content detached from window top: \(maxContentError)") }
        let pasteboard = NSPasteboard.withUniqueName()
        let fixture = URL(fileURLWithPath: "/tmp/notch-presentation-probe.txt")
        pasteboard.writeObjects([fixture as NSURL])
        if host.beginProbeDrop(pasteboard) != [] { failures.append("disabled file target accepted a drop") }
        var entered = 0
        var accepted = 0
        host.setFileDropActions(NotchFileDropActions(
            canAccept: { $0.availableType(from: [.fileURL]) != nil },
            enter: { entered += 1; host.present(size: geometry.expanded, geometry: geometry, animated: true) },
            accept: { board in
                guard board.string(forType: .fileURL) == fixture.absoluteString else { return false }
                accepted += 1
                return true
            }, exit: {}))
        if host.beginProbeDrop(pasteboard, localSource: true) != [] { failures.append("file target stole an internal reorder") }
        if host.beginProbeDrop(pasteboard) != .copy { failures.append("file URL was refused") }
        advance(0.07)
        if !host.finishProbeDrop(pasteboard) || accepted != 1 || entered != 1 {
            failures.append("drop was lost while the native window expanded")
        }
        if host.finishProbeDrop(pasteboard) { failures.append("one drag was accepted twice") }
        host.setFileDropActions(nil)
        if host.beginProbeDrop(pasteboard) != [] { failures.append("disabled target retained its drop handler") }
        pasteboard.releaseGlobally()
        host.present(size: geometry.peek, geometry: geometry, animated: false)
        if host.panel.frame != geometry.frame(for: geometry.peek)
            || host.panel.contentView?.layer?.mask?.animation(forKey: "notch.resize") != nil {
            failures.append("immediate presentation retained an animation")
        }
        host.present(size: geometry.expanded, geometry: geometry, animated: true)
        host.whenSettled { completedActions += 1 }
        host.close()
        advance(0.02)
        if completedActions != 2 || host.panel.isVisible { failures.append("closing the host lost a pending action or reopened the window") }
        print("NOTCH PROBE \(failures.isEmpty ? "OK" : "FAILED") samples=\(samples) openingNativeResizes=\(openingResizes) repeatedUpdates=1000 fileDrops=\(accepted) topError=\(maxAnchorError) contentError=\(maxContentError)")
        failures.forEach { print($0) }
        exit(failures.isEmpty ? 0 : 1)
    }
}
#endif
