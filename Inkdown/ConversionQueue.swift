import Foundation

// What Inkdown is doing right now, for the menu and the menu bar icon.
enum QueueStatus: Equatable {
    case idle(last: String?)                              // nothing running; `last` describes the last result
    case converting(name: String, done: Int, total: Int)  // a PDF is being converted

    // The first line of the menu.
    var menuTitle: String {
        switch self {
        case .idle(let last):
            return last ?? "Ready"
        case .converting(let name, let done, let total):
            if total == 0 { return "Converting \(name) — opening…" }
            // Show the page being worked on, not the number already finished.
            return "Converting \(name) — page \(min(done + 1, total)) of \(total)"
        }
    }

    // The short text next to the menu bar icon.
    var iconTitle: String {
        switch self {
        case .idle:
            return ""
        case .converting(_, let done, let total):
            return total == 0 ? "…" : "\(done)/\(total)"
        }
    }
}

// One PDF to convert and where its Markdown file goes.
struct Job: Equatable {
    let pdf: URL
    let output: URL
}

// How a job ended. (A cancelled job reports nothing.)
enum JobOutcome: Equatable {
    case done(output: URL, result: ConversionResult)
    case failed(pdf: URL, error: ConversionError)
}

// Converts PDFs one after another and reports what is going on.
@MainActor
final class ConversionQueue {

    // The three steps of a conversion. The app passes the real ones;
    // tests pass fakes.
    private let split: @Sendable (URL) throws -> [Data]
    private let makeConverter: () -> Converter
    private let write: (String, URL) throws -> Void

    // Called whenever the status changes, and whenever a job ends.
    var onStatus: ((QueueStatus) -> Void)?
    var onOutcome: ((JobOutcome) -> Void)?

    private var waiting: [Job] = []
    private var running: Task<Void, Never>?
    private var lastLine: String?

    // Goes up by one with every Cancel. A job remembers the number it
    // started with; if the number has changed, the job was cancelled and
    // must not write or report anything any more.
    private var generation = 0

    init(split: @escaping @Sendable (URL) throws -> [Data],
         makeConverter: @escaping () -> Converter,
         write: @escaping (String, URL) throws -> Void) {
        self.split = split
        self.makeConverter = makeConverter
        self.write = write
    }

    // True while a PDF is being converted or waiting.
    var isBusy: Bool {
        running != nil || !waiting.isEmpty
    }

    // Adds a PDF. It starts at once if nothing else is running.
    func add(_ job: Job) {
        waiting.append(job)
        startNextIfIdle()
    }

    // Stops the running conversion and forgets the waiting ones.
    // Nothing is written for any of them.
    func cancelAll() {
        generation += 1
        waiting.removeAll()
        running?.cancel()
        running = nil
        onStatus?(.idle(last: lastLine))
    }

    private func startNextIfIdle() {
        guard running == nil else { return }
        guard !waiting.isEmpty else {
            onStatus?(.idle(last: lastLine))
            return
        }
        let job = waiting.removeFirst()
        let mine = generation
        running = Task {
            await self.run(job, generation: mine)
            // Only move on if this job was not cancelled in the meantime.
            if self.generation == mine {
                self.running = nil
                self.startNextIfIdle()
            }
        }
    }

    private func run(_ job: Job, generation mine: Int) async {
        let name = job.pdf.lastPathComponent
        onStatus?(.converting(name: name, done: 0, total: 0))

        do {
            // Cutting a big PDF into pages can take a moment, so it runs
            // off the main thread and the menu stays responsive.
            let split = self.split
            let pages = try await Task.detached { try split(job.pdf) }.value
            guard generation == mine else { return }
            onStatus?(.converting(name: name, done: 0, total: pages.count))

            let result = try await makeConverter().convert(pages: pages) { done, total in
                Task { @MainActor in
                    guard self.generation == mine, self.running != nil else { return }
                    self.onStatus?(.converting(name: name, done: done, total: total))
                }
            }
            guard generation == mine else { return }

            do {
                try write(result.markdown, job.output)
            } catch {
                throw ConversionError.cannotWrite
            }
            lastLine = ConversionQueue.lastLine(output: job.output, result: result)
            onOutcome?(.done(output: job.output, result: result))
        } catch ConversionError.cancelled {
            // The user chose Cancel: nothing to report.
        } catch let error as ConversionError {
            guard generation == mine else { return }
            onOutcome?(.failed(pdf: job.pdf, error: error))
        } catch {
            guard generation == mine else { return }
            onOutcome?(.failed(pdf: job.pdf, error: .cannotOpen))
        }
    }

    // The line shown in the menu after a conversion, for example
    // "notes.md — 12 pages, about $0.31".
    static func lastLine(output: URL, result: ConversionResult) -> String {
        let pages = result.pageCount == 1 ? "1 page" : "\(result.pageCount) pages"
        let cost = ClaudeClient.cost(inputTokens: result.inputTokens, outputTokens: result.outputTokens)
        var line = "\(output.lastPathComponent) — \(pages), about $" + String(format: "%.2f", cost)
        if !result.unreadablePages.isEmpty {
            let count = result.unreadablePages.count
            line += count == 1 ? ", 1 page unreadable" : ", \(count) pages unreadable"
        }
        if result.markdown.isEmpty {
            line += ", no text found"
        }
        return line
    }
}
