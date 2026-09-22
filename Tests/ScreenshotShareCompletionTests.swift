// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Runs the production completion handler with controlled upload and clipboard results.
/// No network request or native preview is created.
enum ScreenshotShareCompletionTests {
    final class Model {
        var sharing = false
        var sharedRecord: ScreenshotShareRecord?
    }

    class State {
        var closed = false
        let model = Model()
        var dismissWork: DispatchWorkItem?
        var autoDismissDuration: TimeInterval = 12
        var completion: (@MainActor (ScreenshotShareRecord?) -> Void)?
        var copies: [ScreenshotShareRecord] = []
        var copySucceeds = true
        var retryScheduled = false
        var showingLink = false

        func share(_ duration: ScreenshotShareDuration,
                   completion: @escaping @MainActor (ScreenshotShareRecord?) -> Void) {
            self.completion = completion
        }
        func copyLinkAndClose(_ record: ScreenshotShareRecord) -> Bool {
            copies.append(record)
            if copySucceeds { closed = true }
            return copySucceeds
        }
        func scheduleAutoDismiss() { retryScheduled = true }
        func resizePanel(showingLink: Bool) { self.showingLink = showingLink }
    }

    @MainActor final class ScreenshotShareService {
        static let shared = ScreenshotShareService()
        var revoked: [ScreenshotShareRecord] = []
        var records: [ScreenshotShareRecord] = []
        var copies: [URL] = []
        var clipboard = "new capture"
        var copySucceeds = true
        func copy(_ url: URL) -> Bool {
            copies.append(url)
            if copySucceeds { clipboard = url.absoluteString }
            return copySucceeds
        }
        func delete(_ record: ScreenshotShareRecord) async throws { revoked.append(record) }
    }

    enum AppFeature {
        case screenshot
        var isAvailable: Bool { true }
    }

    enum ScreenshotLastCaptureStore {
        static func load() -> Int? { 1 }
    }

    enum QuickToolHUD {
        static func show(icon: String, message: String) {}
    }

    final class ScreenshotQuickPreviewController {
        var closed = false
        var onClose: () -> Void = {}
        func close() { closed = true; onClose() }
    }

    @MainActor class UploadState {
        let defaultsName = "vorss.tests.screenshot-shortcut.\(UUID().uuidString)"
        let defaults: UserDefaults
        let strings = ScreenshotFeatureStrings.enUS
        var uploadingLatestCapture = false
        var latestCaptureID = UUID()
        var linkCopyRetry = ScreenshotLinkCopyRetry()
        var preview: ScreenshotQuickPreviewController?
        var completion: (@MainActor (ScreenshotShareRecord?) -> Void)?
        var uploads = 0

        init() {
            defaults = UserDefaults(suiteName: defaultsName)!
            defaults.set(true, forKey: DefaultsKey.screenshotUploadShortcutEnabled)
            defaults.set(true, forKey: DefaultsKey.screenshotSharingEnabled)
        }
        deinit {
            UserDefaults(suiteName: defaultsName)?.removePersistentDomain(forName: defaultsName)
        }
        func shareDirect(_ capture: Int, duration: ScreenshotShareDuration,
                         completion: @escaping @MainActor (ScreenshotShareRecord?) -> Void) {
            uploads += 1
            self.completion = completion
        }
        func showPreview() -> ScreenshotQuickPreviewController {
            let controller = ScreenshotQuickPreviewController()
            controller.onClose = { [weak self] in self?.preview = nil }
            preview = controller
            return controller
        }
    }

    static func run(_ suite: TestSuite) {
        var finished = false
        Task { @MainActor in
            await checks(suite)
            finished = true
        }
        let deadline = Date().addingTimeInterval(10)
        while !finished && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        suite.expect(finished, "screenshot upload completion tests finish")
    }

    @MainActor static func checks(_ suite: TestSuite) async {
        let record = ScreenshotShareRecord(id: "test", endpoint: URL(string: "https://example.com")!,
                                          expiresAt: Date().addingTimeInterval(3_600), deleteToken: "test")
        let service = ScreenshotShareService.shared
        service.revoked = []
        let open = Controller()
        open.performShare(.oneHour)
        open.completion?(record)
        suite.expect(open.copies == [record] && open.closed,
                     "upload completion copies and closes before returning, without a deferred handoff")
        for _ in 0..<20 { await Task.yield() }
        suite.expect(service.revoked.isEmpty, "a delivered link stays active")

        let closingAfterCallback = Controller()
        closingAfterCallback.performShare(.oneHour)
        closingAfterCallback.completion?(record)
        closingAfterCallback.closed = true
        for _ in 0..<20 { await Task.yield() }
        suite.expect(closingAfterCallback.copies == [record] || service.revoked == [record],
                     "closing immediately after the callback cannot leave a link neither delivered nor revoked")
        service.revoked = []

        let closed = Controller()
        closed.performShare(.oneHour)
        closed.closed = true
        closed.completion?(record)
        for _ in 0..<20 { await Task.yield() }
        suite.expect(service.revoked == [record] && closed.copies.isEmpty,
                     "closing before upload completion revokes the link without copying it")

        service.revoked = []
        var released: Controller? = Controller()
        released?.performShare(.oneHour)
        let completion = released?.completion
        released = nil
        completion?(record)
        for _ in 0..<20 { await Task.yield() }
        suite.expect(service.revoked == [record], "releasing the preview also revokes an undelivered link")

        let failedCopy = Controller()
        failedCopy.copySucceeds = false
        failedCopy.performShare(.oneHour)
        failedCopy.completion?(record)
        suite.expect(!failedCopy.closed && failedCopy.model.sharedRecord == record
                     && failedCopy.showingLink && failedCopy.retryScheduled,
                     "clipboard failure retains the existing link and copy controls in the preview")

        for scenario in ["open", "closed", "released", "replaced", "standalone", "owner released"] {
            service.revoked = []
            service.copies = []
            service.clipboard = "new capture"
            var uploader: Uploader? = Uploader()
            var preview: ScreenshotQuickPreviewController? = scenario == "standalone"
                ? nil : uploader!.showPreview()
            uploader!.uploadLastCapture()
            uploader!.uploadLastCapture()
            suite.expect(uploader!.uploads == 1, "pending shortcut upload ignores duplicate presses")
            let completion = uploader!.completion
            if ["closed", "released", "replaced"].contains(scenario) { preview?.close() }
            if scenario == "released" { preview = nil }
            if scenario == "replaced" {
                uploader!.latestCaptureID = UUID()
                _ = uploader!.showPreview()
            }
            if scenario == "owner released" { uploader = nil }
            completion?(record)
            for _ in 0..<20 { await Task.yield() }
            if ["open", "standalone"].contains(scenario) {
                suite.expect(service.copies == [record.url] && service.revoked.isEmpty,
                             "\(scenario) shortcut upload delivers its link")
                if scenario == "open" {
                    suite.expect(preview?.closed == true, "successful shortcut copy closes its preview")
                }
            } else {
                suite.expect(service.copies.isEmpty && service.clipboard == "new capture"
                             && service.revoked == [record],
                             "\(scenario) shortcut upload should revoke and preserve clipboard; "
                             + "copies=\(service.copies.count), revoked=\(service.revoked.count), "
                             + "clipboard=\(service.clipboard)")
            }
            if let uploader {
                suite.expect(!uploader.uploadingLatestCapture, "completion clears pending shortcut upload")
            }
        }
        service.revoked = []
        service.copies = []
        service.records = [record]
        service.copySucceeds = false
        let retry = Uploader()
        let retryPreview = retry.showPreview()
        retry.uploadLastCapture()
        retry.completion?(record)
        suite.expect(!retryPreview.closed, "failed shortcut copy keeps its preview open")
        service.copySucceeds = true
        retry.uploadLastCapture()
        suite.expect(retry.uploads == 1 && service.copies == [record.url, record.url]
                     && retryPreview.closed, "shortcut retries a failed copy without another upload")
        service.records = []
        let failedUpload = Uploader()
        failedUpload.uploadLastCapture()
        failedUpload.completion?(nil)
        suite.expect(!failedUpload.uploadingLatestCapture, "failed upload clears pending shortcut state")
    }
}
