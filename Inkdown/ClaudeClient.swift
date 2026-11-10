import Foundation

// What Claude sent back for one page.
struct PageAnswer: Equatable {
    let text: String        // the transcription
    let inputTokens: Int    // how much Claude read (for the cost)
    let outputTokens: Int   // how much Claude wrote (for the cost)
    let cutOff: Bool        // true if the answer hit the length limit
}

// Sends one page to Claude and returns its transcription.
enum ClaudeClient {

    // The Claude model to use, and its list price in dollars per million
    // tokens. Change all three together if you switch models.
    static let model = "claude-sonnet-5-5"
    static let inputPricePerMillion = 2.0
    static let outputPricePerMillion = 10.0

    // A single page bigger than this is not sent. A whole request may be
    // at most 32 MB, and the page grows by a third when it is encoded.
    static let maxPageBytes = 20_000_000

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    // A session that keeps nothing: no cache and no cookies.
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration)
    }()

    // Builds the JSON we send to Claude: the instructions, the page as a
    // PDF document, and a short line saying which page it is.
    static func requestBody(pagePDF: Data, page: Int, of total: Int) throws -> Data {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            // If Claude's safety system declines a request by mistake, let
            // the API try once more on a fallback model.
            "fallbacks": "default",
            // How carefully Claude works. "medium" reads carefully without
            // spending a lot on thinking. (Thinking itself cannot be
            // switched off on this model, so it is not mentioned here.)
            "output_config": ["effort": "medium"],
            "system": Prompts.system,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "document",
                            "source": [
                                "type": "base64",
                                "media_type": "application/pdf",
                                "data": pagePDF.base64EncodedString(),
                            ],
                        ],
                        ["type": "text", "text": Prompts.user(page: page, of: total)],
                    ],
                ],
            ],
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    // The few fields of Claude's reply that we read.
    private struct Reply: Decodable {
        let content: [Block]
        let stop_reason: String?
        let usage: Usage?

        struct Block: Decodable {
            let type: String
            let text: String?
        }

        struct Usage: Decodable {
            let input_tokens: Int?
            let output_tokens: Int?
        }
    }

    // Reads Claude's reply. Throws a ClaudeError if it was not an answer.
    static func parse(_ data: Data, statusCode: Int) throws -> PageAnswer {
        if statusCode != 200 {
            let text = String(data: data.prefix(10_000), encoding: .utf8) ?? ""
            if statusCode == 401 { throw ClaudeError.unauthorized }
            if statusCode == 402 || text.contains("credit balance") { throw ClaudeError.noCredit }
            if statusCode == 413 { throw ClaudeError.tooLarge }
            if statusCode == 429 || statusCode == 529 { throw ClaudeError.busy }
            throw ClaudeError.failed
        }

        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            throw ClaudeError.failed
        }
        if reply.stop_reason == "refusal" {
            throw ClaudeError.refused
        }

        // The reply can contain "thinking" blocks; only "text" blocks are the answer.
        let text = reply.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined()

        return PageAnswer(text: text,
                          inputTokens: reply.usage?.input_tokens ?? 0,
                          outputTokens: reply.usage?.output_tokens ?? 0,
                          cutOff: reply.stop_reason == "max_tokens")
    }

    // Sends one page and waits for the transcription.
    static func transcribe(pagePDF: Data, page: Int, of total: Int, apiKey: String?) async throws -> PageAnswer {
        let key = (apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ClaudeError.noKey }
        guard pagePDF.count <= maxPageBytes else { throw ClaudeError.tooLarge }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        // Reading a full page of handwriting can take a while.
        request.timeoutInterval = 240
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        // Needed for the "fallbacks" field in the body.
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try requestBody(pagePDF: pagePDF, page: page, of: total)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            // The request never got an answer: no connection, or it took too long.
            throw ClaudeError.offline
        }

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        return try parse(data, statusCode: statusCode)
    }

    // The approximate price of a conversion in dollars.
    static func cost(inputTokens: Int, outputTokens: Int) -> Double {
        Double(inputTokens) / 1_000_000 * inputPricePerMillion
            + Double(outputTokens) / 1_000_000 * outputPricePerMillion
    }
}
