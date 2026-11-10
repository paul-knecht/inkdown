import Foundation

// What a finished conversion produced.
struct ConversionResult: Equatable {
    let markdown: String          // the whole Markdown file
    let pageCount: Int            // how many pages the PDF has
    let unreadablePages: [Int]    // page numbers that could not be read
    let inputTokens: Int          // tokens Claude read, for the cost
    let outputTokens: Int         // tokens Claude wrote, for the cost
}

// Converts all pages of a PDF: sends each page to Claude, tries again when
// something goes wrong, and puts the answers together in page order.
struct Converter {

    // Sends one page (its data, its number, the total) and returns the answer.
    // The real app passes ClaudeClient.transcribe; tests pass a fake.
    var transcribe: @Sendable (Data, Int, Int) async throws -> PageAnswer

    // How many seconds to wait before the 2nd, 3rd and 4th try of a page.
    var retryDelays: [Double] = [2, 6, 15]

    // How many pages are sent at the same time.
    var maxAtOnce = 4

    // What one page ended as, with the tokens it used.
    private struct Finished: Sendable {
        let index: Int
        let result: PageResult
        let inputTokens: Int
        let outputTokens: Int
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

        return ConversionResult(markdown: MarkdownAssembler.assemble(results),
                                pageCount: total,
                                unreadablePages: unreadable,
                                inputTokens: finished.reduce(0) { $0 + $1.inputTokens },
                                outputTokens: finished.reduce(0) { $0 + $1.outputTokens })
    }

    // Converts one page, trying again after a pause when that can help.
    // Throws a ClaudeError only for problems that stop the whole conversion.
    private func convertPage(_ data: Data, index: Int, total: Int) async throws -> Finished {
        let number = index + 1
        var attempt = 0

        while true {
            try Task.checkCancellation()
            do {
                let answer = try await transcribe(data, number, total)
                var result = MarkdownAssembler.clean(answer.text)
                if answer.cutOff, case .text(let text) = result {
                    result = .text(text + "\n\n[PAGE \(number) WAS CUT OFF]")
                }
                return Finished(index: index, result: result,
                                inputTokens: answer.inputTokens, outputTokens: answer.outputTokens)
            } catch let error as ClaudeError {
                switch error {
                case .noKey, .unauthorized, .noCredit:
                    // Trying again cannot help, and no other page would work either.
                    throw error
                case .refused, .tooLarge:
                    // Only this page is affected, and trying again gives the same answer.
                    return Finished(index: index, result: .unreadable, inputTokens: 0, outputTokens: 0)
                case .busy, .offline, .failed:
                    if attempt < retryDelays.count {
                        try await Task.sleep(nanoseconds: UInt64(retryDelays[attempt] * 1_000_000_000))
                        attempt += 1
                    } else if error == .failed {
                        // Something is wrong with this page only. Mark it and go on.
                        return Finished(index: index, result: .unreadable, inputTokens: 0, outputTokens: 0)
                    } else {
                        // Still no connection, or still busy: stop everything.
                        throw error
                    }
                }
            }
        }
    }
}
