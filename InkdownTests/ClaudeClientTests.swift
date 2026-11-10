import XCTest
@testable import Inkdown

// Checks what is sent to Claude and how its replies are read.
// None of these tests uses the network.
final class ClaudeClientTests: XCTestCase {

    private func reply(_ json: String) -> Data { Data(json.utf8) }

    // MARK: The request

    func testRequestBodyCarriesThePageAsAPDFDocument() throws {
        let page = Data("fake pdf bytes that are long enough to wrap in base64 ................................".utf8)
        let data = try ClaudeClient.requestBody(pagePDF: page, page: 3, of: 12)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(body["model"] as? String, "claude-sonnet-5-5")
        XCTAssertEqual((body["output_config"] as? [String: Any])?["effort"] as? String, "medium")
        XCTAssertNil(body["thinking"])
        XCTAssertNil(body["temperature"])
        XCTAssertFalse((body["system"] as? String ?? "").isEmpty)

        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        let content = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 2)

        XCTAssertEqual(content[0]["type"] as? String, "document")
        let source = try XCTUnwrap(content[0]["source"] as? [String: Any])
        XCTAssertEqual(source["type"] as? String, "base64")
        XCTAssertEqual(source["media_type"] as? String, "application/pdf")
        let encoded = try XCTUnwrap(source["data"] as? String)
        XCTAssertFalse(encoded.contains("\n"))
        XCTAssertEqual(Data(base64Encoded: encoded), page)

        XCTAssertEqual(content[1]["type"] as? String, "text")
        XCTAssertTrue((content[1]["text"] as? String ?? "").contains("3"))
    }

    func testRequestCarriesTheRightHeadersAndKeepsTheKeyOutOfTheAddress() throws {
        let request = try ClaudeClient.request(pagePDF: Data([1, 2, 3]), page: 1, of: 1, apiKey: "test-key")

        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "test-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2026-10-21")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "server-side-fallback-2026-07-01")
        XCTAssertEqual(request.value(forHTTPHeaderField: "content-type"), "application/json")
        let body = String(data: try XCTUnwrap(request.httpBody), encoding: .utf8) ?? ""
        XCTAssertFalse(body.contains("test-key"))
    }

    func testATimeoutIsAPageProblemNotAConnectionProblem() {
        XCTAssertEqual(ClaudeClient.error(for: URLError(.timedOut)), .failed)
        XCTAssertEqual(ClaudeClient.error(for: URLError(.notConnectedToInternet)), .offline)
        XCTAssertEqual(ClaudeClient.error(for: URLError(.networkConnectionLost)), .offline)
    }

    // MARK: Reading replies

    func testParseJoinsTextBlocksAndSkipsThinking() throws {
        let json = """
        {"content":[{"type":"thinking","thinking":""},{"type":"text","text":"Hello "},{"type":"text","text":"world"}],
         "stop_reason":"end_turn","usage":{"input_tokens":1500,"output_tokens":300}}
        """
        let answer = try ClaudeClient.parse(reply(json), statusCode: 200)
        XCTAssertEqual(answer, PageAnswer(text: "Hello world", inputTokens: 1500, outputTokens: 300, cutOff: false))
    }

    func testParseMarksACutOffAnswer() throws {
        let json = """
        {"content":[{"type":"text","text":"Half"}],"stop_reason":"max_tokens","usage":{"input_tokens":1,"output_tokens":2}}
        """
        let answer = try ClaudeClient.parse(reply(json), statusCode: 200)
        XCTAssertTrue(answer.cutOff)
        XCTAssertEqual(answer.text, "Half")
    }

    func testParseWithoutUsageCountsZero() throws {
        let json = """
        {"content":[{"type":"text","text":"x"}],"stop_reason":"end_turn"}
        """
        let answer = try ClaudeClient.parse(reply(json), statusCode: 200)
        XCTAssertEqual(answer.inputTokens, 0)
        XCTAssertEqual(answer.outputTokens, 0)
    }

    private func assertParse(_ json: String, status: Int, throws expected: ClaudeError,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try ClaudeClient.parse(reply(json), statusCode: status), file: file, line: line) { error in
            XCTAssertEqual(error as? ClaudeError, expected, file: file, line: line)
        }
    }

    func testParseNamesEachFailure() {
        assertParse("{}", status: 401, throws: .unauthorized)
        assertParse("{}", status: 402, throws: .noCredit)
        assertParse(#"{"error":{"message":"Your credit balance is too low"}}"#, status: 400, throws: .noCredit)
        assertParse("{}", status: 413, throws: .tooLarge)
        assertParse("{}", status: 429, throws: .busy)
        assertParse("{}", status: 529, throws: .busy)
        assertParse("{}", status: 500, throws: .failed)
        assertParse("{}", status: 400, throws: .rejected)
        assertParse("{}", status: 403, throws: .rejected)
        assertParse("{}", status: 404, throws: .rejected)
        assertParse("not json", status: 200, throws: .failed)
        assertParse(#"{"content":[],"stop_reason":"refusal"}"#, status: 200, throws: .refused)
    }

    // MARK: Before anything is sent

    func testNoKeyNeverTouchesTheNetwork() async {
        for key in [nil, "", "   "] as [String?] {
            do {
                _ = try await ClaudeClient.transcribe(pagePDF: Data([1]), page: 1, of: 1, apiKey: key)
                XCTFail("Expected an error")
            } catch {
                XCTAssertEqual(error as? ClaudeError, .noKey)
            }
        }
    }

    func testAHugePageIsNotSent() async {
        let huge = Data(count: ClaudeClient.maxPageBytes + 1)
        do {
            _ = try await ClaudeClient.transcribe(pagePDF: huge, page: 1, of: 1, apiKey: "test")
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? ClaudeError, .tooLarge)
        }
    }

    // MARK: Cost

    func testCostUsesTheListPrice() {
        XCTAssertEqual(ClaudeClient.cost(inputTokens: 1_000_000, outputTokens: 1_000_000), 12.0, accuracy: 0.0001)
        XCTAssertEqual(ClaudeClient.cost(inputTokens: 0, outputTokens: 0), 0)
    }
}

// Checks that the instructions for Claude contain every rule for the output.
final class PromptsTests: XCTestCase {

    func testSystemPromptStatesTheOutputRules() {
        let system = Prompts.system
        for needle in ["[ILLEGIBLE]", "[DIAGRAM:", "[BLANK PAGE]", "$$", "summar", "translate", "##", "**"] {
            XCTAssertTrue(system.contains(needle), "The instructions do not mention \(needle)")
        }
    }

    func testUserPromptNamesThePage() {
        let user = Prompts.user(page: 3, of: 12)
        XCTAssertTrue(user.contains("3"))
        XCTAssertTrue(user.contains("12"))
    }
}
