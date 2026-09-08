// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import CoreGraphics

enum NotchTests {
    static func run(expect: (Bool, String) -> Void) {
        let suite = "com.vorssaint.tests.notch"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        // Registration defaults are shared across suites within the process.
        // Keep this fixture inside its own persistent domain so migration
        // tests later in the harness still see a genuinely untouched setup.
        for (key, value) in Defaults.registeredDefaults
        where key.hasPrefix("notch") || key == DefaultsKey.clipboardHistoryEnabled
            || key == DefaultsKey.brightnessControlEnabled {
            defaults.set(value, forKey: key)
        }
        for (key, value) in AppFeature.availabilityDefaults { defaults.set(value, forKey: key) }
        expect(!NotchSupport.isEnabled(in: defaults), "notch is opt-in")
        expect(!NotchSupport.routesAppPanel(in: defaults) && !NotchSupport.routesQuickPanel(in: defaults)
               && !NotchSupport.routesShelf(in: defaults) && !NotchSupport.routesCaptureControls(in: defaults)
               && !NotchSupport.routesClipboardWindow(in: defaults),
               "separate panels remain the default until the notch is explicitly enabled")
        expect(NotchSupport.showsInCaptures(in: defaults), "notch appears in screenshots and recordings by default")
        defaults.set(true, forKey: DefaultsKey.notchHideInCaptures)
        expect(NotchSupport.showsInCaptures(in: defaults), "the old inverse default cannot silently hide the notch")
        defaults.set(false, forKey: DefaultsKey.notchShowInCaptures)
        expect(!NotchSupport.showsInCaptures(in: defaults), "capture visibility remains an explicit opt-out")
        defaults.set(true, forKey: DefaultsKey.notchShowInCaptures)
        expect(NotchEvent.allCases.allSatisfy { !NotchSupport.routes($0, in: defaults) },
               "disabled notch cannot consume any existing presentation")
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        expect(NotchSupport.isEnabled(in: defaults), "master switch enables notch")
        expect(!NotchSupport.usesHapticFeedback(in: defaults), "enabling the notch does not enable tactile feedback")
        defaults.set(true, forKey: DefaultsKey.notchHapticFeedback)
        expect(NotchSupport.usesHapticFeedback(in: defaults), "tactile feedback has an independent opt-in")
        defaults.set(false, forKey: DefaultsKey.notchEnabled)
        expect(!NotchSupport.usesHapticFeedback(in: defaults) && !NotchSupport.routesAppPanel(in: defaults)
               && !NotchSupport.routesQuickPanel(in: defaults) && !NotchSupport.routesShelf(in: defaults),
               "turning the notch off restores separate panels and suppresses tactile feedback")
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        expect(NotchSupport.usesHapticFeedback(in: defaults), "disabling the notch preserves the user's tactile preference")
        expect(NotchSupport.idleContent(in: defaults) == .none, "idle is empty without an explicit choice")
        expect(NotchSupport.watchesMusicActivity(in: defaults), "enabled music activity can detect playback while the panel is closed")
        expect(NotchSupport.showsMusicActivity(isPlaying: true, in: defaults)
               && !NotchSupport.showsMusicActivity(isPlaying: false, in: defaults),
               "active playback has a horizontal presentation without populating quiet idle")
        defaults.set(false, forKey: DefaultsKey.notchShowPlayingMusic)
        expect(!NotchSupport.showsMusicActivity(isPlaying: true, in: defaults), "automatic music presentation can be disabled")
        defaults.set(true, forKey: DefaultsKey.notchShowPlayingMusic)
        defaults.set("music", forKey: DefaultsKey.notchHiddenModules)
        expect(!NotchSupport.watchesMusicActivity(in: defaults), "hidden music does not keep an activity observer")
        defaults.set("", forKey: DefaultsKey.notchHiddenModules)
        defaults.set(true, forKey: DefaultsKey.notchMusicActivity)
        expect(NotchSupport.idleContent(in: defaults) == .none, "legacy music preference cannot populate a newly empty idle surface")
        defaults.set(NotchIdleContent.battery.rawValue, forKey: DefaultsKey.notchIdleContent)
        expect(NotchSupport.idleContent(in: defaults) == .battery, "idle battery is an independent explicit choice")
        defaults.set(false, forKey: AppFeature.monitorPower.availabilityKey)
        expect(NotchSupport.idleContent(in: defaults) == .none, "unavailable battery cannot appear while idle")
        defaults.set(true, forKey: AppFeature.monitorPower.availabilityKey)
        defaults.set(NotchIdleContent.none.rawValue, forKey: DefaultsKey.notchIdleContent)
        expect(NotchSupport.modules(in: defaults).contains(.mixer), "the full mixer has a direct destination")
        defaults.set(false, forKey: AppFeature.mixer.availabilityKey)
        expect(!NotchSupport.modules(in: defaults).contains(.mixer)
               && !NotchSupport.controls(in: defaults).contains(.volume), "mixer availability gates its module and volume control")
        defaults.set(true, forKey: AppFeature.mixer.availabilityKey)
        defaults.set("panel,panel,unknown,speedTest", forKey: DefaultsKey.notchControlOrder)
        defaults.set("volume,screenshot", forKey: DefaultsKey.notchHiddenControls)
        let controls = NotchSupport.controls(in: defaults)
        expect(controls.first == .panel && Set(controls).count == controls.count,
               "shortcut ordering tolerates duplicate and obsolete identifiers")
        expect(!controls.contains(.volume) && !controls.contains(.screenshot), "individual controls can be hidden")
        defaults.set("mixer,commandBar", forKey: DefaultsKey.notchHiddenControls)
        defaults.set("", forKey: DefaultsKey.notchControlOrder)
        expect(!NotchSupport.closesOnPointerExit(expanded: true, peeking: false, openedByHover: false),
               "menu bar and keyboard openings survive a pointer outside the notch")
        expect(NotchSupport.closesOnPointerExit(expanded: true, peeking: false, openedByHover: true)
               && NotchSupport.closesOnPointerExit(expanded: false, peeking: true, openedByHover: false),
               "hover presentations still close when the pointer leaves")
        expect(ScreenshotSupport.selectionDimAlpha(notchControls: true, isFrozen: true, isDragging: false) == 0,
               "opening capture controls in the notch does not darken the desktop")
        expect(ScreenshotSupport.selectionDimAlpha(notchControls: true, isFrozen: true, isDragging: true) > 0,
               "dragging a capture region retains visual selection feedback")
        expect(ScreenshotSupport.selectionDimAlpha(notchControls: false, isFrozen: true, isDragging: false) == 0.22,
               "the standalone capture chooser keeps its existing contrast")
        expect(!NotchSupport.routes(.clipboard, in: defaults) && !NotchSupport.routes(.capture, in: defaults),
               "notch opt-in does not reveal copied content or move captures")
        defaults.set(true, forKey: DefaultsKey.notchClipboard)
        expect(!NotchSupport.routes(.clipboard, in: defaults), "clipboard event respects the history capture switch")
        defaults.set(true, forKey: DefaultsKey.clipboardHistoryEnabled)
        expect(NotchSupport.routes(.clipboard, in: defaults), "explicit clipboard activity opt-in is honored")
        expect(!NotchSupport.routesClipboardWindow(in: defaults), "clipboard opening stays unchanged until opted in")
        defaults.set(true, forKey: DefaultsKey.notchClipboardWindow)
        expect(NotchSupport.routesClipboardWindow(in: defaults), "clipboard opening can be routed to the notch")
        defaults.set("clipboard,unknown", forKey: DefaultsKey.notchHiddenModules)
        expect(!NotchSupport.routesClipboardWindow(in: defaults), "hidden clipboard keeps the ordinary history available")
        expect(!NotchSupport.routes(.clipboard, in: defaults), "hidden module cannot leak an activity")
        defaults.set("system,music,music,unknown", forKey: DefaultsKey.notchModuleOrder)
        expect(NotchSupport.modules(in: defaults) == [.system, .music, .controls, .mixer, .captures, .files, .tools],
               "module order ignores unknown ids and duplicates, preserving newly added modules")
        expect(NotchSupport.routesShelf(in: defaults) && NotchSupport.revealsShelfDrag(in: defaults),
               "the enabled notch replaces the file destination and reveals active drags")
        defaults.set(false, forKey: DefaultsKey.notchDragReveal)
        expect(NotchSupport.routesShelf(in: defaults) && !NotchSupport.revealsShelfDrag(in: defaults),
               "drag reveal can be disabled without moving the shelf")
        defaults.set(false, forKey: DefaultsKey.notchCaptureControls)
        expect(!NotchSupport.routesCaptureControls(in: defaults), "capture controls retain an independent destination")
        defaults.set(false, forKey: AppFeature.quickLauncher.availabilityKey)
        expect(!NotchSupport.modules(in: defaults).contains(.tools) && !NotchSupport.routesQuickPanel(in: defaults),
               "removing the quick panel also removes its embedded tools and shortcut routing")
        defaults.set(false, forKey: DefaultsKey.notchQuickPanel)
        expect(!NotchSupport.routesQuickPanel(in: defaults), "quick panel shortcut can keep its original destination")
        defaults.set(false, forKey: AppFeature.shelf.availabilityKey)
        expect(!NotchSupport.modules(in: defaults).contains(.files), "unavailable shelf leaves no notch surface")
        defaults.set(false, forKey: AppFeature.notch.availabilityKey)
        expect(!NotchSupport.isEnabled(in: defaults), "hub is stronger than the notch master switch")
        expect(!NotchSupport.usesHapticFeedback(in: defaults), "removing the feature also gates tactile feedback")
        expect(NotchEvent.allCases.allSatisfy { !NotchSupport.routes($0, in: defaults) },
               "hub removal gates every notch event")

        let keys: Set<String> = [DefaultsKey.notchShowPlayingMusic, DefaultsKey.notchShowInCaptures, DefaultsKey.notchIdleContent, DefaultsKey.notchHiddenControls, DefaultsKey.notchControlOrder, DefaultsKey.notchSize, DefaultsKey.notchShelf, DefaultsKey.notchDragReveal,
                                DefaultsKey.notchCustomWidth, DefaultsKey.notchCustomHeight, DefaultsKey.notchHapticFeedback,
                                DefaultsKey.notchCaptureControls, DefaultsKey.notchQuickPanel, DefaultsKey.notchAppPanel,
                                DefaultsKey.notchHoverExpands, DefaultsKey.notchEnabled, DefaultsKey.notchDisplay,
                                DefaultsKey.notchOpenOnHover, DefaultsKey.notchHiddenModules,
                                DefaultsKey.notchModuleOrder, DefaultsKey.notchVolume,
                                DefaultsKey.notchBrightness, DefaultsKey.notchBattery,
                                DefaultsKey.notchClipboard, DefaultsKey.notchClipboardWindow, DefaultsKey.notchCapture,
                                DefaultsKey.notchMusicActivity, DefaultsKey.notchHideInCaptures, DefaultsKey.panelControlNotch,
                                AppFeature.notch.availabilityKey]
        expect(SettingsBackupSupport.exportKeys().isSuperset(of: keys), "every notch preference travels in backup")
        let restored = SettingsBackupSupport.sanitizedSettings(from: [
            SettingsBackupSupport.formatVersionKey: SettingsBackupSupport.formatVersion,
            SettingsBackupSupport.settingsKey: [DefaultsKey.notchEnabled: true,
                                                DefaultsKey.notchDisplay: "builtIn",
                                                DefaultsKey.notchSize: "custom",
                                                DefaultsKey.notchCustomWidth: 390.0,
                                                DefaultsKey.notchCustomHeight: 580.0,
                                                DefaultsKey.notchHapticFeedback: true,
                                                DefaultsKey.notchHiddenModules: "clipboard",
                                                DefaultsKey.notchVolume: false],
        ])
        expect(restored?[DefaultsKey.notchEnabled] as? Bool == true
               && restored?[DefaultsKey.notchDisplay] as? String == "builtIn"
               && restored?[DefaultsKey.notchVolume] as? Bool == false,
               "backup restores notch placement and event choices")
        expect(restored?[DefaultsKey.notchSize] as? String == "custom"
               && restored?[DefaultsKey.notchCustomWidth] as? Double == 390
               && restored?[DefaultsKey.notchCustomHeight] as? Double == 580
               && restored?[DefaultsKey.notchHapticFeedback] as? Bool == true,
               "backup restores custom dimensions and tactile feedback together")
        expect(AppFeature.notch.settingsDestination.page == .notch, "hub routes to notch settings")
        expect(!FeatureVisibilitySupport.isPageVisible(.notch, isAvailable: { $0 != .notch }),
               "notch settings disappear when uninstalled")

        for language in AppLanguage.allCases {
            for child in Mirror(reflecting: FeatureStrings.notch(language)).children {
                let value = child.value as? String ?? ""
                expect(!value.isEmpty && !value.contains("—"),
                       "notch localized text is present and human-readable: \(language) \(child.label ?? "")")
            }
        }

        let frames = [CGRect(x: 0, y: 0, width: 1512, height: 982),
                      CGRect(x: -1920, y: -100, width: 1920, height: 1080),
                      CGRect(x: 100, y: 982, width: 900, height: 1440),
                      CGRect(x: 0, y: 0, width: 640, height: 480)]
        let compact = NotchGeometry(screen: frames[0], safeAreaTop: 32, cameraWidth: 210)
        let spacious = NotchGeometry(screen: frames[0], safeAreaTop: 32, cameraWidth: 210, layout: .spacious)
        expect(compact.expanded.width < 400 && spacious.expanded.width > compact.expanded.width,
               "compact is close to the separate panel's width while spacious remains available")
        let idleMusic = compact.expandedSize(module: .music, musicHasContent: false)
        expect(idleMusic.height < compact.expandedSize(module: .music).height
               && compact.contentSize(for: idleMusic, navigation: true).height >= 130,
               "empty music keeps its message and volume controls without reserving a full player")
        let fullControls = compact.expandedSize(module: .controls, controlRows: 2, sliderCount: 2)
        let fewerShortcuts = compact.expandedSize(module: .controls, controlRows: 1, sliderCount: 2)
        let onlyShortcuts = compact.expandedSize(module: .controls, controlRows: 1, sliderCount: 0)
        expect(fullControls.height > fewerShortcuts.height && fewerShortcuts.height > onlyShortcuts.height,
               "hiding shortcuts or sliders removes their unused vertical space")
        expect(compact.contentSize(for: compact.expandedSize(module: .controls, controlRows: 0, sliderCount: 0),
                                   navigation: true).height >= 160,
               "hiding every control leaves enough room for the empty-state guidance")
        for frame in frames {
            for width in [360.0, 470.0, 600.0] {
                for height in [400.0, 520.0, 640.0] {
                    let custom = NotchGeometry(screen: frame, safeAreaTop: 32, cameraWidth: 210,
                                               layout: .custom, customWidth: width, customHeight: height)
                    for module in NotchModule.allCases {
                        let size = custom.expandedSize(module: module)
                        expect(size.width == min(width, frame.width - 24) && size.height <= height
                               && frame.contains(custom.frame(for: size)),
                               "custom dimensions fit every module and respect the display and height limit")
                    }
                    expect(custom.expandedSize(module: .clipboard).height == min(height, frame.height - 48),
                           "long lists use the chosen height without overflowing a shorter display")
                    expect(custom.contentSize(for: custom.expandedSize(module: .music), navigation: true).height >= 238,
                           "custom sizes retain space for music and its essential volume controls")
                }
            }
        }
        for invalid in [Double.nan, .infinity, -.infinity, -200, 0, 1e9] {
            let custom = NotchGeometry(screen: frames[0], safeAreaTop: 32, cameraWidth: 210, layout: .custom,
                                       customWidth: invalid, customHeight: invalid)
            expect(NotchSize.widthRange.contains(custom.customWidth) && NotchSize.heightRange.contains(custom.customHeight)
                   && frames[0].contains(custom.frame(for: custom.expandedSize(module: .tools))),
                   "invalid imported dimensions cannot create an unbounded or off-screen panel")
        }
        let wideCamera = NotchGeometry(screen: frames[0], safeAreaTop: 32, cameraWidth: 390, layout: .custom,
                                       customWidth: 360)
        expect(wideCamera.expanded.width > wideCamera.cameraWidth,
               "a requested narrow panel still clears a wider physical camera")
        for frame in frames {
            for notch in [false, true] {
                let geometry = NotchGeometry(screen: frame, safeAreaTop: notch ? 32 : 0,
                                             cameraWidth: notch ? 210 : 0)
                for size in [geometry.collapsed, geometry.notice, geometry.expanded] {
                    let positioned = geometry.frame(for: size)
                    expect(frame.contains(positioned), "notch fits displays in every coordinate quadrant")
                    expect(positioned.midX == frame.midX, "notch stays centered while morphing")
                    expect(positioned.maxY == frame.maxY - geometry.topInset,
                           "top edge does not jump across presentation states")
                }
                expect(geometry.musicWingWidth * 2 + geometry.musicCameraGap == geometry.musicStrip.width,
                       "horizontal metadata uses equal wings around the camera")
                expect(geometry.frame(for: geometry.musicStrip).maxY == frame.maxY - geometry.topInset,
                       "music activity remains attached to the same top edge")
                expect(geometry.contentSize(for: geometry.expandedSize(module: .music), navigation: true).height >= 238,
                       "compact music reserves room for metadata, transport, progress and volume together")
                let quiet = geometry.restingSize(showsContent: false)
                expect(quiet.width == geometry.cameraWidth && quiet.height <= geometry.menuBarHeight,
                       "empty idle does not reserve wings or a footer for unsolicited widgets")
                expect(geometry.contentSize(for: geometry.expanded, navigation: true).height
                       == geometry.expanded.height - geometry.safeContentTop - 24 - 38 - 20 - 14,
                       "content budget matches the actual header, navigation, gaps and bottom inset")
                expect(geometry.safeContentTop > geometry.cameraHeight, "controls always clear the physical camera")
                expect(geometry.appPanelSize.width > 0 && geometry.appPanelSize.height >= 176
                       && geometry.appPanelSize.height < geometry.expandedSize(module: .tools).height,
                       "embedded panel reserves room for its navigation, content and footer")
            }
        }
        for frame in frames {
            for layout in NotchSize.allCases {
                let geometry = NotchGeometry(screen: frame, safeAreaTop: 32, cameraWidth: 210, layout: layout)
                for module in NotchModule.allCases {
                    let target = geometry.expandedSize(module: module)
                    let envelope = NotchMotion.envelope(from: geometry.notice, to: target)
                    let position = geometry.frame(for: envelope)
                    expect(position.maxY == frame.maxY && position.midX == frame.midX && frame.contains(position),
                           "the animation's backing window stays inside the display and attached to its top center")
                    expect(envelope.width >= geometry.notice.width && envelope.height >= geometry.notice.height
                           && envelope.width >= target.width && envelope.height >= target.height,
                           "the backing window can reveal either endpoint without resizing each frame")
                    expect(NotchMotion.envelope(from: envelope, to: geometry.collapsed) == envelope,
                           "an interrupted closing retains its backing area until the silhouette settles")
                }
                expect(geometry.peek.height < geometry.expanded.height / 3,
                       "hover reveals a small target instead of the entire panel")
            }
        }
        let menuScreen = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let freeRoom = NotchMenuBarLayout.sideRoom(screen: menuScreen, cameraWidth: 180, barHeight: 32,
            occupied: [CGRect(x: 0, y: 924, width: 610, height: 32), CGRect(x: 950, y: 924, width: 520, height: 32)])
        expect(freeRoom == 27, "compact wings stop before the app menu, including its spacing")
        expect(NotchMenuBarLayout.sideRoom(screen: menuScreen, cameraWidth: 180, barHeight: 32,
            occupied: [CGRect(x: 630, y: 924, width: 60, height: 32)]) == nil,
               "occupied camera space cannot be treated as a free menu gap")
        let constrained = NotchGeometry(screen: menuScreen, safeAreaTop: 32, cameraWidth: 180,
                                        menuBarHeight: 24, compactSideRoom: freeRoom)
        expect(constrained.collapsed.height == 32 && constrained.musicStrip.height == 32,
               "every passive presentation stays inside the menu bar, without an extra lower lip")
        expect(constrained.restingWingWidth == 0,
               "an indicator is omitted when there is not enough room to render it intact")
        let roomy = NotchGeometry(screen: menuScreen, safeAreaTop: 32, cameraWidth: 180,
                                 menuBarHeight: 24, compactSideRoom: 100)
        expect(roomy.musicStrip.width <= 380 && roomy.restingWingWidth == 44,
               "music and idle indicators both respect the same measured menu gap")
        let simulated = NotchGeometry(screen: menuScreen, safeAreaTop: 0, cameraWidth: 0, menuBarHeight: 22)
        expect(simulated.topInset == 0 && simulated.musicStrip.height == 22 && simulated.collapsed.height == 22,
               "simulated notches do not add a top offset or exceed a shorter menu bar")
        expect(NotchSupport.screenIndex(preference: .automatic, builtIn: [false, true],
                                       notched: [false, true], main: 0) == 1,
               "automatic uses the notched built-in screen even with external main display")
        expect(NotchSupport.screenIndex(preference: .builtIn, builtIn: [false],
                                       notched: [false], main: 0) == 0, "closed-lid mode falls back to an attached screen")
        expect(NotchSupport.screenIndex(preference: .main, builtIn: [], notched: [], main: 0) == nil,
               "no connected displays means no panel")
        expect(NotchSupport.shouldReplace(.volume, with: .brightness), "continuous controls can replace each other")
        expect(!NotchSupport.shouldReplace(.volume, with: .clipboard), "copy does not interrupt a volume adjustment")
        expect(NotchSupport.shouldReplace(.battery, with: .capture), "a capture takes precedence over passive battery status")
        expect(NotchSupport.volumeLevel(current: 0.99, direction: 1, fine: false) == 1
               && NotchSupport.volumeLevel(current: 0, direction: -1, fine: false) == 0,
               "hardware volume steps clamp to audible limits")
        expect(NotchSupport.volumeLevel(current: 0.5, direction: 1, fine: true) == 0.515625,
               "fine volume preserves the system quarter-step")

        var session = NotchSessionState()
        session.locked = true
        session.sleeping = true
        session.sleeping = false
        expect(!session.canPresent, "wake cannot reveal content over a locked screen")
        session.locked = false
        session.displaysSleeping = true
        expect(!session.canPresent, "unlock alone cannot revive sleeping displays")
        session.displaysSleeping = false
        session.onConsole = false
        expect(!session.canPresent, "another login session owns the display")
        session.onConsole = true
        expect(session.canPresent, "presentation resumes after every privacy condition clears")

        let now = Date(timeIntervalSince1970: 100)
        let reply = Data("{\"pid\":12,\"isPlaying\":false,\"kMRMediaRemoteNowPlayingInfoTitle\":\"A track\",\"kMRMediaRemoteNowPlayingInfoDuration\":180,\"kMRMediaRemoteNowPlayingInfoElapsedTime\":20}".utf8)
        let playback = NotchPlayback.decode(reply, now: now)
        expect(playback?.track.title == "A track" && playback?.isPlaying == false,
               "paused playback retains the track and its resume control")
        expect(playback?.position(at: now.addingTimeInterval(20)) == 20, "paused progress never advances")
        let playingReply = Data(String(decoding: reply, as: UTF8.self).replacingOccurrences(of: "false", with: "true").utf8)
        let playing = NotchPlayback.decode(playingReply, now: now)
        expect(playing?.position(at: now.addingTimeInterval(10)) == 30, "visible music progress follows elapsed time")
        expect(playing?.position(at: now.addingTimeInterval(500)) == 180, "music progress stops at track duration")
        expect(NotchPlayback.decode(Data("{\"pid\":0,\"isPlaying\":false}".utf8)) == nil,
               "empty system playback never fabricates a song")
        let fasterReply = Data(String(decoding: playingReply, as: UTF8.self)
            .replacingOccurrences(of: "\"pid\":12", with: "\"pid\":12,\"kMRMediaRemoteNowPlayingInfoPlaybackRate\":2").utf8)
        expect(NotchPlayback.decode(fasterReply, now: now)?.position(at: now.addingTimeInterval(10)) == 40,
               "spoken content follows its actual playback speed")
        let unchangedArtwork = Data("{\"pid\":12,\"isPlaying\":true,\"artworkUnchanged\":true}".utf8)
        let cachedArtwork = Data([1, 2, 3])
        expect(NotchPlayback.decode(unchangedArtwork, previousArtwork: cachedArtwork)?.track.artworkData == cachedArtwork,
               "metadata-only updates retain the existing artwork without retransmitting it")
        expect(NotchPlayback.decode(playingReply, previousArtwork: cachedArtwork)?.track.artworkData == nil,
               "a new track without artwork clears the old cover")
    }
}
