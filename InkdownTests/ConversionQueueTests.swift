import XCTest
@testable import Inkdown

// Checks that PDFs are converted one after another, that the status is
// reported, and that Cancel writes nothing.
@MainActor
final class ConversionQueueTests: XCTestCase {

    private var written: [(String, URL)] = []
    private var statuses: [QueueStatus] = []
    private var outcomes: [JobOutcome] = []
    private var savedElsewhere: URL?

    override func setUp() {
        savedElsewhere = nil
        written = []
        statuses = []
        outcomes = []
    }

    private func job(_ name: String) -> Job {
        Job(pdf: URL(fileURLWithPath: "/tmp/\(name).pdf"), output: URL(fileURLWithPath: "/tmp/\(name).md"))
    }

    // A queue whose pages take `delay` seconds each and whose split fails
    // for any PDF called "broken".
    private func makeQueue(pagesPerPDF: Int = 2, delay: Double = 0, writeFails: Bool = false) -> ConversionQueue {
        let queue = ConversionQueue(
            split: { url in
                if url.lastPathComponent == "broken.pdf" { throw ConversionError.cannotOpen }
                return (0..<pagesPerPDF).map { Data([UInt8($0)]) }
            },
            makeConverter: {
                Converter(transcribe: { _, page, _ in
                    if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                    return PageAnswer(text: "P\(page)", inputTokens: 1000, outputTokens: 100, cutOff: false)
                }, retryDelays: [])
            },
            write: { [unowned self] text, url in
                if writeFails { throw CocoaError(.fileWriteNoPermission) }
                self.written.append((text, url))
                return self.savedElsewhere ?? url
            })
        queue.onStatus = { [unowned self] in self.statuses.append($0) }
        queue.onOutcome = { [unowned self] in self.outcomes.append($0) }
        return queue
    }

    // Waits until the condition holds, at most two seconds.
    private func wait(until condition: () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func testTwoJobsRunInOrderAndBothAreWritten() async {
        let queue = makeQueue()
        queue.add(job("a"))
        queue.add(job("b"))
        await wait { self.outcomes.count == 2 && !queue.isBusy }

        XCTAssertEqual(written.map(\.1.lastPathComponent), ["a.md", "b.md"])
        XCTAssertEqual(written.first?.0, "<!-- Page 1 -->\n\nP1\n\n<!-- Page 2 -->\n\nP2\n")
        XCTAssertFalse(queue.isBusy)
        guard case .done(let output, let result) = outcomes.first else { return XCTFail("Expected done") }
        XCTAssertEqual(output.lastPathComponent, "a.md")
        XCTAssertEqual(result.pageCount, 2)
    }

    func testStatusGoesFromConvertingToIdleWithTheLastResult() async {
        let queue = makeQueue()
        queue.add(job("a"))
        await wait { !queue.isBusy && self.outcomes.count == 1 }
        await wait { self.statuses.last == .idle(last: "a.md — 2 pages, about $0.01") }

        XCTAssertTrue(statuses.contains(.converting(name: "a.pdf", done: 0, total: 2)))
        XCTAssertEqual(statuses.last, .idle(last: "a.md — 2 pages, about $0.01"))
    }

    func testABrokenPDFIsReportedAndTheNextStillRuns() async {
        let queue = makeQueue()
        queue.add(job("broken"))
        queue.add(job("b"))
        await wait { self.outcomes.count == 2 && !queue.isBusy }

        XCTAssertEqual(outcomes.first, .failed(pdf: URL(fileURLWithPath: "/tmp/broken.pdf"), error: .cannotOpen))
        XCTAssertEqual(written.map(\.1.lastPathComponent), ["b.md"])
    }

    func testAFailedSaveIsReported() async {
        let queue = makeQueue(writeFails: true)
        queue.add(job("a"))
        await wait { self.outcomes.count == 1 }
        XCTAssertEqual(outcomes, [.failed(pdf: URL(fileURLWithPath: "/tmp/a.pdf"), error: .cannotWrite)])
    }

    func testCancelWritesNothingAndClearsTheQueue() async {
        let queue = makeQueue(delay: 0.3)
        queue.add(job("a"))
        queue.add(job("b"))
        try? await Task.sleep(nanoseconds: 50_000_000)

        queue.cancelAll()
        XCTAssertFalse(queue.isBusy)
        XCTAssertEqual(statuses.last, .idle(last: nil))

        // Give the cancelled work time to finish; it must stay silent.
        try? await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertTrue(written.isEmpty)
        XCTAssertTrue(outcomes.isEmpty)
        XCTAssertEqual(statuses.last, .idle(last: nil))
    }

    func testANewJobRunsAfterCancel() async {
        let queue = makeQueue(delay: 0.2)
        queue.add(job("a"))
        try? await Task.sleep(nanoseconds: 50_000_000)
        queue.cancelAll()

        queue.add(job("c"))
        await wait { self.outcomes.count == 1 && !queue.isBusy }
        XCTAssertEqual(written.map(\.1.lastPathComponent), ["c.md"])
    }

    // Review finding: the same PDF queued twice was converted and paid twice.
    func testTheQueueKnowsWhatItIsWorkingOn() async {
        let queue = makeQueue(delay: 0.2)
        queue.add(job("a"))
        queue.add(job("b"))

        XCTAssertTrue(queue.isQueued(URL(fileURLWithPath: "/tmp/a.pdf")))
        XCTAssertTrue(queue.isQueued(URL(fileURLWithPath: "/tmp/b.pdf")))
        XCTAssertFalse(queue.isQueued(URL(fileURLWithPath: "/tmp/c.pdf")))
        XCTAssertEqual(queue.reservedOutputs.map(\.lastPathComponent).sorted(), ["a.md", "b.md"])

        await wait { !queue.isBusy }
        XCTAssertFalse(queue.isQueued(URL(fileURLWithPath: "/tmp/a.pdf")))
        XCTAssertEqual(queue.reservedOutputs, [])
    }

    // Review finding: when saving next to the PDF fails, the user picks
    // another place. The result must then point at the real file.
    func testTheOutcomeNamesWhereTheFileReallyWent() async {
        savedElsewhere = URL(fileURLWithPath: "/tmp/elsewhere/a.md")
        let queue = makeQueue()
        queue.add(job("a"))
        await wait { self.outcomes.count == 1 }

        guard case .done(let output, _) = outcomes.first else { return XCTFail("Expected done") }
        XCTAssertEqual(output.path, "/tmp/elsewhere/a.md")
    }

    func testLastLineMentionsCutOffPages() {
        let url = URL(fileURLWithPath: "/tmp/notes.md")
        let result = ConversionResult(markdown: "x", pageCount: 5, unreadablePages: [], incompletePages: [4],
                                      inputTokens: 0, outputTokens: 0)
        XCTAssertTrue(ConversionQueue.lastLine(output: url, result: result).hasSuffix(", 1 page cut off"))
    }

    func testLastLineDescribesTheResult() {
        let url = URL(fileURLWithPath: "/tmp/notes.md")
        // 100,000 tokens in and 11,000 out cost $0.20 + $0.11 = $0.31.
        let twelve = ConversionResult(markdown: "x", pageCount: 12, unreadablePages: [], incompletePages: [],
                                      inputTokens: 100_000, outputTokens: 11_000)
        XCTAssertEqual(ConversionQueue.lastLine(output: url, result: twelve), "notes.md — 12 pages, about $0.31")

        let one = ConversionResult(markdown: "x", pageCount: 1, unreadablePages: [1], incompletePages: [], inputTokens: 0, outputTokens: 0)
        XCTAssertEqual(ConversionQueue.lastLine(output: url, result: one), "notes.md — 1 page, about $0.00, 1 page unreadable")

        let two = ConversionResult(markdown: "x", pageCount: 5, unreadablePages: [2, 4], incompletePages: [], inputTokens: 0, outputTokens: 0)
        XCTAssertTrue(ConversionQueue.lastLine(output: url, result: two).hasSuffix(", 2 pages unreadable"))

        let empty = ConversionResult(markdown: "", pageCount: 3, unreadablePages: [], incompletePages: [], inputTokens: 0, outputTokens: 0)
        XCTAssertTrue(ConversionQueue.lastLine(output: url, result: empty).hasSuffix(", no text found"))
    }

    func testStatusTexts() {
        XCTAssertEqual(QueueStatus.idle(last: nil).menuTitle, "Ready")
        XCTAssertEqual(QueueStatus.idle(last: nil).iconTitle, "")
        XCTAssertEqual(QueueStatus.idle(last: "a.md — 1 page, about $0.02").menuTitle, "a.md — 1 page, about $0.02")
        XCTAssertEqual(QueueStatus.converting(name: "notes.pdf", done: 2, total: 12).menuTitle,
                       "Converting notes.pdf — page 3 of 12")
        XCTAssertEqual(QueueStatus.converting(name: "notes.pdf", done: 12, total: 12).menuTitle,
                       "Converting notes.pdf — page 12 of 12")
        XCTAssertEqual(QueueStatus.converting(name: "notes.pdf", done: 3, total: 12).iconTitle, "3/12")
    }
}
