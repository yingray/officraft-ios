import Foundation

// MARK: - Errors

enum APIError: LocalizedError, Equatable {
    /// The host string could not be turned into a URL.
    case badHost(String)
    /// Token missing or rejected — the app drops back to the login screen.
    case unauthorized
    /// Server answered with a non-2xx and, where available, its error envelope.
    case server(status: Int, code: String?, message: String?)
    case decoding(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .badHost(let host):
            return "無法解析主機網址「\(host)」"
        case .unauthorized:
            return "登入已失效，請重新連線"
        case .server(let status, _, let message):
            return message ?? "伺服器回應 \(status)"
        case .decoding(let detail):
            return "回應格式無法解讀：\(detail)"
        case .transport(let detail):
            return detail
        }
    }

    /// Shown under the host field on the login screen.
    var isConnectivity: Bool {
        if case .transport = self { return true }
        if case .badHost = self { return true }
        return false
    }
}

/// The server's error envelope (`docs/design/api-error-envelope.md`).
private struct ErrorEnvelope: Decodable {
    struct Body: Decodable {
        var code: String?
        var message: String?
    }
    var error: Body?
    var detail: String?
}

// MARK: - Host

/// A saved connection target. The design doc keeps several (本機 / tunnel / VPN)
/// so the owner can switch in one tap when they leave the house.
struct ServerHost: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    /// As typed: `officraft.hardcore.link`, `127.0.0.1:7755`, `https://…`.
    var raw: String
    var label: String = ""

    /// Bare host:port with the scheme stripped, for display.
    var display: String {
        raw
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// Loopback and private ranges get plain HTTP; everything else HTTPS.
    /// The server binds 127.0.0.1 by default, so the local case must not be
    /// forced onto TLS it does not speak.
    var isLocal: Bool {
        let h = display.split(separator: ":").first.map(String.init) ?? display
        return h == "localhost"
            || h == "127.0.0.1"
            || h.hasSuffix(".local")
            || h.hasPrefix("192.168.")
            || h.hasPrefix("10.")
            || h.hasPrefix("100.")   // Tailscale CGNAT range
    }

    var scheme: String {
        if raw.hasPrefix("http://") { return "http" }
        if raw.hasPrefix("https://") { return "https" }
        return isLocal ? "http" : "https"
    }

    var baseURL: URL? {
        URL(string: "\(scheme)://\(display)")
    }
}

// MARK: - Client

/// Thin async wrapper over `URLSession` for the OffiCraft REST surface.
///
/// It is deliberately stateless apart from host + token: the app reconciles by
/// refetching whenever an SSE delta arrives (spec/sse.md §2.2), so there is no
/// client-side cache to invalidate.
actor APIClient {
    private var host: ServerHost?
    private var token: String?
    private let session: URLSession

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 20
            config.waitsForConnectivity = false
            config.httpAdditionalHeaders = ["Accept": "application/json"]
            self.session = URLSession(configuration: config)
        }
    }

    func configure(host: ServerHost?, token: String?) {
        self.host = host
        self.token = token
    }

    var currentHost: ServerHost? { host }
    var hasToken: Bool { token?.isEmpty == false }

    /// Absolute URL for a server-relative attachment path.
    func resolve(path: String) -> URL? {
        guard let base = host?.baseURL else { return nil }
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path)
        }
        return URL(string: path, relativeTo: base)?.absoluteURL
    }

    /// Attachment fetches need the bearer token, so callers download through
    /// the client rather than handing the URL to `AsyncImage`.
    func data(forPath path: String) async throws -> Data {
        guard let url = resolve(path: path) else { throw APIError.badHost(path) }
        var request = URLRequest(url: url)
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await perform(request)
        try validate(response: response, data: data)
        return data
    }

    // MARK: Requests

    func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        try await request(path, method: "GET", query: query, body: Optional<EmptyResponse>.none)
    }

    @discardableResult
    func post<T: Decodable, Body: Encodable>(_ path: String, body: Body) async throws -> T {
        try await request(path, method: "POST", query: [:], body: body)
    }

    @discardableResult
    func post<T: Decodable>(_ path: String) async throws -> T {
        try await request(path, method: "POST", query: [:], body: Optional<EmptyResponse>.none)
    }

    @discardableResult
    func patch<T: Decodable, Body: Encodable>(_ path: String, body: Body) async throws -> T {
        try await request(path, method: "PATCH", query: [:], body: body)
    }

    /// For endpoints whose body we do not care about.
    func send<Body: Encodable>(_ path: String, method: String, body: Body?) async throws {
        let _: EmptyResponse = try await request(path, method: method, query: [:], body: body)
    }

    func request<T: Decodable, Body: Encodable>(
        _ path: String,
        method: String,
        query: [String: String] = [:],
        body: Body?
    ) async throws -> T {
        try await perform(path, method: method, query: query, body: body)
    }

    private func perform<T: Decodable, Body: Encodable>(
        _ path: String,
        method: String,
        query: [String: String],
        body: Body?
    ) async throws -> T {
        // Built by string rather than `appendingPathComponent`, which would
        // double the slash for our already-absolute paths ("/api/tasks").
        guard let base = host?.baseURL else { throw APIError.badHost(host?.raw ?? "") }
        let absolute = base.absoluteString.hasSuffix("/")
            ? String(base.absoluteString.dropLast())
            : base.absoluteString
        guard var components = URLComponents(string: absolute + path) else {
            throw APIError.badHost(host?.raw ?? "")
        }
        if !query.isEmpty {
            components.queryItems = query
                .sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw APIError.badHost(host?.raw ?? "") }

        var request = URLRequest(url: url)
        request.httpMethod = method
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await perform(request)
        try validate(response: response, data: data)

        if T.self == EmptyResponse.self { return EmptyResponse() as! T }
        guard !data.isEmpty else { throw APIError.decoding("空回應") }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error).prefix(200).description)
        }
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            throw APIError.transport(Self.message(for: error))
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard !(200..<300).contains(http.statusCode) else { return }
        if http.statusCode == 401 || http.statusCode == 403 { throw APIError.unauthorized }
        let envelope = try? decoder.decode(ErrorEnvelope.self, from: data)
        throw APIError.server(
            status: http.statusCode,
            code: envelope?.error?.code,
            message: envelope?.error?.message ?? envelope?.detail
        )
    }

    /// Connection failures are the common case here — the server binds
    /// loopback, so "connect from outside" is a tunnel/VPN problem far more
    /// often than a server bug. The copy points that way.
    private static func message(for error: URLError) -> String {
        switch error.code {
        case .cannotFindHost, .cannotConnectToHost:
            return "連不上這個位址。server 預設只綁 127.0.0.1，從外面連要先開 tunnel 或走 VPN。"
        case .timedOut:
            return "連線逾時。"
        case .notConnectedToInternet:
            return "裝置目前沒有網路連線。"
        case .secureConnectionFailed, .serverCertificateUntrusted:
            return "TLS 交握失敗，請確認網址與憑證。"
        default:
            return error.localizedDescription
        }
    }
}

/// Placeholder for endpoints that return no useful body.
struct EmptyResponse: Codable {}
