import XCTest
@testable import Inkdown

// A stand-in for Claude. It decides per page and per try what to answer,
// and counts how it was used. An actor keeps the counting safe when
// several pages run at once.
actor FakeClaude {
    private(set) var calls = 0
    private(set) var callsPerPage: [Int: Int] = [:]
    private(set) var inFlight = 0
    private(set) var mostInFlight = 0

    // (page number, which try this is, starting at 1) -> answer or error
    let behave: @Sendable (Int, Int) async throws -> PageAnswer

    init(_ behave: @escaping @Sendable (Int, Int) async throws -> PageAnswer) {
        self.behave = behave
    }

    func transcribe(page: Int) async throws -> PageAnswer {
        calls += 1
        callsPerPage[page, default: 0] += 1
        let attempt = callsPerPage[page]!
        inFlight += 1
        mostInFlight = max(mostInFlight, inFlight)
        defer { inFlight -= 1 }
        return try await behave(page, attempt)
    }
}

// Checks that all pages are converted, retried and put in order.
final class ConverterTests: XCTestCase {

    private func answer(_ text: String, input: Int = 10, output: Int = 5, cutOff: Bool = false) -> PageAnswer {
        PageAnswer(text: text, inputTokens: input, outputTokens: output, cutOff: cutOff)
    }

    private func pages(_ count: Int) -> [Data] {
        (0..<count).map { Data([UInt8($0 % 250)]) }
    }

    private func converter(_ fake: FakeClaude, maxAtOnce: Int = 4) -> Converter {
        Converter(transcribe: { _, page, _ in try await fake.transcribe(page: page) },
                  retryDelays: [0, 0],
                  maxAtOnce: maxAtOnce)
    }

    func testPagesComeOutInOrderEvenIfTheFirstFinishesLast() async throws {
        let fake = FakeClaude { page, _ in
            if page == 1 { try await Task.sleep(nanoseconds: 200_000_000) }
            return PageAnswer(text: "P\(page)", inputTokens: 10, outputTokens: 5, cutOff: false)
        }
        let result = try await converter(fake).convert(pages: pages(3)) { _, _ in }

        XCTAssertEqual(result.markdown,
            "<!-- Page 1 -->\n\nP1\n\n<!-- Page 2 -->\n\nP2\n\n<!-- Page 3 -->\n\nP3\n")
        XCTAssertEqual(result.pageCount, 3)
        XCTAssertEqual(result.unreadablePages, [])
        XCTAssertEqual(result.inputTokens, 30)
        XCTAssertEqual(result.outputTokens, 15)
    }

    func testNeverMoreThanFourPagesAtOnce() async throws {
        let fake = FakeClaude { page, _ in
            try await Task.sleep(nanoseconds: 30_000_000)
            return PageAnswer(text: "P\(page)", inputTokens: 1, outputTokens: 1, cutOff: false)
        }
        _ = try await converter(fake).convert(pages: pages(12)) { _, _ in }

        let most = await fake.mostInFlight
        let calls = await fake.calls
        XCTAssertLessThanOrEqual(most, 4)
        XCTAssertGreaterThan(most, 1)
        XCTAssertEqual(calls, 12)
    }

    func testAPageThatKeepsFailingIsMarkedAndTheRestContinues() async throws {
        let fake = FakeClaude { page, _ in
            if page == 2 { throw ClaudeError.failed }
            return PageAnswer(text: "P\(page)", inputTokens: 1, outputTokens: 1, cutOff: false)
        }
        let result = try await converter(fake).convert(pages: pages(3)) { _, _ in }

        XCTAssertEqual(result.unreadablePages, [2])
        XCTAssertTrue(result.markdown.contains("[PAGE 2 COULD NOT BE READ]"))
        XCTAssertTrue(result.markdown.contains("P1"))
        XCTAssertTrue(result.markdown.contains("P3"))
        let tries = await fake.callsPerPage[2]
        XCTAssertEqual(tries, 3)   // the first try and two more
    }

    func testBusyIsTriedAgainAndThenWorks() async throws {
        let fake = FakeClaude { page, attempt in
            if attempt < 3 { throw ClaudeError.busy }
            return PageAnswer(text: "P\(page)", inputTokens: 1, outputTokens: 1, cutOff: false)
        }
        let result = try await converter(fake).convert(pages: pages(1)) { _, _ in }
        XCTAssertEqual(result.markdown, "<!-- Page 1 -->\n\nP1\n")
    }

    func testAWrongKeyStopsEverythingAfterOneRequest() async {
        let fake = FakeClaude { _, _ in throw ClaudeError.unauthorized }
        do {
            _ = try await converter(fake, maxAtOnce: 1).convert(pages: pages(20)) { _, _ in }
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? ConversionError, .stopped(.unauthorized))
        }
        let calls = await fake.calls
        XCTAssertEqual(calls, 1)
    }

    func testNoCreditStopsEverything() async {
        let fake = FakeClaude { _, _ in throw ClaudeError.noCredit }
        do {
            _ = try await converter(fake).convert(pages: pages(3)) { _, _ in }
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? ConversionError, .stopped(.noCredit))
        }
    }

    func testARefusedPageIsMarkedWithoutTryingAgain() async throws {
        let fake = FakeClaude { page, _ in
            if page == 1 { throw ClaudeError.refused }
            return PageAnswer(text: "P\(page)", inputTokens: 1, outputTokens: 1, cutOff: false)
        }
        let result = try await converter(fake).convert(pages: pages(2)) { _, _ in }
        XCTAssertEqual(result.unreadablePages, [1])
        let tries = await fake.callsPerPage[1]
        XCTAssertEqual(tries, 1)
    }

    func testStayingOfflineStopsEverything() async {
        let fake = FakeClaude { _, _ in throw ClaudeError.offline }
        do {
            _ = try await converter(fake).convert(pages: pages(2)) { _, _ in }
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? ConversionError, .stopped(.offline))
        }
    }

    func testACutOffPageSaysSo() async throws {
        let fake = FakeClaude { _, _ in
            PageAnswer(text: "Half", inputTokens: 1, outputTokens: 1, cutOff: true)
        }
        let result = try await converter(fake).convert(pages: pages(1)) { _, _ in }
        XCTAssertEqual(result.markdown, "<!-- Page 1 -->\n\nHalf\n\n[PAGE 1 WAS CUT OFF]\n")
    }

    func testBlankPagesAreLeftOut() async throws {
        let fake = FakeClaude { page, _ in
            PageAnswer(text: page == 2 ? "[BLANK PAGE]" : "P\(page)", inputTokens: 1, outputTokens: 1, cutOff: false)
        }
        let result = try await converter(fake).convert(pages: pages(3)) { _, _ in }
        XCTAssertEqual(result.markdown, "<!-- Page 1 -->\n\nP1\n\n<!-- Page 3 -->\n\nP3\n")
        XCTAssertEqual(result.unreadablePages, [])
    }

    func testCancellingStopsWithCancelled() async {
        let fake = FakeClaude { page, _ in
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return PageAnswer(text: "P\(page)", inputTokens: 1, outputTokens: 1, cutOff: false)
        }
        let converter = converter(fake)
        let pages = pages(3)
        let task = Task { try await converter.convert(pages: pages) { _, _ in } }
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? ConversionError, .cancelled)
        }
    }

    func testProgressReachesTheTotal() async throws {
        let fake = FakeClaude { page, _ in
            PageAnswer(text: "P\(page)", inputTokens: 1, outputTokens: 1, cutOff: false)
        }
        let seen = Recorder()
        _ = try await converter(fake).convert(pages: pages(5)) { done, total in
            seen.add(done, total)
        }
        XCTAssertEqual(seen.values.count, 5)
        XCTAssertEqual(seen.values.last?.0, 5)
        XCTAssertEqual(seen.values.last?.1, 5)
    }
}

// Collects progress reports from several tasks safely.
final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [(Int, Int)] = []

    func add(_ done: Int, _ total: Int) {
        lock.lock(); stored.append((done, total)); lock.unlock()
    }

    var values: [(Int, Int)] {
        lock.lock(); defer { lock.unlock() }
        return stored
    }
}
