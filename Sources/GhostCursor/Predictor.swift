import Foundation

struct Prediction: Decodable {
    let action: String        // "click" | "type" | "done"
    let element_id: Int       // -1 when done
    let text: String          // text to type, "" otherwise
    let confidence: Double    // 0...1
    let reason: String
}

/// Calls the Claude Messages API over raw HTTP (there is no official Swift SDK).
final class Predictor {
    static let model = "claude-opus-5-5"

    private let systemPrompt = """
    You are Ghost Cursor, a guide that points a user to the single next UI element to interact with on macOS \
    to accomplish their goal. You see a screenshot where actionable elements are outlined in pink with numeric \
    tags, plus a list of the same elements from the Accessibility tree.

    Rules:
    - Choose exactly one element by its numeric id from the list. Never invent ids or coordinates.
    - action "click": press the element. action "type": click the element, then type `text` into it.
    - action "done": the goal already appears complete on screen (element_id -1).
    - If the target app is not frontmost, use the Dock or menu bar to get there.
    - Prefer the most direct path; menu bar items are fine when a toolbar button is not visible.
    - confidence is your honest probability (0 to 1) that this is the step an expert would take next. \
    Be calibrated: use low values when guessing.
    - reason is under 12 words, written to the user (e.g. "Open the File menu to find Export").
    """

    private var apiKey: String? {
        if let k = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !k.isEmpty { return k }
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ghostcursor/api_key")
        return (try? String(contentsOf: url, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func predict(goal: String, history: [String], elements: [UIElement], screenshot: Data) async throws -> Prediction {
        guard let key = apiKey, !key.isEmpty else {
            throw err("No API key. Put it in ~/.ghostcursor/api_key or set ANTHROPIC_API_KEY.")
        }

        let historyText = history.isEmpty ? "(none yet)" : history.enumerated().map { "\($0 + 1). \($1)" }.joined(separator: "\n")
        let userText = """
        Goal: \(goal)

        Steps so far:
        \(historyText)

        Elements:
        \(elements.map(\.promptLine).joined(separator: "\n"))
        """

        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "action": ["type": "string", "enum": ["click", "type", "done"]],
                "element_id": ["type": "integer"],
                "text": ["type": "string"],
                "confidence": ["type": "number"],
                "reason": ["type": "string"],
            ],
            "required": ["action", "element_id", "text", "confidence", "reason"],
            "additionalProperties": false,
        ]

        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": 16000,
            // Latency matters more than depth here; low effort keeps each step snappy.
            "output_config": ["effort": "low", "format": ["type": "json_schema", "schema": schema]],
            // On a safety-classifier decline, re-run server-side on Anthropic's recommended fallback.
            "fallbacks": "default",
            "system": [["type": "text", "text": systemPrompt, "cache_control": ["type": "ephemeral"]]],
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "image", "source": ["type": "base64", "media_type": "image/png",
                                                 "data": screenshot.base64EncodedString()]],
                    ["type": "text", "text": userText],
                ],
            ]],
        ]

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw err("Bad response (HTTP \(status))")
        }
        guard status == 200 else {
            let msg = (json["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(status)"
            throw err("API error: \(msg)")
        }
        if json["stop_reason"] as? String == "refusal" { throw err("Model declined this step.") }

        let blocks = json["content"] as? [[String: Any]] ?? []
        guard let text = blocks.first(where: { $0["type"] as? String == "text" })?["text"] as? String else {
            throw err("No text in response")
        }
        return try JSONDecoder().decode(Prediction.self, from: Data(text.utf8))
    }

    private func err(_ msg: String) -> NSError {
        NSError(domain: "GhostCursor", code: 2, userInfo: [NSLocalizedDescriptionKey: msg])
    }
}
