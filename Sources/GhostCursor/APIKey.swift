import Foundation

/// The Anthropic API key: from the environment if set, otherwise ~/.ghostcursor/api_key (mode 600).
enum APIKey {
    static let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ghostcursor")
    static let file = dir.appendingPathComponent("api_key")

    static func load() -> String? {
        if let k = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !k.isEmpty { return k }
        let k = (try? String(contentsOf: file, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (k?.isEmpty ?? true) ? nil : k
    }

    static func save(_ key: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? fm.removeItem(at: file)
        guard fm.createFile(atPath: file.path, contents: Data(key.utf8), attributes: [.posixPermissions: 0o600]) else {
            throw NSError(domain: "GhostCursor", code: 3, userInfo: [NSLocalizedDescriptionKey: "Couldn't save the key"])
        }
    }

    /// Checks the key with a cheap authenticated call (lists models; no tokens spent).
    static func verify(_ key: String) async -> String? {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models?limit=1")!)
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        req.timeoutInterval = 15
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            switch (resp as? HTTPURLResponse)?.statusCode ?? 0 {
            case 200: return nil
            case 401, 403: return "That key was rejected. Double-check you copied all of it."
            case let code: return "Unexpected response from Anthropic (HTTP \(code)). Try again."
            }
        } catch {
            return "Couldn't reach Anthropic: \(error.localizedDescription)"
        }
    }
}
