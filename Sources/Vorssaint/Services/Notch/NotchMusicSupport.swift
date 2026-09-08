// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchPlayback: Equatable {
    let track: RadialNowPlayingSnapshot
    let isPlaying: Bool
    let elapsed: TimeInterval
    let duration: TimeInterval
    let rate: Double
    let sampledAt: Date

    func position(at date: Date) -> TimeInterval {
        min(duration, max(0, elapsed + (isPlaying ? max(0, date.timeIntervalSince(sampledAt)) * rate : 0)))
    }

    static func decode(_ data: Data, now: Date = Date(), previousArtwork: Data? = nil) -> NotchPlayback? {
        guard let reply = RadialNowPlayingSupport.adapterReply(from: data) else { return nil }
        var info = reply.info
        if info["artworkUnchanged"] as? Bool == true {
            info[RadialNowPlayingSupport.artworkDataKey] = previousArtwork
        }
        guard let track = RadialNowPlayingSupport.snapshot(
                info: info, isPlaying: true,
                appBundleIdentifier: reply.displayID, appPID: reply.pid) else { return nil }
        func seconds(_ key: String) -> Double {
            guard let value = (reply.info[key] as? NSNumber)?.doubleValue,
                  value.isFinite, value >= 0 else { return 0 }
            return min(value, 7 * 24 * 60 * 60)
        }
        let rawRate = (reply.info[RadialNowPlayingSupport.playbackRateKey] as? NSNumber)?.doubleValue
        let rate: Double
        if let rawRate, rawRate.isFinite { rate = min(16, max(0, rawRate)) }
        else { rate = 1 }
        return NotchPlayback(track: track,
                             isPlaying: RadialNowPlayingSupport.playbackIsActive(
                                remoteIsPlaying: reply.isPlaying, info: reply.info),
                             elapsed: seconds("kMRMediaRemoteNowPlayingInfoElapsedTime"),
                             duration: seconds("kMRMediaRemoteNowPlayingInfoDuration"),
                             rate: rate, sampledAt: now)
    }
}
