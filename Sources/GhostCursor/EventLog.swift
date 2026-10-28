import Foundation

/// One accept / reject / correction. Every keypress is an eval.
struct EvalEvent: Codable {
    var ts = Date()
    let session: String
    let goal: String
    let step: Int
    let app: String
    let model: String
    let action: String
    let elementRole: String
    let elementLabel: String
    let confidence: Double
    let latencyMs: Int
    let elementCount: Int
    var outcome: String              // accepted | rejected | done
    var correctionRole: String? = nil
    var correctionLabel: String? = nil
}

enum EventLog {
    static let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GhostCursor", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("events.jsonl")
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = .sortedKeys
        return e
    }()

    static func append(_ event: EvalEvent) {
        guard var line = try? encoder.encode(event) else { return }
        line.append(0x0A)
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(line); try? h.close()
        } else {
            try? line.write(to: url)
        }
    }
}
