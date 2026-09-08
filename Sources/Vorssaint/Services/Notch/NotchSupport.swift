// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import CoreGraphics

enum NotchModule: String, CaseIterable, Identifiable {
    case controls, mixer, music, clipboard, captures, files, system, tools
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .controls: return "slider.horizontal.3"
        case .mixer: return "slider.vertical.3"
        case .music: return "music.note"
        case .clipboard: return "doc.on.clipboard"
        case .captures: return "camera.viewfinder"
        case .files: return "tray.full"
        case .system: return "gauge.with.dots.needle.50percent"
        case .tools: return "square.grid.2x2"
        }
    }

    func isAvailable(in defaults: UserDefaults = .standard) -> Bool {
        switch self {
        case .controls, .music: return true
        case .mixer: return AppFeature.mixer.isAvailable(in: defaults)
        case .tools: return AppFeature.quickLauncher.isAvailable(in: defaults)
        case .clipboard: return AppFeature.clipboardHistory.isAvailable(in: defaults)
        case .captures:
            return AppFeature.screenshot.isAvailable(in: defaults)
                || AppFeature.screenRecorder.isAvailable(in: defaults)
                || AppFeature.screenOCR.isAvailable(in: defaults)
                || AppFeature.colorPicker.isAvailable(in: defaults)
        case .files: return AppFeature.shelf.isAvailable(in: defaults)
        case .system:
            return [.monitorCPU, .monitorGPU, .monitorMemory, .monitorNetwork,
                    .monitorDisk, .monitorPower].contains { (feature: AppFeature) in
                feature.isAvailable(in: defaults)
            }
        }
    }
}

enum NotchDisplay: String, CaseIterable {
    case automatic, builtIn, main
}

enum NotchSize: String, CaseIterable {
    case compact, spacious, custom

    static let widthRange = 360.0...600.0
    static let heightRange = 400.0...640.0
    static let defaultWidth = 440.0
    static let defaultHeight = 480.0

    static func clamped(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }
}

enum NotchIdleContent: String, CaseIterable {
    case none, battery, music, controls
}

enum NotchControlItem: String, CaseIterable, Identifiable {
    case volume, brightness, keepAwake, microphone, screenshot, recording, speedTest, panel, mixer, commandBar
    var id: String { rawValue }

    func isAvailable(in defaults: UserDefaults = .standard) -> Bool {
        switch self {
        case .volume: return AppFeature.mixer.isAvailable(in: defaults)
        case .mixer: return AppFeature.mixer.isAvailable(in: defaults) && NotchSupport.modules(in: defaults).contains(.mixer)
        case .brightness: return AppFeature.brightness.isAvailable(in: defaults)
        case .keepAwake: return AppFeature.keepAwake.isAvailable(in: defaults)
        case .microphone: return AppFeature.micMute.isAvailable(in: defaults)
        case .screenshot: return AppFeature.screenshot.isAvailable(in: defaults)
        case .recording: return AppFeature.screenRecorder.isAvailable(in: defaults)
        case .speedTest: return AppFeature.monitorNetwork.isAvailable(in: defaults) && NotchSupport.modules(in: defaults).contains(.system)
        case .commandBar: return AppFeature.commandBar.isAvailable(in: defaults)
        case .panel: return true
        }
    }
}

enum NotchEvent: String, CaseIterable {
    case volume, brightness, battery, clipboard, capture

    var preferenceKey: String {
        switch self {
        case .volume: return DefaultsKey.notchVolume
        case .brightness: return DefaultsKey.notchBrightness
        case .battery: return DefaultsKey.notchBattery
        case .clipboard: return DefaultsKey.notchClipboard
        case .capture: return DefaultsKey.notchCapture
        }
    }

    var priority: Int {
        switch self {
        case .volume, .brightness: return 3
        case .capture: return 2
        case .battery: return 1
        case .clipboard: return 0
        }
    }

    var duration: TimeInterval {
        switch self {
        case .volume, .brightness: return 1.6
        case .battery: return 4
        case .clipboard: return 2.5
        case .capture: return 12
        }
    }
}

enum NotchSupport {
    static let toolColumns = 5
    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        AppFeature.notch.isAvailable(in: defaults)
            && defaults.bool(forKey: DefaultsKey.notchEnabled)
    }

    static func usesHapticFeedback(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchHapticFeedback)
    }

    static func modules(in defaults: UserDefaults = .standard) -> [NotchModule] {
        let hidden = Set((defaults.string(forKey: DefaultsKey.notchHiddenModules) ?? "")
            .split(separator: ",").map(String.init))
        let stored = (defaults.string(forKey: DefaultsKey.notchModuleOrder) ?? "")
            .split(separator: ",").compactMap { NotchModule(rawValue: String($0)) }
        var seen = Set<NotchModule>()
        return (stored + NotchModule.allCases).filter {
            seen.insert($0).inserted && !hidden.contains($0.rawValue) && $0.isAvailable(in: defaults)
        }
    }

    static func watchesMusicActivity(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && modules(in: defaults).contains(.music)
            && (defaults.object(forKey: DefaultsKey.notchShowPlayingMusic) as? Bool ?? true)
    }

    static func showsMusicActivity(isPlaying: Bool, in defaults: UserDefaults = .standard) -> Bool {
        isPlaying && watchesMusicActivity(in: defaults)
    }

    static func showsInCaptures(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: DefaultsKey.notchShowInCaptures) as? Bool ?? true
    }

    static func idleContent(in defaults: UserDefaults = .standard) -> NotchIdleContent {
        let choice = NotchIdleContent(rawValue: defaults.string(forKey: DefaultsKey.notchIdleContent) ?? "") ?? .none
        if choice == .battery, !AppFeature.monitorPower.isAvailable(in: defaults) { return .none }
        if choice == .music, !modules(in: defaults).contains(.music) { return .none }
        return choice
    }

    static func controls(in defaults: UserDefaults = .standard) -> [NotchControlItem] {
        let hidden = Set((defaults.string(forKey: DefaultsKey.notchHiddenControls) ?? "")
            .split(separator: ",").map(String.init))
        let stored = (defaults.string(forKey: DefaultsKey.notchControlOrder) ?? "")
            .split(separator: ",").compactMap { NotchControlItem(rawValue: String($0)) }
        var seen = Set<NotchControlItem>()
        return (stored + NotchControlItem.allCases).filter {
            seen.insert($0).inserted && !hidden.contains($0.rawValue) && $0.isAvailable(in: defaults)
        }
    }

    /// Direct openings are dismissed explicitly, never by the pointer's
    /// initial position at the menu bar or in the application being used.
    static func closesOnPointerExit(expanded: Bool, peeking: Bool, openedByHover: Bool) -> Bool {
        peeking || (expanded && openedByHover)
    }

    static func routes(_ event: NotchEvent, in defaults: UserDefaults = .standard) -> Bool {
        guard isEnabled(in: defaults), defaults.bool(forKey: event.preferenceKey) else { return false }
        switch event {
        case .volume: return AppFeature.mixer.isAvailable(in: defaults)
        case .brightness:
            return AppFeature.brightness.isAvailable(in: defaults)
                && defaults.bool(forKey: DefaultsKey.brightnessControlEnabled)
        case .battery: return AppFeature.monitorPower.isAvailable(in: defaults)
        case .clipboard:
            return modules(in: defaults).contains(.clipboard)
                && defaults.bool(forKey: DefaultsKey.clipboardHistoryEnabled)
        case .capture:
            return AppFeature.screenshot.isAvailable(in: defaults)
                && modules(in: defaults).contains(.captures)
        }
    }

    static func routesClipboardWindow(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchClipboardWindow)
            && modules(in: defaults).contains(.clipboard)
    }

    static func routesShelf(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchShelf)
            && modules(in: defaults).contains(.files)
    }

    static func revealsShelfDrag(in defaults: UserDefaults = .standard) -> Bool {
        routesShelf(in: defaults) && defaults.bool(forKey: DefaultsKey.notchDragReveal)
    }

    static func routesCaptureControls(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchCaptureControls)
            && modules(in: defaults).contains(.captures)
    }

    static func routesQuickPanel(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchQuickPanel)
            && AppFeature.quickLauncher.isAvailable(in: defaults)
            && modules(in: defaults).contains(.tools)
    }

    static func routesAppPanel(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchAppPanel)
    }

    static func shouldReplace(_ current: NotchEvent?, with incoming: NotchEvent) -> Bool {
        current == nil || incoming.priority >= current!.priority
    }

    static func volumeLevel(current: Double, direction: Int, fine: Bool) -> Double {
        guard current.isFinite else { return 0 }
        return min(1, max(0, current + Double(direction.signum()) / (fine ? 64 : 16)))
    }

    static func screenIndex(preference: NotchDisplay, builtIn: [Bool], notched: [Bool], main: Int) -> Int? {
        guard !builtIn.isEmpty, builtIn.count == notched.count else { return nil }
        let fallback = builtIn.indices.contains(main) ? main : 0
        switch preference {
        case .main: return fallback
        case .builtIn: return builtIn.firstIndex(of: true) ?? fallback
        case .automatic:
            return builtIn.indices.first { builtIn[$0] && notched[$0] }
                ?? notched.firstIndex(of: true) ?? fallback
        }
    }
}

/// Screen coordinates stay in points, including displays to the left or above
/// the primary display. No model name or pixel density is assumed.
struct NotchGeometry: Equatable {
    let screen: CGRect
    let cameraWidth: CGFloat
    let cameraHeight: CGFloat
    let isNotched: Bool
    let layout: NotchSize
    let customWidth: CGFloat
    let customHeight: CGFloat
    let menuBarHeight: CGFloat
    var compactSideRoom: CGFloat?

    init(screen: CGRect, safeAreaTop: CGFloat, cameraWidth: CGFloat, layout: NotchSize = .compact,
         menuBarHeight: CGFloat = 24, compactSideRoom: CGFloat? = nil,
         customWidth: Double = NotchSize.defaultWidth, customHeight: Double = NotchSize.defaultHeight) {
        self.screen = screen
        self.layout = layout
        self.customWidth = NotchSize.clamped(customWidth, to: NotchSize.widthRange, fallback: NotchSize.defaultWidth)
        self.customHeight = NotchSize.clamped(customHeight, to: NotchSize.heightRange, fallback: NotchSize.defaultHeight)
        isNotched = safeAreaTop.isFinite && safeAreaTop > 0 && cameraWidth.isFinite && cameraWidth > 0
        self.cameraWidth = isNotched ? min(cameraWidth, screen.width * 0.7) : 100
        cameraHeight = isNotched ? min(safeAreaTop, 64) : 0
        self.menuBarHeight = max(cameraHeight, menuBarHeight.isFinite ? min(64, max(16, menuBarHeight)) : 24)
        self.compactSideRoom = compactSideRoom
    }

    var topInset: CGFloat { 0 }
    var safeContentTop: CGFloat { isNotched ? cameraHeight + 10 : 14 }
    var restingWingWidth: CGFloat {
        let available = min(44, max(0, compactSideRoom ?? 0)).rounded(.down)
        return available >= 44 ? available : 0
    }
    var collapsed: CGSize {
        CGSize(width: min(screen.width - 24, cameraWidth + restingWingWidth * 2), height: menuBarHeight)
    }
    func restingSize(showsContent: Bool) -> CGSize {
        showsContent ? collapsed : CGSize(width: cameraWidth, height: isNotched ? cameraHeight : menuBarHeight)
    }
    var musicCameraGap: CGFloat { cameraWidth }
    var musicStrip: CGSize {
        let preferred = min(layout == .spacious ? 520 : 440, screen.width - 24)
        let room = max(0, compactSideRoom ?? 0).rounded(.down)
        let wings = room >= 36 ? room * 2 : 0
        return CGSize(width: max(cameraWidth, min(preferred, cameraWidth + wings)), height: menuBarHeight)
    }
    var musicWingWidth: CGFloat { max(0, (musicStrip.width - musicCameraGap) / 2) }
    var notice: CGSize {
        CGSize(width: min(screen.width - 24, max(cameraWidth + 160, 360)),
               height: safeContentTop + 58)
    }
    var peek: CGSize {
        CGSize(width: min(screen.width - 24, max(cameraWidth + 110, 320)), height: safeContentTop + 42)
    }
    var expanded: CGSize { expandedSize(module: .controls) }
    var expandedWidth: CGFloat {
        let preferred: CGFloat
        switch layout {
        case .compact: preferred = 380
        case .spacious: preferred = 520
        case .custom: preferred = customWidth
        }
        return min(max(preferred, cameraWidth + 36), screen.width - 24)
    }
    var usesCompactContent: Bool { expandedWidth < 480 }

    func expandedSize(module: NotchModule, detail: Bool = false, controlRows: Int = 2,
                      sliderCount: Int = 2, musicHasContent: Bool = true) -> CGSize {
        let contentHeight: CGFloat
        switch module {
        case .controls:
            let rows = max(0, controlRows)
            let sliders = min(2, max(0, sliderCount))
            let groups = sliders + (rows > 0 ? 1 : 0)
            let controls = CGFloat(sliders) * 48 + CGFloat(rows) * 54
                + CGFloat(max(0, rows - 1)) * 8 + CGFloat(max(0, groups - 1)) * 12
            contentHeight = 96 + (groups == 0 ? 160 : controls + 2)
        case .mixer: contentHeight = 400
        case .music: contentHeight = musicHasContent ? (usesCompactContent ? 334 : 374) : 238
        case .system: contentHeight = 324
        case .files: contentHeight = 336
        case .clipboard, .captures: contentHeight = 340
        case .tools: contentHeight = 400
        }
        let fillsHeight = detail || [.mixer, .clipboard, .captures, .tools].contains(module)
        var preferredHeight = safeContentTop + (detail ? 440 : contentHeight)
            + (layout == .spacious && module != .controls && module != .music ? 40 : 0)
        if layout == .custom {
            preferredHeight = fillsHeight ? customHeight : min(preferredHeight, customHeight)
        }
        return CGSize(width: expandedWidth,
                      height: min(preferredHeight, screen.height - topInset - 48))
    }
    func contentSize(for size: CGSize, navigation: Bool) -> CGSize {
        CGSize(width: size.width - 36,
               height: size.height - safeContentTop - 24 - 10 - 14 - (navigation ? 48 : 0))
    }
    var appPanelSize: CGSize { contentSize(for: expandedSize(module: .tools), navigation: false) }
    func frame(for size: CGSize) -> CGRect {
        CGRect(x: screen.midX - size.width / 2,
               y: screen.maxY - topInset - size.height,
               width: size.width, height: size.height)
    }
}

struct NotchSessionState {
    var locked = false
    var sleeping = false
    var displaysSleeping = false
    var onConsole = true
    var canPresent: Bool { !locked && !sleeping && !displaysSleeping && onConsole }
}

/// Reserve enough backing space for both ends. The visible silhouette moves
/// inside it; the native window only shrinks after the transition finishes.
enum NotchMotion {
    static func envelope(from: CGSize, to: CGSize) -> CGSize {
        CGSize(width: max(from.width, to.width), height: max(from.height, to.height))
    }
}

/// Free room on both sides of the camera, in Cocoa screen coordinates.
/// Unknown/occupied camera space is distinct from a known zero-width wing.
enum NotchMenuBarLayout {
    static func sideRoom(screen: CGRect, cameraWidth: CGFloat, barHeight: CGFloat,
                         occupied: [CGRect]) -> CGFloat? {
        let bar = CGRect(x: screen.minX, y: screen.maxY - barHeight, width: screen.width, height: barHeight)
        let camera = CGRect(x: screen.midX - cameraWidth / 2, y: bar.minY,
                            width: cameraWidth, height: barHeight)
        var left = screen.minX + 8
        var right = screen.maxX - 8
        for rect in occupied where rect.intersects(bar) {
            guard rect.minX.isFinite, rect.maxX.isFinite, rect.width > 0 else { return nil }
            if rect.intersects(camera) { return nil }
            if rect.maxX <= camera.minX { left = max(left, rect.maxX + 8) }
            if rect.minX >= camera.maxX { right = min(right, rect.minX - 8) }
        }
        return max(0, min(camera.minX - left, right - camera.maxX))
    }
}
