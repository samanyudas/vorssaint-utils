// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct NotchControlsView: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.brightnessControlEnabled) private var brightnessEnabled = false

    var body: some View {
        VStack(spacing: 12) {
            let items = NotchSupport.controls()
            if items.contains(.volume) { NotchAudioControls(notch: service) }
            if items.contains(.brightness) {
                if brightnessEnabled { NotchBrightnessControls() }
                else {
                    HStack {
                        Label(FeatureStrings.notch(l10n.language).brightness, systemImage: "sun.max.fill")
                        Spacer()
                        Button(l10n.s.menuSettings) {
                            service.perform {
                                SettingsRouter.shared.request(AppFeature.brightness.settingsDestination)
                                (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
                            }
                        }.buttonStyle(.plain)
                    }.font(.system(size: 11, weight: .medium))
                }
            }
            let shortcuts = items.filter { $0 != .volume && $0 != .brightness }
            if !shortcuts.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(shortcuts) { item in shortcut(item) }
                }
            }
            if shortcuts.isEmpty, !items.contains(.volume), !items.contains(.brightness) {
                NotchEmptyView(symbol: "slider.horizontal.3", message: FeatureStrings.notch(l10n.language).empty)
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder private func shortcut(_ item: NotchControlItem) -> some View {
        switch item {
        case .keepAwake: NotchAwakeButton()
        case .microphone: NotchMicButton()
        case .screenshot:
            NotchActionTile(symbol: "camera.viewfinder", title: item.title(l10n)) {
                service.perform { ScreenshotService.shared.capture() }
            }
        case .recording: NotchRecorderButton(service: service)
        case .speedTest:
            NotchActionTile(symbol: "speedometer", title: item.title(l10n)) { service.showMetric(.network) }
        case .panel:
            NotchActionTile(symbol: "rectangle.topthird.inset.filled", title: item.title(l10n)) { service.openAppPanel() }
        case .mixer:
            NotchActionTile(symbol: "slider.vertical.3", title: item.title(l10n)) { service.select(.mixer) }
        case .commandBar:
            NotchActionTile(symbol: "command", title: item.title(l10n)) { service.perform { CommandBarService.shared.show() } }
        case .volume, .brightness: EmptyView()
        }
    }
}

extension NotchControlItem {
    func title(_ l10n: L10n) -> String {
        switch self {
        case .volume: return FeatureStrings.notch(l10n.language).volume
        case .brightness: return FeatureStrings.notch(l10n.language).brightness
        case .keepAwake: return l10n.s.keepAwakeTitle
        case .microphone: return l10n.s.micMuteName
        case .screenshot: return FeatureStrings.recentCaptures(l10n.language).screenshot
        case .recording: return FeatureStrings.recorder(l10n.language).pageTitle
        case .speedTest: return l10n.s.speedTestRun
        case .panel: return FeatureStrings.notch(l10n.language).panel
        case .mixer: return l10n.s.mixerSection
        case .commandBar: return FeatureStrings.commandBar(l10n.language).pageTitle
        }
    }
}

struct NotchAudioControls: View {
    @ObservedObject var notch: NotchService = .shared
    @ObservedObject private var mixer = AppVolumeMixer.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    if let muted = mixer.systemOutputMuted { mixer.requestOutputAdjustment(muted: !muted) }
                } label: {
                    Image(systemName: mixer.systemOutputMuted == true ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }
                .buttonStyle(.plain)
                .disabled(mixer.systemOutputMuted == nil)
                .accessibilityLabel(mixer.systemOutputMuted == true ? l10n.s.actionUnmute : l10n.s.actionMute)
                Text(FeatureStrings.notch(l10n.language).volume)
                if notch.modules.contains(.mixer) {
                    Button { notch.select(.mixer) } label: {
                        Image(systemName: "slider.vertical.3").frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain).help(l10n.s.mixerSection).accessibilityLabel(l10n.s.mixerSection)
                }
                Spacer()
                Menu {
                    ForEach(mixer.outputDevices.filter(\.canBeDefaultOutput)) { device in
                        Button {
                            _ = mixer.setUniversalOutputDeviceUID(device.uid)
                        } label: {
                            if device.uid == mixer.currentOutputDeviceUID {
                                Label(device.name, systemImage: "checkmark")
                            } else { Text(device.name) }
                        }
                    }
                } label: {
                    Text(mixer.outputDevices.first(where: { $0.uid == mixer.currentOutputDeviceUID })?.name
                         ?? l10n.s.mixerSystemOutputTitle)
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: 140, alignment: .trailing)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(l10n.s.mixerSystemOutputTooltip)
            }
            .font(.system(size: 11, weight: .medium))
            if let volume = mixer.systemOutputVolume {
                HStack(spacing: 10) {
                    Slider(value: Binding(get: { mixer.systemOutputMuted == true ? 0 : volume },
                                          set: { mixer.requestOutputAdjustment(volume: $0) }), in: 0...1)
                        .controlSize(.small)
                        .accessibilityLabel(FeatureStrings.notch(l10n.language).volume)
                        .accessibilityValue("\(Int(((mixer.systemOutputMuted == true ? 0 : volume) * 100).rounded()))%")
                    Text("\(Int(((mixer.systemOutputMuted == true ? 0 : volume) * 100).rounded()))%")
                        .font(.system(size: 11, weight: .medium)).monospacedDigit()
                        .frame(width: 38, alignment: .trailing)
                }
            } else {
                Text(l10n.s.mixerOutputUnavailable).font(.caption).foregroundStyle(.secondary)
            }
            if let error = mixer.outputSwitchError {
                Text(error).font(.caption).foregroundStyle(.orange).lineLimit(1).help(error)
            }
        }
    }
}

private struct NotchBrightnessControls: View {
    @ObservedObject private var service = BrightnessService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var selectedID: CGDirectDisplayID?

    private var displays: [BrightnessDisplay] { service.displays.filter { $0.isActive && $0.method != nil } }
    private var display: BrightnessDisplay? {
        displays.first(where: { $0.id == selectedID }) ?? displays.first(where: \.isBuiltIn) ?? displays.first
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Label(FeatureStrings.notch(l10n.language).brightness, systemImage: "sun.max.fill")
                Spacer()
                if let display {
                    Menu {
                        ForEach(displays) { item in
                            Button(item.name) { selectedID = item.id }
                        }
                    } label: {
                        Text(display.name).lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: 140, alignment: .trailing)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
            .font(.system(size: 11, weight: .medium))
            if let display {
                HStack(spacing: 10) {
                    Slider(value: Binding(get: { display.brightness }, set: {
                        service.setBrightness($0, for: display.id, showOSD: true)
                    }), in: 0...1)
                        .controlSize(.small)
                        .accessibilityLabel(FeatureStrings.notch(l10n.language).brightness)
                    Text("\(BrightnessSupport.wholePercent(display.brightness))%")
                        .font(.system(size: 11, weight: .medium)).monospacedDigit()
                        .frame(width: 38, alignment: .trailing)
                }
            } else {
                Text(FeatureStrings.brightness(l10n.language).noDisplays)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { service.refresh() }
    }
}

struct NotchActionTile: View {
    let symbol: String
    let title: String
    var active = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 16, weight: .medium))
                    .foregroundStyle(active ? .mint : .white.opacity(0.85))
                Text(title).font(.system(size: 10, weight: .medium))
                    .lineLimit(2).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).frame(height: 54)
            .modifier(NotchControlSurface(cornerRadius: 14, selected: active))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

private struct NotchAwakeButton: View {
    @ObservedObject private var service = KeepAwakeManager.shared
    @ObservedObject private var l10n = L10n.shared
    var body: some View {
        NotchActionTile(symbol: service.isActive ? "cup.and.saucer.fill" : "cup.and.saucer",
                        title: l10n.s.keepAwakeTitle, active: service.isActive, action: service.toggle)
    }
}

private struct NotchMicButton: View {
    @ObservedObject private var service = MicMuteService.shared
    @ObservedObject private var l10n = L10n.shared
    var body: some View {
        NotchActionTile(symbol: service.isMuted ? "mic.slash.fill" : "mic.fill",
                        title: service.isMuted ? l10n.s.micUnmuteName : l10n.s.micMuteName,
                        active: service.isMuted, action: service.toggle)
    }
}

private struct NotchRecorderButton: View {
    let service: NotchService
    @ObservedObject private var recorder = ScreenRecorderService.shared
    @ObservedObject private var l10n = L10n.shared
    var body: some View {
        NotchActionTile(symbol: recorder.isRecording ? "stop.circle.fill" : "record.circle",
                        title: FeatureStrings.recorder(l10n.language).pageTitle,
                        active: recorder.isRecording) {
            service.perform { recorder.toggle() }
        }
    }
}
