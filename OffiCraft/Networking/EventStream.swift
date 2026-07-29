import Foundation

/// The closed topic vocabulary of `GET /api/events` (spec/sse.md §3.1).
enum EventTopic: String, Codable {
    case member
    case chat
    case chatRead = "chat_read"
    case replyCard = "reply_card"
    case task
    case outsourceWorker = "outsource_worker"
    case taskManual = "task_manual"
    case globalContext = "global_context"
    case roleDef = "role_def"
    case lessons
    case context
    case monitoring
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = EventTopic(rawValue: raw) ?? .unknown
    }
}

/// One delta frame. `payload` is deliberately ignored: the contract says a
/// client MUST NOT merge it in place — a delta means "refetch this topic"
/// (spec/sse.md §2.2).
struct EventFrame: Decodable {
    struct Envelope: Decodable {
        var entity: String?
        var key: String?
        var deleted: Bool?
    }
    let seq: Int
    let topic: EventTopic
    var op: String = "patch"
    var data: Envelope?
    var ts: Double = 0
    /// Who caused the write. Absent on older producers — treat as unknown and
    /// never suppress on it.
    var trigger: String?
}

/// Long-lived SSE connection with reconnect-and-resync semantics.
///
/// `seq` is process-local on the server and rolls back on restart, so this
/// intentionally keeps no cursor and performs no replay: every (re)connect is
/// followed by a full refetch, which is exactly what the contract asks for.
actor EventStream {
    /// Emitted for each delta; the app maps topics to refetches.
    ///
    /// Built in `init`, not on the first `frames()` call. The connection is
    /// opened from `AppSession` as soon as there is a token, while the consumer
    /// only starts iterating once the store loads — anything that arrived in
    /// between used to be yielded into a nil continuation and silently dropped.
    private let stream: AsyncStream<EventFrame>
    private let continuation: AsyncStream<EventFrame>.Continuation
    private var task: Task<Void, Never>?
    private var session: URLSession

    /// Whether a connection is currently open. Surfaced so the app can say
    /// "live" or "not live" instead of leaving a dead stream looking healthy.
    private(set) var isConnected = false

    /// Fired whenever the stream (re)connects, so callers can full-resync.
    private var onReconnect: (@Sendable () -> Void)?

    init() {
        // Buffered, so a burst while the consumer is busy refetching is queued
        // rather than dropped. Newest wins if it ever overflows.
        (stream, continuation) = AsyncStream.makeStream(
            of: EventFrame.self,
            bufferingPolicy: .bufferingNewest(256)
        )
        let config = URLSessionConfiguration.default
        // A stream that is quiet for 15s still sends `: heartbeat`, so a
        // generous read timeout with no overall limit is the right shape.
        config.timeoutIntervalForRequest = 90
        config.timeoutIntervalForResource = .infinity
        config.httpAdditionalHeaders = ["Accept": "text/event-stream"]
        session = URLSession(configuration: config)
    }

    func frames() -> AsyncStream<EventFrame> { stream }

    func setReconnectHandler(_ handler: @escaping @Sendable () -> Void) {
        onReconnect = handler
    }

    func connect(host: ServerHost, token: String) {
        disconnect()
        task = Task { [weak self] in
            await self?.runLoop(host: host, token: token)
        }
    }

    func disconnect() {
        task?.cancel()
        task = nil
        isConnected = false
    }

    func finish() {
        disconnect()
        continuation.finish()
    }

    // MARK: - Loop

    private func runLoop(host: ServerHost, token: String) async {
        var backoff: UInt64 = 1
        while !Task.isCancelled {
            do {
                try await stream(host: host, token: token)
                backoff = 1   // clean end-of-stream: retry promptly
            } catch is CancellationError {
                return
            } catch {
                // Exponential backoff, capped, so a server that is down does
                // not turn into a reconnect storm.
                try? await Task.sleep(nanoseconds: backoff * 1_000_000_000)
                backoff = min(backoff * 2, 30)
            }
        }
    }

    private func stream(host: ServerHost, token: String) async throws {
        // Same trailing-slash guard the REST client uses. Without it a host
        // typed as "127.0.0.1:7755/" produced ".../api/events" with a doubled
        // slash — the server 404s it, this loop retries forever, and the app
        // looks perfectly healthy while nothing ever updates live.
        guard let base = host.baseURL else { throw APIError.badHost(host.raw) }
        let absolute = base.absoluteString.hasSuffix("/")
            ? String(base.absoluteString.dropLast())
            : base.absoluteString
        guard let url = URL(string: absolute + "/api/events") else {
            throw APIError.badHost(host.raw)
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 90

        let (bytes, response) = try await session.bytes(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw APIError.unauthorized
            }
            // Anything else non-2xx has to throw so the caller backs off. It
            // used to fall through: a 404 body yields no frames, the loop sees
            // a clean end of stream, resets the backoff to one second and
            // reconnects immediately — a silent hammer on a broken URL.
            guard (200..<300).contains(http.statusCode) else {
                throw APIError.server(status: http.statusCode, code: nil, message: nil)
            }
        }

        isConnected = true
        defer { isConnected = false }

        // Connected — the caller resyncs now, because there is no replay.
        onReconnect?()

        let decoder = JSONDecoder()
        var dataBuffer = ""

        for try await line in bytes.lines {
            if Task.isCancelled { throw CancellationError() }

            if line.isEmpty {
                // Blank line terminates an event.
                defer { dataBuffer = "" }
                guard !dataBuffer.isEmpty,
                      let payload = dataBuffer.data(using: .utf8),
                      let frame = try? decoder.decode(EventFrame.self, from: payload) else {
                    continue
                }
                continuation.yield(frame)
            } else if line.hasPrefix(":") {
                // `: connected` / `: heartbeat` — liveness only.
                continue
            } else if line.hasPrefix("data:") {
                let value = line.dropFirst(5)
                dataBuffer += value.hasPrefix(" ") ? String(value.dropFirst()) : String(value)
            }
            // `id:` carries the seq, which we deliberately do not track.
        }
    }
}
