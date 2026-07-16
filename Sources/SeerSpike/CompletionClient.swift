import Foundation
import SeerSpikeCore

final class CompletionClient {
    private let endpoint: URL
    init(host: String = "127.0.0.1", port: Int = 8080) {
        endpoint = URL(string: "http://\(host):\(port)/completion")!
    }

    func stream(prompt: String) -> AsyncStream<String> {
        AsyncStream { continuation in
            let task = Task {
                var req = URLRequest(url: endpoint)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let body: [String: Any] = [
                    "prompt": prompt, "n_predict": 24, "stream": true,
                    "temperature": 0.3, "cache_prompt": true,
                    "stop": ["\n"]
                ]
                req.httpBody = try? JSONSerialization.data(withJSONObject: body)
                do {
                    let (bytes, _) = try await URLSession.shared.bytes(for: req)
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard let chunk = CompletionStreamParser.parse(line: line) else { continue }
                        if !chunk.text.isEmpty { continuation.yield(chunk.text) }
                        if chunk.done { break }
                    }
                } catch { }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
