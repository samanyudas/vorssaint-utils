// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct NotchSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.notchEnabled) private var enabled = false
    @AppStorage(DefaultsKey.notchDisplay) private var display = NotchDisplay.automatic.rawValue
    @AppStorage(DefaultsKey.notchOpenOnHover) private var hover = true
    @AppStorage(DefaultsKey.notchHiddenModules) private var hidden = ""
    @AppStorage(DefaultsKey.notchModuleOrder) private var order = ""
    @AppStorage(DefaultsKey.notchVolume) private var volume = true
    @AppStorage(DefaultsKey.notchBrightness) private var brightness = true
    @AppStorage(DefaultsKey.notchBattery) private var battery = true
    @AppStorage(DefaultsKey.notchClipboard) private var clipboard = false
    @AppStorage(DefaultsKey.notchClipboardWindow) private var clipboardWindow = false
    @AppStorage(DefaultsKey.screenshotDefaultAction) private var captureAction = ""
    @AppStorage(DefaultsKey.notchCapture) private var capture = false
    @AppStorage(DefaultsKey.notchShowPlayingMusic) private var showPlayingMusic = true
    @AppStorage(DefaultsKey.notchIdleContent) private var idle = NotchIdleContent.none.rawValue
    @AppStorage(DefaultsKey.notchHiddenControls) private var hiddenControls = "mixer,commandBar"
    @AppStorage(DefaultsKey.notchControlOrder) private var controlOrder = ""
    @AppStorage(DefaultsKey.notchShowInCaptures) private var showInCaptures = true
    @AppStorage(DefaultsKey.notchSize) private var size = NotchSize.compact.rawValue
    @AppStorage(DefaultsKey.notchCustomWidth) private var customWidth = NotchSize.defaultWidth
    @AppStorage(DefaultsKey.notchCustomHeight) private var customHeight = NotchSize.defaultHeight
    @AppStorage(DefaultsKey.notchHapticFeedback) private var hapticFeedback = false
    @AppStorage(DefaultsKey.notchShelf) private var shelfWindow = true
    @AppStorage(DefaultsKey.notchDragReveal) private var dragReveal = true
    @AppStorage(DefaultsKey.notchCaptureControls) private var captureControls = true
    @AppStorage(DefaultsKey.notchQuickPanel) private var quickPanel = true
    @AppStorage(DefaultsKey.notchAppPanel) private var appPanel = true
    @AppStorage(DefaultsKey.notchHoverExpands) private var hoverExpand = false
    private var text: NotchStrings { FeatureStrings.notch(l10n.language) }

    private var configuration: [String] {
        [String(enabled), String(showPlayingMusic), idle, hiddenControls, controlOrder, size,
         String(customWidth), String(customHeight), String(hapticFeedback), String(shelfWindow), String(dragReveal), String(captureControls), String(quickPanel), String(appPanel), String(hoverExpand), display, String(hover), hidden, order, String(volume),
         String(brightness), String(battery), String(clipboard), String(clipboardWindow), String(capture), captureAction, String(showInCaptures)]
    }

    private var orderedModules: [NotchModule] {
        let stored = order.split(separator: ",").compactMap { NotchModule(rawValue: String($0)) }
        var seen = Set<NotchModule>()
        return (stored + NotchModule.allCases).filter { seen.insert($0).inserted }
    }

    var body: some View {
        Form {
            Section {
                preview
                HStack {
                    Toggle(text.enable, isOn: $enabled)
                    Button(text.open) { NotchService.shared.open() }
                        .disabled(!enabled)
                }
                Text(text.description).font(.caption).foregroundStyle(.secondary)
            } header: { Text(text.title) }

            Section {
                Picker(text.size, selection: $size) {
                    Text(text.compact).tag(NotchSize.compact.rawValue)
                    Text(text.spacious).tag(NotchSize.spacious.rawValue)
                    Text(text.custom).tag(NotchSize.custom.rawValue)
                }
                if size == NotchSize.custom.rawValue {
                    dimensionSlider(text.width, value: $customWidth, range: NotchSize.widthRange,
                                    fallback: NotchSize.defaultWidth)
                    dimensionSlider(text.maximumHeight, value: $customHeight, range: NotchSize.heightRange,
                                    fallback: NotchSize.defaultHeight)
                    Text(text.sizeHint).font(.caption).foregroundStyle(.secondary)
                }
                Toggle(text.hover, isOn: $hover)
                DisclosureGroup(text.modules) {
                    ForEach(orderedModules) { module in
                        HStack {
                            Toggle(isOn: moduleBinding(module)) {
                                Label(module.title(l10n.language), systemImage: module.symbol)
                            }
                            .disabled(!module.isAvailable())
                            Spacer()
                            Button { move(module, by: -1) } label: { Image(systemName: "chevron.up") }
                                .disabled(orderedModules.first == module)
                                .help(FeatureStrings.clipboard(l10n.language).moveUp)
                                .accessibilityLabel(FeatureStrings.clipboard(l10n.language).moveUp)
                            Button { move(module, by: 1) } label: { Image(systemName: "chevron.down") }
                                .disabled(orderedModules.last == module)
                                .help(FeatureStrings.clipboard(l10n.language).moveDown)
                                .accessibilityLabel(FeatureStrings.clipboard(l10n.language).moveDown)
                        }
                        .controlSize(.small)
                    }
                    if orderedModules.contains(where: { !$0.isAvailable() }) {
                        Text(text.disabled).font(.caption).foregroundStyle(.secondary)
                    }
                }
                DisclosureGroup(text.events) {
                    Picker(text.idleContent, selection: $idle) {
                        Text(text.idleNone).tag(NotchIdleContent.none.rawValue)
                        Text(text.battery).tag(NotchIdleContent.battery.rawValue)
                        Text(FeatureStrings.radialMenu(l10n.language).mediaNowPlaying).tag(NotchIdleContent.music.rawValue)
                        Text(text.controls).tag(NotchIdleContent.controls.rawValue)
                    }
                    Picker(text.display, selection: $display) {
                        Text(text.automatic).tag(NotchDisplay.automatic.rawValue)
                        Text(text.builtIn).tag(NotchDisplay.builtIn.rawValue)
                        Text(text.mainDisplay).tag(NotchDisplay.main.rawValue)
                    }
                    Toggle(text.hoverExpand, isOn: $hoverExpand).disabled(!hover)
                    Toggle(text.hapticFeedback, isOn: $hapticFeedback)
                    Text(text.hapticHint).font(.caption).foregroundStyle(.secondary)
                    Toggle(text.appPanel, isOn: $appPanel)
                    Toggle(text.quickPanel, isOn: $quickPanel).disabled(!AppFeature.quickLauncher.isAvailable)
                    Toggle(text.shelfWindow, isOn: $shelfWindow).disabled(!AppFeature.shelf.isAvailable)
                    Toggle(text.dragReveal, isOn: $dragReveal).disabled(!shelfWindow || !AppFeature.shelf.isAvailable)
                    Toggle(text.captureControls, isOn: $captureControls)

                    DisclosureGroup(text.controlShortcuts) {
                        ForEach(orderedControls) { item in
                            HStack {
                                Toggle(item.title(l10n), isOn: controlBinding(item)).disabled(!item.isAvailable())
                                if item != .volume && item != .brightness {
                                    Spacer()
                                    Button { moveControl(item, by: -1) } label: { Image(systemName: "chevron.up") }
                                        .disabled(orderedShortcuts.first == item)
                                        .accessibilityLabel(FeatureStrings.clipboard(l10n.language).moveUp)
                                    Button { moveControl(item, by: 1) } label: { Image(systemName: "chevron.down") }
                                        .disabled(orderedShortcuts.last == item)
                                        .accessibilityLabel(FeatureStrings.clipboard(l10n.language).moveDown)
                                }
                            }.controlSize(.small)
                        }
                    }
                    Text(text.activity).font(.caption).foregroundStyle(.secondary)
                    Toggle(text.playingMusic, isOn: $showPlayingMusic)
                        .disabled(!NotchSupport.modules().contains(.music))
                    Toggle(text.volume, isOn: $volume).disabled(!AppFeature.mixer.isAvailable)
                    Toggle(text.brightness, isOn: $brightness).disabled(!AppFeature.brightness.isAvailable)
                    Toggle(text.battery, isOn: $battery).disabled(!AppFeature.monitorPower.isAvailable)
                    Toggle(text.showInCaptures, isOn: $showInCaptures)
                    Toggle(text.clipboardWindow, isOn: $clipboardWindow)
                        .disabled(!AppFeature.clipboardHistory.isAvailable)
                    Toggle(text.clipboardActivity, isOn: $clipboard)
                        .disabled(!AppFeature.clipboardHistory.isAvailable)
                    Toggle(text.captureActivity, isOn: $capture).disabled(!AppFeature.screenshot.isAvailable)
                    if capture, AppFeature.screenshot.isAvailable {
                        ScreenshotDefaultActionPicker(strings: FeatureStrings.screenshot(l10n.language),
                                                      selection: $captureAction)
                    }
                    Text(text.privacy).font(.caption).foregroundStyle(.secondary)
                    if enabled, (volume || brightness), !permissions.accessibility {
                        PermissionRow(kind: .accessibility)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: configuration) { _, _ in
            NotchService.shared.syncWithPreferences()
            if AppFeature.brightness.isAvailable { BrightnessService.shared.syncWithPreferences() }
        }
    }

    private func dimensionSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
                                 fallback: Double) -> some View {
        let bounded = Binding(get: { NotchSize.clamped(value.wrappedValue, to: range, fallback: fallback) },
                              set: { value.wrappedValue = $0 })
        return HStack {
            Slider(value: bounded, in: range, step: 10) { Text(title) }
            Text(bounded.wrappedValue, format: .number.precision(.fractionLength(0)))
                .monospacedDigit().foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }

    private var preview: some View {
        VStack(spacing: 12) {
            HStack(spacing: 25) {
                Image(systemName: "music.note").foregroundStyle(.mint)
                Color.clear.frame(width: 28)
                Image(systemName: "waveform").foregroundStyle(.mint)
            }
            .font(.system(size: 13, weight: .medium))
            .opacity(idle == NotchIdleContent.none.rawValue ? 0 : 1)
            .frame(width: 182, height: 34)
            .background(.black, in: UnevenRoundedRectangle(bottomLeadingRadius: 15, bottomTrailingRadius: 15))
            HStack(spacing: 14) {
                ForEach(NotchModule.allCases) { module in
                    Image(systemName: module.symbol).font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityHidden(true)
    }

    private var orderedControls: [NotchControlItem] {
        [.volume, .brightness] + orderedShortcuts
    }

    private var orderedShortcuts: [NotchControlItem] {
        let stored = controlOrder.split(separator: ",").compactMap { NotchControlItem(rawValue: String($0)) }
        var seen = Set<NotchControlItem>()
        return (stored + NotchControlItem.allCases).filter {
            $0 != .volume && $0 != .brightness && seen.insert($0).inserted
        }
    }

    private func controlBinding(_ item: NotchControlItem) -> Binding<Bool> {
        Binding {
            !hiddenControls.split(separator: ",").contains(Substring(item.rawValue))
        } set: { shown in
            var values = Set(hiddenControls.split(separator: ",").map(String.init))
            if shown { values.remove(item.rawValue) } else { values.insert(item.rawValue) }
            hiddenControls = values.sorted().joined(separator: ",")
        }
    }

    private func moveControl(_ item: NotchControlItem, by offset: Int) {
        var items = orderedShortcuts
        guard let index = items.firstIndex(of: item), items.indices.contains(index + offset) else { return }
        items.swapAt(index, index + offset)
        controlOrder = items.map(\.rawValue).joined(separator: ",")
    }

    private func moduleBinding(_ module: NotchModule) -> Binding<Bool> {
        Binding {
            !hidden.split(separator: ",").contains(Substring(module.rawValue))
        } set: { shown in
            var values = Set(hidden.split(separator: ",").map(String.init))
            if shown { values.remove(module.rawValue) } else { values.insert(module.rawValue) }
            hidden = values.sorted().joined(separator: ",")
        }
    }

    private func move(_ module: NotchModule, by offset: Int) {
        var modules = orderedModules
        guard let index = modules.firstIndex(of: module), modules.indices.contains(index + offset) else { return }
        modules.swapAt(index, index + offset)
        order = modules.map(\.rawValue).joined(separator: ",")
    }
}
