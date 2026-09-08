// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import IOKit.ps
import SwiftUI

struct NotchNotice: Equatable {
    let event: NotchEvent
    let title: String
    let detail: String
    let symbol: String
    var level: Double? = nil
}

/// Owns presentation only. Clipboard, files, captures, audio and metrics keep
/// their original owners, gates and privacy rules.
final class NotchService: ObservableObject {
    static let shared = NotchService()

    @Published private(set) var geometry = NotchGeometry(
        screen: CGRect(x: 0, y: 0, width: 1440, height: 900), safeAreaTop: 0, cameraWidth: 0)
    @Published private(set) var expanded = false
    @Published private(set) var peeking = false
    @Published private(set) var dragPlaceholder = false
    @Published private(set) var selectedMetric: MetricDetailKind?
    @Published private(set) var captureControls: ScreenCaptureSelectionOptions?
    @Published var pinned = false
    @Published private(set) var selected: NotchModule = .controls
    @Published private(set) var showingAppPanel = false
    @Published private(set) var modules: [NotchModule] = []
    @Published private(set) var notice: NotchNotice?
    @Published private(set) var captureContent: AnyView?
    @Published private(set) var power = PowerReading()

    private var windowHost: NotchWindowHost?
    private var panel: NotchPanel? { windowHost?.panel }
    private var captureControlsCancel: (() -> Void)?
    private var captureControlsSubscription: AnyCancellable?
    private var heldDrag = false
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var subscriptions = Set<AnyCancellable>()
    private var eventMonitors: [Any] = []
    private var hoverWork: DispatchWorkItem?
    private var noticeWork: DispatchWorkItem?
    private var powerSource: CFRunLoopSource?
    private var powerSampler: PowerSampler?
    private var captureID: UUID?
    private var captureFallback: (() -> Void)?
    private var captureClose: (() -> Void)?
    private var captureHover: ((Bool) -> Void)?
    private var inside = false
    private var openedByHover = false
    private var trackingMenu = false
    private var keepsWorkingSurface: Bool {
        pinned || trackingMenu || NSApp.modalWindow != nil || panel?.attachedSheet != nil
            || (expanded && selected == .tools && (QuickLauncherService.shared.activeUtility != nil || QuickLauncherService.shared.isEditing))
    }
    private var running = false
    private var session = NotchSessionState()
    private var suspended: Bool { !session.canPresent }
    private var settingsSignature = ""
    private var volumeBaseline: Double?
    private var muteBaseline: Bool?
    private var notchNeedsMonitor = false
    private var menuSpaceTimer: Timer?
    private var menuSpaceReading = false
    private var menuSpaceGeneration = 0
    private let menuSpaceQueue = DispatchQueue(label: "com.vorssaint.notch-menu-space", qos: .utility)

    private init() {}

    var idleContent: NotchIdleContent { NotchSupport.idleContent() }

    var hasMusicActivity: Bool {
        NotchSupport.showsMusicActivity(isPlaying: NotchMusicService.shared.playback?.isPlaying == true)
    }

    var expandedSize: CGSize {
        let controls = NotchSupport.controls()
        let sliders = controls.filter { $0 == .volume || $0 == .brightness }.count
        let shortcuts = controls.count - sliders
        return geometry.expandedSize(module: showingAppPanel ? .tools : selected,
                                     detail: selectedMetric != nil, controlRows: (shortcuts + 2) / 3,
                                     sliderCount: sliders, musicHasContent: NotchMusicService.shared.playback != nil)
    }
    var contentSize: CGSize { geometry.contentSize(for: expandedSize, navigation: !showingAppPanel && selectedMetric == nil) }
    var surfaceSize: CGSize {
        if let captureControls {
            return CGSize(width: geometry.expanded.width,
                          height: geometry.safeContentTop + (captureControls.selectedTool == .recording ? 158 : 112))
        }
        if expanded { return expandedSize }
        if dragPlaceholder { return CGSize(width: geometry.peek.width, height: geometry.safeContentTop + 66) }
        if notice != nil { return geometry.notice }
        if peeking { return geometry.peek }
        if hasMusicActivity { return geometry.musicStrip }
        return geometry.restingSize(showsContent: idleContent != .none)
    }

    var presentationWindow: NSPanel? { panel }
    var acceptsSystemFeedback: Bool { running && !suspended && panel != nil }

    var protectedWindowIDs: Set<CGWindowID> {
        guard !NotchSupport.showsInCaptures(),
              let panel, panel.isVisible, panel.windowNumber > 0 else { return [] }
        return [CGWindowID(panel.windowNumber)]
    }

    var captureVisibleWindowIDs: Set<CGWindowID> {
        guard NotchSupport.showsInCaptures(), let panel, panel.isVisible,
              panel.windowNumber > 0 else { return [] }
        return [CGWindowID(panel.windowNumber)]
    }

    func syncWithPreferences() {
        guard NotchSupport.isEnabled() else { stop(); return }
        if !running {
            running = true
            installObservers()
        }
        guard !suspended else { return }
        refreshModules()
        updateScreen()
        let signature = NotchEvent.allCases.map { String(NotchSupport.routes($0)) }.joined()
            + idleContent.rawValue + String(NotchSupport.watchesMusicActivity())
            + modules.map(\.rawValue).joined()
            + String(NotchSupport.routesShelf()) + String(NotchSupport.revealsShelfDrag())
            + String(NotchSupport.routesCaptureControls())
        if signature != settingsSignature {
            settingsSignature = signature
            bindEvents()
            if AppFeature.shelf.isAvailable { ShelfService.shared.syncWithPreferences() }
        }
        if !NotchSupport.routes(.capture), captureContent != nil {
            let fallback = captureFallback
            clearCapture()
            fallback?()
        }
        if captureControls != nil, !NotchSupport.routesCaptureControls() { cancelCaptureControls() }
        if let notice, !NotchSupport.routes(notice.event) { dismissNotice() }
        syncVisibleConsumers()
        refreshPresentation(animated: false)
        if AppFeature.mixer.isAvailable { PreciseVolumeRollerService.shared.syncWithPreferences() }
        if AppFeature.brightness.isAvailable { BrightnessService.shared.syncWithPreferences() }
    }

    private func refreshModules() {
        let updated = NotchSupport.modules()
        if modules != updated { modules = updated }
        let selection = modules.contains(selected) ? selected : modules.first ?? .controls
        if selected != selection { selected = selection }
    }

    func stop(restoreCapture: Bool = true) {
        guard running else { return }
        running = false
        let cancelCapture = captureControlsCancel
        endCaptureControls()
        cancelCapture?()
        let fallback = restoreCapture ? captureFallback : captureClose
        clearCapture()
        tearDownPresentation()
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
        session = NotchSessionState()
        if AppFeature.mixer.isAvailable { PreciseVolumeRollerService.shared.syncWithPreferences() }
        if AppFeature.brightness.isAvailable { BrightnessService.shared.syncWithPreferences() }
        if AppFeature.shelf.isAvailable { ShelfService.shared.syncWithPreferences() }
        fallback?()
    }

    private func tearDownPresentation() {
        stopMenuSpaceMonitoring()
        geometry.compactSideRoom = nil
        hoverWork?.cancel(); hoverWork = nil
        noticeWork?.cancel(); noticeWork = nil
        subscriptions.removeAll()
        stopPower()
        NotchMusicService.shared.stop()
        settingsSignature = ""
        expanded = false
        peeking = false
        dragPlaceholder = false
        heldDrag = false
        selectedMetric = nil
        pinned = false
        notice = nil
        showingAppPanel = false
        inside = false
        openedByHover = false
        removeEventMonitors()
        releaseMonitor()
        windowHost?.close()
        windowHost = nil
    }

    func open(_ module: NotchModule? = nil, pinned: Bool = false, takeFocus: Bool = true,
              appPanel: Bool = false, metric: MetricDetailKind? = nil, feedback: Bool = true) {
        guard NotchSupport.isEnabled(), !suspended else { return }
        if !running || self.panel == nil { syncWithPreferences() }
        else { refreshModules() }
        guard let panel else { return }
        let destination = module.flatMap { modules.contains($0) ? $0 : nil } ?? selected
        let changesPresentation = !expanded || selected != destination
            || showingAppPanel != appPanel || selectedMetric != metric
        (NSApp.delegate as? AppDelegate)?.closePopover(preservingNotch: true)
        if !expanded, modules.contains(.clipboard) { ClipboardHistoryService.shared.rememberPasteTarget() }
        panel.acceptsKeyFocus = true
        hoverWork?.cancel()
        mutatePresentation(transitionContent: changesPresentation ? (expanded ? .replace : .reveal) : .none) {
            showingAppPanel = appPanel
            if selected != destination { selected = destination }
            if pinned { self.pinned = true }
            selectedMetric = metric
            peeking = false
            openedByHover = !takeFocus
            expanded = true
        }
        inside = geometry.frame(for: expandedSize).contains(NSEvent.mouseLocation)
        installEventMonitors()
        syncVisibleConsumers()
        if takeFocus { panel.makeKey() }
        if feedback, changesPresentation { provideHapticFeedback() }
    }

    func collapse() {
        guard captureControls == nil, !heldDrag else { return }
        pinned = false
        hoverWork?.cancel(); hoverWork = nil
        mutatePresentation(transitionContent: expanded || peeking ? .dismiss : .none) {
            geometry.compactSideRoom = nil
            expanded = false
            openedByHover = false
            peeking = false
            selectedMetric = nil
            showingAppPanel = false
        }
        panel?.acceptsKeyFocus = false
        panel?.resignKey()
        removeEventMonitors()
        syncVisibleConsumers()
    }

    func toggle() { expanded ? collapse() : open() }

    @discardableResult
    func showClipboard(toggle: Bool = false) -> Bool {
        guard running, !suspended, NotchSupport.routesClipboardWindow() else { return false }
        if toggle, expanded, selected == .clipboard, !showingAppPanel { collapse() }
        else { open(.clipboard) }
        return true
    }

    func hover(_ entered: Bool) {
        inside = entered
        captureHover?(entered)
        hoverWork?.cancel(); hoverWork = nil
        guard !pinned, captureControls == nil, !heldDrag, !keepsWorkingSurface else { return }
        if entered {
            guard !expanded, !peeking, !dragPlaceholder,
                  UserDefaults.standard.bool(forKey: DefaultsKey.notchOpenOnHover) else { return }
            if hasMusicActivity, geometry.musicWingWidth > 0,
               !UserDefaults.standard.bool(forKey: DefaultsKey.notchHoverExpands) { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.inside, self.captureControls == nil else { return }
                if UserDefaults.standard.bool(forKey: DefaultsKey.notchHoverExpands) {
                    self.open(self.hasMusicActivity ? NotchModule.music : nil, takeFocus: false)
                } else {
                    self.mutatePresentation(transitionContent: .reveal) { self.peeking = true }
                    self.provideHapticFeedback()
                }
            }
            hoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
        } else if NotchSupport.closesOnPointerExit(expanded: expanded, peeking: peeking, openedByHover: openedByHover) {
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.inside, !self.pinned, !self.heldDrag, !self.keepsWorkingSurface,
                      NotchSupport.closesOnPointerExit(expanded: self.expanded, peeking: self.peeking, openedByHover: self.openedByHover) else { return }
                self.collapse()
            }
            hoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20, execute: work)
        }
    }

    func select(_ module: NotchModule) {
        guard modules.contains(module) else { return }
        open(module)
    }

    func openAppPanel(toggle: Bool = false) {
        if toggle, expanded, showingAppPanel { collapse(); return }
        MenuPanelFocus.shared.showNormalPanel()
        open(.controls, appPanel: true)
    }

    func openQuickPanel(toggle: Bool = false) -> Bool {
        guard NotchSupport.routesQuickPanel(), acceptsSystemFeedback else { return false }
        if toggle, expanded, selected == .tools { collapse() }
        else { open(.tools) }
        return true
    }

    func openShelf(toggle: Bool = false) -> Bool {
        guard NotchSupport.routesShelf(), acceptsSystemFeedback else { return false }
        if toggle, expanded, selected == .files { collapse() }
        else { open(.files) }
        return true
    }

    func showMetric(_ metric: MetricDetailKind) {
        guard metric.panelSection.isAvailable else { return }
        open(.system, metric: metric)
    }

    func goBack() {
        let changesPresentation = selectedMetric != nil || showingAppPanel
        mutatePresentation(transitionContent: changesPresentation ? .replace : .none) { selectedMetric = nil; showingAppPanel = false }
        syncVisibleConsumers()
        if changesPresentation { provideHapticFeedback() }
    }

    private func provideHapticFeedback() {
        guard acceptsSystemFeedback, panel?.isVisible == true, NotchSupport.usesHapticFeedback() else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }

    func fileDragChanged(_ active: Bool, internalDrag: Bool = false) {
        guard running, !suspended, NotchSupport.routesShelf() else { return }
        heldDrag = active && internalDrag
        if active, !internalDrag, NotchSupport.revealsShelfDrag(), !expanded {
            mutatePresentation { dragPlaceholder = true; peeking = false }
        } else if !active {
            mutatePresentation { dragPlaceholder = false }
            inside = windowHost?.contains(NSEvent.mouseLocation) == true
            if !inside, !pinned { hover(false) }
        }
    }

    func presentCaptureControls(_ options: ScreenCaptureSelectionOptions, cancel: @escaping () -> Void) {
        guard acceptsSystemFeedback else { cancel(); return }
        pinned = false
        captureControlsCancel = cancel
        captureControls = options
        captureControlsSubscription = options.$selectedTool.dropFirst()
            .receive(on: DispatchQueue.main).sink { [weak self] _ in
                self?.objectWillChange.send()
                self?.refreshPresentation()
            }
        expanded = false
        peeking = false
        notice = nil
        hoverWork?.cancel()
        removeEventMonitors()
        panel?.acceptsKeyFocus = true
        panel?.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        refreshPresentation()
        panel?.orderFrontRegardless()
        panel?.makeKey()
        syncVisibleConsumers()
    }

    func endCaptureControls() {
        guard captureControls != nil else { return }
        geometry.compactSideRoom = nil
        captureControls = nil
        captureControlsSubscription = nil
        captureControlsCancel = nil
        panel?.level = .statusBar
        panel?.acceptsKeyFocus = false
        panel?.resignKey()
        refreshPresentation()
        syncMenuSpaceMonitoring()
    }

    func cancelCaptureControls() { captureControlsCancel?() }

    func openSettings() {
        collapse()
        SettingsRouter.shared.request(FeatureSettingsDestination(.notch))
        (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
    }

    func perform(_ action: @escaping () -> Void) {
        collapse()
        if let windowHost { windowHost.whenSettled(action) }
        else { DispatchQueue.main.async(execute: action) }
    }

    var canAcceptFileDrop: Bool {
        acceptsSystemFeedback && captureControls == nil && modules.contains(.files)
            && AppFeature.shelf.isAvailable
    }

    func accept(_ pasteboard: NSPasteboard) -> Bool {
        guard canAcceptFileDrop else { return false }
        let accepted = ShelfService.shared.accept(pasteboard: pasteboard)
        if accepted { heldDrag = false; dragPlaceholder = false; open(.files) }
        return accepted
    }

    @discardableResult
    func show(_ incoming: NotchNotice) -> Bool {
        guard running, !suspended, panel != nil, NotchSupport.routes(incoming.event),
              NotchSupport.shouldReplace(notice?.event, with: incoming.event) else { return false }
        noticeWork?.cancel()
        // Slider and key bursts only replace the displayed value. They never
        // restart a window resize or enqueue another layout animation.
        mutatePresentation { notice = incoming }
        let work = DispatchWorkItem { [weak self] in self?.dismissNotice() }
        noticeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + incoming.event.duration, execute: work)
        return true
    }

    func showBrightness(_ level: Double) -> Bool {
        let text = FeatureStrings.notch(L10n.shared.language)
        return show(NotchNotice(event: .brightness, title: text.brightness,
                                detail: "\(BrightnessSupport.wholePercent(level))%",
                                symbol: "sun.max.fill", level: level))
    }

    private func dismissNotice() {
        noticeWork?.cancel(); noticeWork = nil
        mutatePresentation { notice = nil }
    }

    func presentCapture(id: UUID, content: AnyView, fallback: @escaping () -> Void,
                        close: @escaping () -> Void, hover: @escaping (Bool) -> Void) -> Bool {
        guard running, !suspended, panel != nil, NotchSupport.routes(.capture) else { return false }
        let keepOpen = expanded && pinned
        captureID = id
        captureContent = content
        captureFallback = fallback
        captureClose = close
        captureHover = hover
        open(.captures, pinned: keepOpen, takeFocus: false, feedback: false)
        captureHover?(inside)
        return true
    }

    func removeCapture(id: UUID) {
        guard captureID == id else { return }
        clearCapture()
        if expanded, selected == .captures, !pinned { collapse() }
    }

    private func clearCapture() {
        captureID = nil
        captureContent = nil
        captureFallback = nil
        captureClose = nil
        captureHover = nil
    }

    private func mutatePresentation(transitionContent: NotchContentTransition = .none, _ change: () -> Void) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
        refreshPresentation(transitionContent: transitionContent)
    }

    func refreshPresentation(animated: Bool = true, transitionContent: NotchContentTransition = .none) {
        let active = expanded || peeking || notice != nil || dragPlaceholder || captureControls != nil
        guard active || geometry.isNotched || geometry.compactSideRoom != nil else {
            panel?.orderOut(nil)
            return
        }
        windowHost?.present(size: surfaceSize, geometry: geometry, animated: animated,
                            transitionContent: transitionContent)
        if panel?.isVisible != true { panel?.orderFrontRegardless() }
    }

    private func stopMenuSpaceMonitoring() {
        menuSpaceTimer?.invalidate()
        menuSpaceTimer = nil
        menuSpaceGeneration += 1
    }

    private func syncMenuSpaceMonitoring() {
        let wanted = running && !suspended && !expanded && captureControls == nil
            && (idleContent != .none || hasMusicActivity || !geometry.isNotched)
        guard wanted else { stopMenuSpaceMonitoring(); return }
        guard menuSpaceTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.readMenuSpace() }
        timer.tolerance = 0.2
        menuSpaceTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        readMenuSpace()
    }

    private func invalidateMenuSpace() {
        menuSpaceGeneration += 1
        geometry.compactSideRoom = nil
        if !expanded, captureControls == nil { refreshPresentation(animated: false) }
        readMenuSpace()
    }

    private func readMenuSpace() {
        guard menuSpaceTimer != nil, !menuSpaceReading,
              let app = NSWorkspace.shared.frontmostApplication else { return }
        menuSpaceReading = true
        let generation = menuSpaceGeneration
        let geometry = geometry
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? geometry.screen.maxY
        let window = panel?.windowNumber ?? -1
        let pid = app.processIdentifier
        menuSpaceQueue.async { [weak self] in
            let room = NotchMenuBarSpace.measure(pid: pid, geometry: geometry,
                                                primaryTop: primaryTop, ownWindow: window)
            DispatchQueue.main.async {
                guard let self else { return }
                self.menuSpaceReading = false
                guard self.menuSpaceTimer != nil else { return }
                guard self.menuSpaceGeneration == generation,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
                    self.readMenuSpace(); return
                }
                if self.geometry.compactSideRoom != room {
                    let previousSize = self.surfaceSize
                    let grows = (room ?? 0) > (self.geometry.compactSideRoom ?? 0)
                    self.geometry.compactSideRoom = room
                    // Shrink immediately to protect new menus. Growing into
                    // confirmed free room can retain the normal smooth motion.
                    if previousSize != self.surfaceSize || self.panel?.isVisible != true {
                        self.refreshPresentation(animated: grows)
                    }
                }
            }
        }
    }

    private func updateScreen() {
        let screens = NSScreen.screens
        let builtIn = screens.map { CGDisplayIsBuiltin($0.notchDisplayID) != 0 }
        let index = NotchSupport.screenIndex(
            preference: NotchDisplay(rawValue: UserDefaults.standard.string(
                forKey: DefaultsKey.notchDisplay) ?? "") ?? .automatic,
            builtIn: builtIn, notched: screens.map { $0.safeAreaInsets.top > 0 },
            main: screens.firstIndex(where: { $0 === NSScreen.withMenuBar }) ?? 0)
        guard let index else { tearDownPresentation(); return }
        let screen = screens[index]
        let cameraWidth: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            cameraWidth = max(0, right.minX - left.maxX)
        } else { cameraWidth = 0 }
        let next = NotchGeometry(screen: screen.frame, safeAreaTop: screen.safeAreaInsets.top,
                                 cameraWidth: cameraWidth,
                                 layout: NotchSize(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.notchSize) ?? "") ?? .compact,
                                 menuBarHeight: NSStatusBar.system.thickness,
                                 compactSideRoom: screen.frame == geometry.screen ? geometry.compactSideRoom : nil,
                                 customWidth: UserDefaults.standard.double(forKey: DefaultsKey.notchCustomWidth),
                                 customHeight: UserDefaults.standard.double(forKey: DefaultsKey.notchCustomHeight))
        if next != geometry { menuSpaceGeneration += 1; geometry = next }
        if windowHost == nil {
            windowHost = NotchWindowHost(content: AnyView(NotchView(service: self)), geometry: geometry, size: surfaceSize)
            panel?.title = FeatureStrings.notch(L10n.shared.language).title
        }
        if modules.contains(.files), AppFeature.shelf.isAvailable {
            windowHost?.setFileDropActions(NotchFileDropActions(
                canAccept: { [weak self] pasteboard in
                    self?.canAcceptFileDrop == true && !ShelfService.shared.isInternalDragActive
                        && ShelfService.shared.canAcceptPasteboard(pasteboard)
                },
                enter: { [weak self] in self?.open(.files, takeFocus: false) },
                accept: { [weak self] in self?.accept($0) == true },
                exit: { [weak self] in
                    guard let self else { return }
                    self.hover(self.windowHost?.contains(NSEvent.mouseLocation) == true)
                }))
        } else { windowHost?.setFileDropActions(nil) }
        panel?.sharingType = NotchSupport.showsInCaptures() ? .readOnly : .none
    }

    private func installObservers() {
        observe(.default, NSMenu.didBeginTrackingNotification) { [weak self] in self?.trackingMenu = true; self?.hoverWork?.cancel() }
        observe(.default, NSMenu.didEndTrackingNotification) { [weak self] in
            guard let self else { return }
            self.trackingMenu = false
            self.hover(self.windowHost?.contains(NSEvent.mouseLocation) == true)
        }
        observe(.default, NSApplication.didChangeScreenParametersNotification) { [weak self] in
            guard let self, !self.suspended else { return }
            self.invalidateMenuSpace()
            self.syncWithPreferences()
        }
        observe(.default, UserDefaults.didChangeNotification) { [weak self] in
            // AppStorage can notify during a view update; defer any window work.
            DispatchQueue.main.async { self?.syncWithPreferences() }
        }
        observe(.default, .menuPanelWillShow) { [weak self] in self?.collapse() }
        session.onConsole = SessionActivity.shared.isActive
        session.locked = (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { [weak self] in
            guard let self, !self.suspended else { return }
            self.invalidateMenuSpace()
            guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            self.panel?.resignKey()
            if self.expanded, self.modules.contains(.clipboard) {
                ClipboardHistoryService.shared.rememberPasteTarget()
            }
            if self.expanded, !self.pinned, !self.keepsWorkingSurface, self.captureControls == nil { self.collapse() }
        }
        observe(workspace, NSWorkspace.willSleepNotification) { [weak self] in
            self?.updateSession { $0.sleeping = true }
        }
        observe(workspace, NSWorkspace.didWakeNotification) { [weak self] in
            self?.updateSession { $0.sleeping = false }
        }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { [weak self] in
            self?.updateSession { $0.displaysSleeping = true }
        }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { [weak self] in
            self?.updateSession { $0.displaysSleeping = false }
        }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { [weak self] in
            self?.updateSession { $0.onConsole = false }
        }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in
            self?.updateSession { $0.onConsole = true }
        }
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { [weak self] in
            self?.updateSession { $0.locked = true }
        }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in
            self?.updateSession { $0.locked = false }
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         action: @escaping () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in action() }
        observers.append((center, token))
    }

    private func updateSession(_ change: (inout NotchSessionState) -> Void) {
        guard running else { return }
        let couldPresent = session.canPresent
        change(&session)
        guard couldPresent != session.canPresent else { return }
        if session.canPresent {
            syncWithPreferences()
        } else {
            let cancel = captureControlsCancel
            endCaptureControls()
            cancel?()
            captureClose?()
            clearCapture()
            tearDownPresentation()
            if AppFeature.mixer.isAvailable { PreciseVolumeRollerService.shared.syncWithPreferences() }
        }
    }

    private func installEventMonitors() {
        guard eventMonitors.isEmpty else { return }
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let token = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            guard let self, !self.keepsWorkingSurface else { return }
            self.collapse()
        }) { eventMonitors.append(token) }
        if let token = NSEvent.addLocalMonitorForEvents(matching: clicks.union(.keyDown), handler: { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.window === self.panel, self.selected == .tools, !self.showingAppPanel {
                return QuickLauncherService.shared.handlePanelKey(event, columns: NotchSupport.toolColumns)
            }
            if event.type == .keyDown, event.window === self.panel, event.keyCode == 53 {
                self.collapse()
                return nil
            }
            if clicks.contains(NSEvent.EventTypeMask(rawValue: 1 << event.type.rawValue)),
               event.window !== self.panel, !self.keepsWorkingSurface { self.collapse() }
            return event
        }) { eventMonitors.append(token) }
    }

    private func removeEventMonitors() {
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors.removeAll()
    }

    private func bindEvents() {
        subscriptions.removeAll()
        if modules.contains(.music) {
            NotchMusicService.shared.$playback.map { ($0 != nil, $0?.isPlaying == true) }
                .removeDuplicates { $0 == $1 }.receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.syncMenuSpaceMonitoring()
                    self?.objectWillChange.send()
                    self?.refreshPresentation()
                }.store(in: &subscriptions)
        }
        stopPower()
        if NotchSupport.routes(.volume) {
            let mixer = AppVolumeMixer.shared
            volumeBaseline = mixer.systemOutputVolume
            muteBaseline = mixer.systemOutputMuted
            mixer.$systemOutputVolume.combineLatest(mixer.$systemOutputMuted)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] volume, muted in self?.volumeChanged(volume, muted: muted) }
                .store(in: &subscriptions)
        }
        if NotchSupport.routes(.clipboard) {
            let history = ClipboardHistoryService.shared
            history.capturedEntry.receive(on: DispatchQueue.main).sink { [weak self] _ in
                guard let self else { return }
                let text = FeatureStrings.clipboard(L10n.shared.language)
                self.show(NotchNotice(event: .clipboard, title: text.copied,
                                      detail: text.title, symbol: "doc.on.clipboard"))
            }.store(in: &subscriptions)
        }
        if NotchSupport.routes(.battery) || idleContent == .battery { startPower() }
    }

    func showCurrentVolume() {
        let mixer = AppVolumeMixer.shared
        guard let volume = mixer.systemOutputVolume else { return }
        showVolume(volume, muted: mixer.systemOutputMuted)
    }

    private func volumeChanged(_ volume: Double?, muted: Bool?) {
        defer { volumeBaseline = volume; muteBaseline = muted }
        guard let volume, volumeBaseline != nil,
              volume != volumeBaseline || (muteBaseline != nil && muted != muteBaseline) else { return }
        showVolume(volume, muted: muted)
    }

    private func showVolume(_ volume: Double, muted: Bool?) {
        guard volume.isFinite else { return }
        let value = muted == true ? 0 : min(1, max(0, volume))
        show(NotchNotice(event: .volume, title: FeatureStrings.notch(L10n.shared.language).volume,
                         detail: "\(Int((value * 100).rounded()))%",
                         symbol: value == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill", level: value))
    }

    private func startPower() {
        guard PowerSampler.hasInternalBattery else { return }
        powerSampler = PowerSampler(smc: nil)
        power = powerSampler?.sample() ?? PowerReading()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let owner = Unmanaged<NotchService>.fromOpaque(context).takeUnretainedValue()
            owner.powerChanged()
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue() {
            powerSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    private func stopPower() {
        if let source = powerSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        powerSource = nil
        powerSampler = nil
    }

    private func powerChanged() {
        guard running, !suspended, let sampler = powerSampler else { return }
        let before = power
        let next = sampler.sample()
        power = next
        let low = (next.chargePercent ?? 100) <= 20 && (before.chargePercent ?? 0) > 20
        guard before.externalConnected != next.externalConnected || low
                || (before.isCharging && !next.isCharging && next.chargePercent == 100) else { return }
        let text = FeatureStrings.notch(L10n.shared.language)
        let title = low ? text.lowBattery : next.externalConnected
            ? (next.isCharging ? text.charging : next.chargePercent == 100
                ? text.charged : L10n.shared.s.powerPluggedIn) : text.onBattery
        show(NotchNotice(event: .battery, title: title,
                         detail: next.chargePercent.map { "\($0)%" } ?? "",
                         symbol: next.externalConnected ? "battery.100percent.bolt" : "battery.25percent"))
    }

    private func syncVisibleConsumers() {
        syncMenuSpaceMonitoring()
        guard running, !suspended else { releaseMonitor(); return }
        let musicWanted = modules.contains(.music) && ((expanded && selected == .music && !showingAppPanel)
            || idleContent == .music || NotchSupport.watchesMusicActivity())
        if musicWanted { NotchMusicService.shared.start() } else { NotchMusicService.shared.stop() }
        let needs = expanded && selected == .system && selectedMetric == nil && modules.contains(.system) && !showingAppPanel
        SystemMonitor.shared.setNotchDetailNeeds(expanded ? selectedMetric?.monitorNeeds ?? .none : .none)
        if needs != notchNeedsMonitor {
            notchNeedsMonitor = needs
            SystemMonitor.shared.setNotchVisible(needs)
        }
    }

    private func releaseMonitor() {
        SystemMonitor.shared.setNotchDetailNeeds(.none)
        guard notchNeedsMonitor else { return }
        notchNeedsMonitor = false
        SystemMonitor.shared.setNotchVisible(false)
    }
}

extension NSScreen {
    var notchDisplayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
