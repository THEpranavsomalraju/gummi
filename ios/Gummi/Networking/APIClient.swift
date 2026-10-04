import Foundation

/// Typed client for CONTRACT section 4. Bearer token from TokenProvider, X-User-Id on every call,
/// one retry with a fresh token after a 401.
nonisolated final class APIClient: Sendable {
    let config: AppConfig
    let tokens: TokenProvider
    let session: URLSession

    init(config: AppConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
        self.tokens = TokenProvider(config: config, session: session)
    }

    // MARK: Routes

    func health() async throws -> Health { try await send("GET", "health") }
    func state() async throws -> GummiState { try await send("GET", "state") }
    func feed(date: String? = nil) async throws -> [StoryCard] {
        try await send("GET", "feed", query: date.map { ["date": $0] } ?? [:], as: FeedResponse.self).cards
    }
    func predictions(status: PredictionStatus? = nil) async throws -> [Prediction] {
        try await send("GET", "predictions", query: status.map { ["status": $0.rawValue] } ?? [:],
                       as: PredictionsResponse.self).predictions
    }
    func grades(date: String? = nil) async throws -> [Grade] {
        try await send("GET", "grades", query: date.map { ["date": $0] } ?? [:], as: GradesResponse.self).grades
    }
    func meals(date: String? = nil) async throws -> [Meal] {
        try await send("GET", "meals", query: date.map { ["date": $0] } ?? [:], as: MealsResponse.self).meals
    }
    func logMeal(_ body: NewMealBody) async throws -> Meal { try await send("POST", "meals", body: body) }
    func logFood(_ body: LogFoodBody) async throws -> Meal { try await send("POST", "meals", body: body) }
    func updateMeal(id: String, items: [MealItem]) async throws -> SavedMeal {
        try await send("PATCH", "meals/\(id)", body: MealItemsBody(items: items))
    }
    func deleteMeal(id: String) async throws -> Bool {
        try await send("DELETE", "meals/\(id)", as: DeletedResponse.self).deleted
    }
    /// Throws `.http(409, "due_already_logged", ...)` if it was logged already.
    func logDueMeal(dueId: String) async throws -> Meal { try await send("POST", "meals/due/\(dueId)/log") }
    func simulate(items: [MealItem], eatAt: Date? = nil) async throws -> Simulation {
        try await send("POST", "simulate", body: SimulateBody(items: items, eatAt: eatAt))
    }
    func uploadSteps(_ samples: [StepSample]) async throws -> Int {
        try await send("POST", "vitals", body: VitalsBody(samples: samples), as: AcceptedResponse.self).accepted
    }
    func sendWalkEvent(_ body: WalkEventBody) async throws {
        _ = try await send("POST", "events", body: body, as: OKResponse.self)
    }
    /// Throws `.http(404, "not_found", ...)` before the first walk.
    func latestWalk() async throws -> WalkSummary { try await send("GET", "walks/latest") }
    func profile() async throws -> Profile { try await send("GET", "profile") }
    func updateProfile(_ profile: Profile) async throws -> Profile { try await send("PUT", "profile", body: profile) }
    func follow(_ userId: String?) async throws -> GummiState {
        try await send("POST", "follow", body: FollowBody(userId: userId))
    }
    func startStream(_ body: StreamStartBody = .init()) async throws -> StreamStatus {
        try await send("POST", "stream/start", body: body)
    }
    func stopStream() async throws -> StreamStatus { try await send("POST", "stream/stop") }
    func pauseStream() async throws -> StreamStatus { try await send("POST", "stream/pause") }
    func resumeStream() async throws -> StreamStatus { try await send("POST", "stream/resume") }
    func setStreamSpeed(_ speed: Double) async throws -> StreamStatus {
        try await send("POST", "stream/speed", body: StreamSpeedBody(speed: speed))
    }
    func streamStatus() async throws -> StreamStatus { try await send("GET", "stream/status") }
    func fleet() async throws -> Fleet { try await send("GET", "fleet") }
    func dexcomStatus() async throws -> DexcomStatus { try await send("GET", "dexcom/status") }
    /// GET /foodlog?date= (1.5). A nil date means the backend's today (the replay day while acting as someone).
    func foodLog(date: String? = nil) async throws -> FoodLog {
        try await send("GET", "foodlog", query: date.map { ["date": $0] } ?? [:])
    }
    /// GET /day?date= (1.6).
    func day(date: String? = nil) async throws -> DaySummary {
        try await send("GET", "day", query: date.map { ["date": $0] } ?? [:])
    }

    /// POST /chat as server-sent events (CONTRACT section 6). The stream finishes when the server closes it
    /// (after `done`, or after a `rate_limited` error) and throws on HTTP errors or a dropped connection.
    /// 60 s of silence counts as dropped: `ask_data` can think for 20 s or more without sending anything.
    func chat(message: String, conversationId: String?) -> AsyncThrowingStream<ChatEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let body = try JSONCoding.encoder().encode(ChatBody(message: message, conversationId: conversationId))
                    var (bytes, status) = try await openChat(body, forceRefresh: false)
                    if status == 401 {
                        bytes.task.cancel()
                        (bytes, status) = try await openChat(body, forceRefresh: true)
                    }
                    guard status == 200 else {
                        var data = Data()
                        for try await byte in bytes where data.count < 4096 { data.append(byte) }
                        throw APIError.from(status: status, body: data)
                    }
                    var parser = SSEParser()
                    let decoder = JSONCoding.decoder()
                    for try await byte in bytes {
                        guard let message = parser.push(byte) else { continue }
                        // A malformed event is skipped rather than ending the turn.
                        if let event = try? ChatEvent.decode(event: message.event, data: Data(message.data.utf8), using: decoder) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch let error as URLError {
                    continuation.finish(throwing: APIError.transport(error.localizedDescription))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Plumbing

    /// An authorized request for `path` under the base URL. LiveClient uses it for GET /live.
    func authorizedRequest(_ method: String, _ path: String, query: [String: String] = [:],
                           body: Data? = nil, forceRefresh: Bool = false) async throws -> URLRequest {
        if forceRefresh { await tokens.invalidate() }
        var url = config.apiBaseURL.appending(path: path)
        if !query.isEmpty {
            url.append(queryItems: query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) })
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = method
        request.setValue("Bearer \(try await tokens.accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue(config.userID, forHTTPHeaderField: "X-User-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func openChat(_ body: Data, forceRefresh: Bool) async throws -> (URLSession.AsyncBytes, Int) {
        var request = try await authorizedRequest("POST", "chat", body: body, forceRefresh: forceRefresh)
        request.timeoutInterval = 60
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        return (bytes, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private func send<T: Decodable & Sendable>(_ method: String, _ path: String, query: [String: String] = [:],
                                               as type: T.Type = T.self) async throws -> T {
        try await perform(method, path, query: query, body: nil)
    }

    private func send<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ method: String, _ path: String, query: [String: String] = [:], body: B, as type: T.Type = T.self
    ) async throws -> T {
        let data: Data
        do { data = try JSONCoding.encoder().encode(body) } catch { throw APIError.decoding(error) }
        return try await perform(method, path, query: query, body: data)
    }

    private func perform<T: Decodable & Sendable>(_ method: String, _ path: String,
                                                  query: [String: String], body: Data?) async throws -> T {
        var (data, status) = try await load(authorizedRequest(method, path, query: query, body: body))
        if status == 401 {
            (data, status) = try await load(authorizedRequest(method, path, query: query, body: body, forceRefresh: true))
        }
        guard (200..<300).contains(status) else { throw APIError.from(status: status, body: data) }
        do { return try JSONCoding.decoder().decode(T.self, from: data) } catch { throw APIError.decoding(error) }
    }

    private func load(_ request: URLRequest) async throws -> (Data, Int) {
        do {
            let (data, response) = try await session.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch let error as URLError {
            throw APIError.transport(error.localizedDescription)
        }
    }
}
