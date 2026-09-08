// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The same selection model drives keyboard shortcuts and the screen overlay.
/// Only the controls change their destination; capture remains in its owner.
struct NotchCaptureControlsView: View {
    @ObservedObject var options: ScreenCaptureSelectionOptions
    let service: NotchService
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(FeatureStrings.screenshot(l10n.language).screenCaptureTitle)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                NotchIconButton(symbol: "xmark", title: l10n.s.menuClose, action: service.cancelCaptureControls)
            }
            HStack(spacing: 6) {
                ForEach(options.showsCaptureMenu ? options.availableTools : [options.selectedTool], id: \.self) { tool in
                    NotchActionTile(symbol: tool.systemImageName,
                                    title: tool.settingsTitle(l10n.s, language: l10n.language),
                                    active: options.selectedTool == tool) { options.select(tool) }
                }
            }
            if options.selectedTool == .recording {
                NotchRecordingAudioOptions(options: options.recorderAudio)
            }
        }
        .foregroundStyle(.white)
    }
}

private struct NotchRecordingAudioOptions: View {
    @ObservedObject var options: RecorderSelectionAudioOptions
    @ObservedObject private var l10n = L10n.shared
    var body: some View {
        HStack {
            Toggle(FeatureStrings.recorder(l10n.language).systemAudioTrackLabel, isOn: $options.systemAudio)
            Toggle(FeatureStrings.recorder(l10n.language).microphoneTrackLabel, isOn: $options.microphone)
        }.toggleStyle(.button).controlSize(.small)
    }
}
