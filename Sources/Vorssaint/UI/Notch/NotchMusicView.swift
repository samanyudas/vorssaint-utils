// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct NotchMusicView: View {
    var compact = true
    @ObservedObject private var service = NotchMusicService.shared
    @ObservedObject private var l10n = L10n.shared
    private var text: RadialMenuFeatureStrings { FeatureStrings.radialMenu(l10n.language) }

    var body: some View {
        VStack(spacing: 10) {
            if let playback = service.playback {
                HStack(spacing: 12) {
                    artwork
                    VStack(alignment: .leading, spacing: 4) {
                        Text(playback.track.title ?? text.mediaNowPlaying)
                            .font(.system(size: compact ? 16 : 18, weight: .semibold))
                            .lineLimit(2).help(playback.track.title ?? text.mediaNowPlaying)
                        if service.commandFailed {
                            Text(l10n.s.monitorUnavailable).font(.system(size: 11))
                                .foregroundStyle(.orange).lineLimit(1)
                        } else if let artist = playback.track.artist {
                            Text(artist).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        if !compact, let album = playback.track.album {
                            Text(album).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    NotchIconButton(symbol: "arrow.up.forward.app",
                                    title: RadialNowPlayingApplication.name(for: playback.track) ?? text.mediaNowPlaying) {
                        RadialNowPlayingApplication.open(playback.track)
                    }
                }
                .frame(height: compact ? 60 : 80)
                if playback.duration > 0 {
                    TimelineView(.animation(minimumInterval: 1, paused: !playback.isPlaying)) { context in
                        VStack(spacing: 3) {
                            ProgressView(value: playback.position(at: context.date), total: playback.duration)
                                .progressViewStyle(.linear).tint(.white.opacity(0.75)).frame(height: 4)
                            HStack {
                                Text(timestamp(playback.position(at: context.date)))
                                Spacer()
                                Text(timestamp(playback.duration))
                            }
                            .font(.system(size: 9)).monospacedDigit().foregroundStyle(.secondary)
                            .frame(height: 11)
                        }
                    }.frame(height: 18)
                }
                HStack(spacing: 36) {
                    playbackButton("backward.end.fill", title: text.mediaPrevious, command: .previous)
                    Button { service.send(.toggle) } label: {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .modifier(NotchControlSurface(cornerRadius: 22))
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain).accessibilityLabel(text.mediaPlayPause)
                    playbackButton("forward.end.fill", title: text.mediaNext, command: .next)
                }.frame(height: 44)
                Spacer(minLength: 0)
            } else {
                HStack(spacing: 14) {
                    Image(systemName: "music.note").font(.system(size: 26, weight: .light))
                    Text(text.mediaNothingPlaying).font(.system(size: 13, weight: .medium))
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 72)
                .accessibilityElement(children: .combine)
            }
            // Essential controls remain outside scrolling content, including
            // when metadata is long, playback is paused or a command fails.
            if AppFeature.mixer.isAvailable { NotchAudioControls() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var artwork: some View {
        Group {
            if let image = service.artwork {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Color.black.overlay {
                    Image(systemName: "music.note").font(.system(size: 24)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: compact ? 60 : 80, height: compact ? 60 : 80)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 12 : 16))
        .overlay { RoundedRectangle(cornerRadius: compact ? 12 : 16).stroke(.white.opacity(0.1), lineWidth: 0.5) }
    }

    private func playbackButton(_ symbol: String, title: String, command: NotchMusicService.Command) -> some View {
        Button { service.send(command) } label: {
            Image(systemName: symbol).font(.system(size: 21)).frame(width: 40, height: 40)
        }
        .buttonStyle(.plain).accessibilityLabel(title).help(title)
    }

    private func timestamp(_ interval: TimeInterval) -> String {
        let seconds = Int(max(0, interval))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
