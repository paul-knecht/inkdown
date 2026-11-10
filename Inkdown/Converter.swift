import Foundation

// What a finished conversion produced.
struct ConversionResult: Equatable {
    let markdown: String          // the whole Markdown file
    let pageCount: Int            // how many pages the PDF has
    let unreadablePages: [Int]    // page numbers that could not be read
    let incompletePages: [Int]    // page numbers whose text was cut off
    let inputTokens: Int          // tokens Claude read, for the cost
    let outputTokens: Int         // tokens Claude wrote, for the cost
}

// Converts all pages of a PDF: sends each page to Claude, tries again when
// something goes wrong, and puts the answers together in page order.
struct Converter {

    // Sends one page (its data, its number, the total) and returns the answer.
    // The real app passes ClaudeClient.transcribe; tests pass a fake.
    var transcribe: @Sendable (Data, Int, Int) async throws -> PageAnswer

    // How many seconds to wait before trying a page again after an error.
    var retryDelays: [Double] = [2, 6, 15]

    // The same for "Claude is busy". These waits are longer, because a
    // busy service or a rate limit needs time to clear.
    var busyDelays: [Double] = [5, 15, 30, 60, 60]

    // How many pages are sent at the same time.
    var maxAtOnce = 4

    // What one page ended as, with the tokens it used.
    private struct Finished: Sendable {
        let index: Int
        let result: PageResult
        var cutOff = false
        var inputTokens = 0
        var outputTokens = 0
    }

    // Converts every page. `progress` is called after each finished page
    // with (pages done, pages in total).
    func convert(pages: [Data], progress: @escaping @Sendable (Int, Int) -> Void) async throws -> ConversionResult {
        let total = pages.count
        var finished: [Finished] = []

        do {
            try await withThrowingTaskGroup(of: Finished.self) { group in
                var next = 0

                // Starts the next page that has not been sent yet.
                func startNext() {
                    guard next < total else { return }
                    let index = next
                    next += 1
                    group.addTask {
                        try await self.convertPage(pages[index], index: index, total: total)
                    }
                }

                // Start the first few pages, then one more each time one finishes.
                for _ in 0..<min(maxAtOnce, total) { startNext() }
                while let page = try await group.next() {
                    finished.append(page)
                    progress(finished.count, total)
                    startNext()
                }
            }
        } catch is CancellationError {
            throw ConversionError.cancelled
        } catch let error as ClaudeError {
            throw ConversionError.stopped(error)
        }

        if Task.isCancelled { throw ConversionError.cancelled }

        // Pages finish in any order; put them back in page order.
        finished.sort { $0.index < $1.index }
        let results = finished.map(\.result)
        let unreadable = finished.filter { $0.result == .unreadable }.map { $0.index + 1 }
        let incomplete = finished.filter(\.cutOff).map { $0.index + 1 }

        // If pages failed and not one page gave any text, a file would hold
        // nothing but failure marks. Report it and write nothing.
        let hasText = results.contains { if case .text = $0 { return true } else { return false } }
        if !unreadable.isEmpty && !hasText {
            throw ConversionError.nothingRead
        }

        return ConversionResult(markdown: MarkdownAssembler.assemble(results),
                                pageCount: total,
                                unreadablePages: unreadable,
                                incompletePages: incomplete,
                                inputTokens: finished.reduce(0) { $0 + $1.inputTokens },
                                outputTokens: finished.reduce(0) { $0 + $1.outputTokens })
    }

    // Converts one page, trying again after a pause when that can help.
    // Throws a ClaudeError only for problems that stop the whole conversion.
    private func convertPage(_ data: Data, index: Int, total: Int) async throws -> Finished {
        let number = index + 1
        var retries = 0       // tries used up after an error
        var busyRetries = 0   // tries used up after "busy"

        while true {
            try Task.checkCancellation()
            do {
                let answer = try await transcribe(data, number, total)
                var result = MarkdownAssembler.clean(answer.text)
                var cutOff = false
                if answer.cutOff, case .text(let text) = result {
                    // Keep what was written, mark the place, and report it.
                    result = .text(text + "\n\n[PAGE \(number) WAS CUT OFF]")
                    cutOff = true
                }
                return Finished(index: index, result: result, cutOff: cutOff,
                                inputTokens: answer.inputTokens, outputTokens: answer.outputTokens)
            } catch let error as ClaudeError {
                switch error {
                case .noKey, .unauthorized, .noCredit, .rejected:
                    // Trying again cannot help, and no other page would work either.
                    throw error
                case .refused, .tooLarge:
                    // Only this page is affected, and trying again gives the same answer.
                    return Finished(index: index, result: .unreadable)
                case .busy:
                    // Wait and try again. If Claude stays busy, stop everything.
                    guard busyRetries < busyDelays.count else { throw error }
                    try await pause(busyDelays[busyRetries])
                    busyRetries += 1
                case .offline:
                    // Wait and try again. If there is still no connection, stop everything.
                    guard retries < retryDelays.count else { throw error }
                    try await pause(retryDelays[retries])
                    retries += 1
                case .failed:
                    // Wait and try again. If it keeps failing, something is
                    // wrong with this page only: mark it and go on.
                    guard retries < retryDelays.count else {
                        return Finished(index: index, result: .unreadable)
                    }
                    try await pause(retryDelays[retries])
                    retries += 1
                }
            }
        }
    }

    // Waits for the given number of seconds.
    private func pause(_ seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
