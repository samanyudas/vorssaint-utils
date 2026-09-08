// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Playback lives beside the camera; no title or artwork crosses its safe area.
struct NotchMusicStrip: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var title: String { music.playback?.track.title ?? FeatureStrings.radialMenu(l10n.language).mediaNowPlaying }

    var body: some View {
        Button { service.open(.music) } label: {
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    if service.geometry.musicWingWidth >= 40 {
                        Group {
                            if let image = music.artwork {
                                Image(nsImage: image).resizable().scaledToFill()
                            } else {
                                Color.black.overlay { Image(systemName: "music.note").foregroundStyle(.secondary) }
                            }
                        }
                        .frame(width: min(26, service.geometry.menuBarHeight - 6), height: min(26, service.geometry.menuBarHeight - 6))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        if service.geometry.musicWingWidth >= 94 {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(title)
                                    .font(.system(size: 11, weight: .semibold))
                                if service.geometry.menuBarHeight >= 30, let artist = music.playback?.track.artist {
                                    Text(artist).font(.system(size: 9)).foregroundStyle(.secondary)
                                }
                            }
                            .lineLimit(1).truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.leading, service.geometry.musicWingWidth >= 40 ? 10 : 0)
                .padding(.trailing, service.geometry.musicWingWidth >= 40 ? 4 : 0)
                .frame(width: service.geometry.musicWingWidth)
                .clipped()
                Color.clear.frame(width: service.geometry.musicCameraGap)
                HStack {
                    Spacer(minLength: 0)
                    if service.geometry.musicWingWidth >= 36 {
                        Image(systemName: "waveform")
                            .font(.system(size: min(17, service.geometry.menuBarHeight - 8), weight: .medium))
                            .foregroundStyle(.mint)
                            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: !reduceMotion)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.trailing, service.geometry.musicWingWidth >= 36 ? 10 : 0)
                .frame(width: service.geometry.musicWingWidth)
            }
            .frame(height: service.geometry.musicStrip.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel([title, music.playback?.track.artist].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint(FeatureStrings.notch(l10n.language).open)
        .help(title)
    }
}
