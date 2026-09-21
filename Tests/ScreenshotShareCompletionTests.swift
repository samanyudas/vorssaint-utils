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
        func delete(_ record: ScreenshotShareRecord) async throws { revoked.append(record) }
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
    }
}
