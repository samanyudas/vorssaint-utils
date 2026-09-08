// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

final class NotchMusicService: ObservableObject {
    static let shared = NotchMusicService()
    @Published private(set) var playback: NotchPlayback?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var commandFailed = false
    private var process: Process?
    private var output: Pipe?
    private var input: Pipe?
    private var generation = UUID()
    private let queue = DispatchQueue(label: "com.vorssaint.notch-music", qos: .utility)

    private init() {}

    private static var adapter: [String]? {
        guard let script = Bundle.main.url(forResource: "now-playing", withExtension: "pl"),
              let library = Bundle.main.privateFrameworksURL?.appendingPathComponent("libVorssaintNowPlaying.dylib"),
              FileManager.default.fileExists(atPath: library.path) else { return nil }
        return [script.path, library.path]
    }

    func start() {
        guard process == nil, let arguments = Self.adapter else { return }
        let process = Process()
        let output = Pipe()
        let input = Pipe()
        // A child can exit between checking isRunning and writing a command.
        // Keep that race an error, never a SIGPIPE that terminates the app.
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else { return }
        let requested = UUID()
        generation = requested
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = arguments + ["watch"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = input
        var cachedArtwork: Data?
        var cachedImage: NSImage?
        let reader = NotchMusicPipeReader { [weak self] data in
            if let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let sent = reply["sent"] as? Bool {
                DispatchQueue.main.async {
                    guard let self, self.generation == requested else { return }
                    self.commandFailed = !sent
                }
                return
            }
            let next = NotchPlayback.decode(data, previousArtwork: cachedArtwork)
            if cachedArtwork != next?.track.artworkData {
                cachedArtwork = next?.track.artworkData
                cachedImage = cachedArtwork.flatMap { ImageThumbnailer.thumbnail(data: $0, pointSize: 96, scale: 2) }
            }
            let image = cachedImage
            DispatchQueue.main.async {
                guard let self, self.generation == requested else { return }
                self.artwork = image
                self.playback = next
            }
        }
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            else { reader.append(data) }
        }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.generation == requested else { return }
                self.stop()
            }
        }
        do {
            try process.run()
            self.process = process
            self.output = output
            self.input = input
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
        }
    }

    func stop() {
        generation = UUID()
        output?.fileHandleForReading.readabilityHandler = nil
        try? input?.fileHandleForWriting.close()
        if let process, process.isRunning {
            process.terminate()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        process = nil
        input = nil
        output = nil
        playback = nil
        artwork = nil
        commandFailed = false
    }

    enum Command: String { case toggle, next, previous }

    func send(_ command: Command) {
        guard playback != nil, process?.isRunning == true, let input else { return }
        let requested = generation
        commandFailed = false
        queue.async { [weak self] in
            do {
                // Native transport commands are asynchronous. The watch
                // process keeps its run loop alive until the request arrives.
                try input.fileHandleForWriting.write(contentsOf: Data((command.rawValue + "\n").utf8))
            } catch {
                DispatchQueue.main.async {
                    guard let self, self.generation == requested else { return }
                    self.commandFailed = true
                }
            }
        }
    }

}

/// Pipe callbacks may split a UTF-8 character or join several replies. Parsing
/// stays serial and bounded before any metadata reaches the main thread.
private final class NotchMusicPipeReader {
    private let queue = DispatchQueue(label: "com.vorssaint.notch-music-reader", qos: .utility)
    private var buffer = Data()
    private let receive: (Data) -> Void
    init(receive: @escaping (Data) -> Void) { self.receive = receive }

    func append(_ data: Data) {
        // Backpressure keeps native metadata bursts from queuing unbounded
        // buffers. The pipe invokes this off-main and delivery never waits on UI.
        queue.sync {
            self.buffer.append(data)
            if self.buffer.count > RadialNowPlayingSupport.maximumAdapterReplyBytes {
                self.buffer.removeAll(keepingCapacity: false)
                return
            }
            while let end = self.buffer.firstIndex(of: 0x0A) {
                let line = Data(self.buffer[..<end])
                self.buffer.removeSubrange(...end)
                self.receive(line)
            }
        }
    }
}
