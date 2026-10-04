import Foundation

/// MockAPI: runs MockSession on a replay clock and pushes the same events the backend would.
/// Default pace: 6 replay minutes per wall second, so one replay hour takes 10 seconds and 05:00 to 22:30 about 2.9 minutes.
nonisolated final class MockGummiService: GummiService {
    let mode = AppMode.mock
    private let engine: MockEngine

    init(day: MockDay, minutesPerSecond: Double = 6) {
        engine = MockEngine(session: MockSession(day: day), minutesPerSecond: minutesPerSecond)
    }

    func health() async throws -> Health { Health(status: "ok", mode: .mock, version: "mock-p012-day4") }
    func snapshot() async throws -> GummiState { await engine.snapshot() }
    func feed() async throws -> [StoryCard] { await engine.cards() }
    func fleet() async throws -> Fleet { await engine.fleet() }
    func follow(_ userId: String?) async throws -> GummiState {
        guard userId == nil || userId == MockSession.participant else {
            throw APIError.http(status: 404, code: "not_found", message: "Mock mode only replays \(MockSession.participant)")
        }
        return await engine.follow(userId)
    }
    func logDueMeal(dueId: String) async throws -> Meal { try await engine.logDue(dueId) }
    func startStream() async throws -> StreamStatus { await engine.restart() }
    func stopStream() async throws -> StreamStatus { await engine.setPaused(true) }
    func pauseStream() async throws -> StreamStatus { await engine.setPaused(true) }
    func resumeStream() async throws -> StreamStatus { await engine.setPaused(false) }
    /// `speed` is the contract's replay multiplier (60 means one replay minute per wall second).
    func setStreamSpeed(_ speed: Double) async throws -> StreamStatus { await engine.setSpeed(speed / 60) }

    /// MockChat's scripted reply, played back with the backend's pacing.
    func chat(_ message: String, conversationId: String?) -> AsyncThrowingStream<ChatEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                for step in await engine.chatReply(message, conversationId: conversationId) {
                    do { try await Task.sleep(for: step.delay) } catch { break }
                    continuation.yield(step.event)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func updateMeal(id: String, items: [MealItem]) async throws -> SavedMeal { try await engine.updateMeal(id, items: items) }
    func sendWalkEvent(_ body: WalkEventBody) async throws { await engine.walkEvent(body) }
    func latestWalk() async throws -> WalkSummary {
        guard let walk = await engine.latestWalk else {
            throw APIError.http(status: 404, code: "not_found", message: "No walks yet")
        }
        return walk
    }
    func uploadSteps(_ samples: [StepSample]) async throws -> Int { samples.count }
    func foodLog(date: String?) async throws -> FoodLog { await engine.foodLog(date: date) }
    func day(date: String?) async throws -> DaySummary { await engine.day(date: date) }
    func logFood(_ body: LogFoodBody) async throws -> Meal { try await engine.logFood(body) }

    func events() -> AsyncStream<ServiceEvent> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await engine.subscribe(id, continuation) }
            continuation.onTermination = { [engine] _ in Task { await engine.unsubscribe(id) } }
        }
    }
}

actor MockEngine {
    private var session: MockSession
    private var minutesPerSecond: Double
    private var paused = false
    private var resumeAt: Date?
    private var lastTick = Date.now
    private var lastStatePush = Date.distantPast
    private var subscribers: [UUID: AsyncStream<ServiceEvent>.Continuation] = [:]
    private var ticker: Task<Void, Never>?
    private var chatTurns = 0
    private var chatMeals: [String: SavedMeal] = [:]
    private(set) var latestWalk: WalkSummary?
    private var manualMeals: [SavedMeal] = []

    init(session: MockSession, minutesPerSecond: Double) {
        self.session = session
        self.minutesPerSecond = minutesPerSecond
    }

    func subscribe(_ id: UUID, _ continuation: AsyncStream<ServiceEvent>.Continuation) {
        subscribers[id] = continuation
        continuation.yield(.connection(.live))
        continuation.yield(.live(.state(snapshot())))
        if ticker == nil {
            lastTick = .now
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(250))
                    await self?.tick()
                }
            }
        }
    }

    func unsubscribe(_ id: UUID) {
        subscribers[id] = nil
        if subscribers.isEmpty {
            ticker?.cancel()
            ticker = nil
        }
    }

    func snapshot() -> GummiState {
        session.snapshot(wallNow: .now, paused: paused, minutesPerSecond: minutesPerSecond)
    }

    func cards() -> [StoryCard] { session.following == nil ? [] : session.cards }

    /// The Follow picker's list: p_012 from the scripted day, the other 14 replay participants with steady
    /// placeholder numbers (mock only, never shown as results).
    func fleet() -> Fleet {
        let state = snapshot()
        let graded = session.grades.filter(\.walkEffectGraded)
        let moods: [Mood] = [.calm, .rising, .calm, .high, .dipping, .calm, .happy, .calm, .low, .rising, .calm, .sleepy, .calm, .proud]
        var entries: [FleetEntry] = []
        for number in 1...16 where number != 15 {
            let id = String(format: "p_%03d", number)
            if id == MockSession.participant {
                func mean(_ values: [Double]) -> Double? { values.isEmpty ? nil : (values.reduce(0, +) / Double(values.count) * 10).rounded() / 10 }
                entries.append(FleetEntry(userId: id, displayName: "Participant \(number)", mood: state.mood,
                                          dataThrough: state.confirmed.last?.t, sparkline: Array(state.confirmed.suffix(24)),
                                          grades: session.grades.count, gummiMaeMgDl: mean(graded.map(\.gummiMaeMgDl)),
                                          cgmOnlyMaeMgDl: mean(graded.compactMap(\.cgmOnlyMaeMgDl)),
                                          lastValueMaeMgDl: mean(graded.map(\.lastValueMaeMgDl)), lastGrade: session.grades.last))
            } else {
                var rng = SplitMix64(seed: UInt64(number))
                func value(_ range: ClosedRange<Double>) -> Double { (Double.random(in: range, using: &rng) * 10).rounded() / 10 }
                entries.append(FleetEntry(userId: id, displayName: "Participant \(number)", mood: moods[number % moods.count],
                                          dataThrough: nil, sparkline: [], grades: Int.random(in: 10...30, using: &rng),
                                          gummiMaeMgDl: value(7...12), cgmOnlyMaeMgDl: value(8...13), lastValueMaeMgDl: value(11...16),
                                          lastGrade: nil))
            }
        }
        func fleetMean(_ values: [Double?]) -> Double? {
            let known = values.compactMap { $0 }
            return known.isEmpty ? nil : (known.reduce(0, +) / Double(known.count) * 10).rounded() / 10
        }
        return Fleet(entries: entries, fleetGummiMaeMgDl: fleetMean(entries.map(\.gummiMaeMgDl)),
                     fleetCgmOnlyMaeMgDl: fleetMean(entries.map(\.cgmOnlyMaeMgDl)),
                     fleetLastValueMaeMgDl: fleetMean(entries.map(\.lastValueMaeMgDl)), stream: state.stream)
    }

    func follow(_ userId: String?) -> GummiState {
        session.following = userId
        pushState()
        return snapshot()
    }

    func logDue(_ dueId: String) throws -> Meal {
        let (meal, events) = try session.logDue(dueId: dueId)
        events.forEach { broadcast(.live($0)) }
        pushState()
        return meal
    }

    func chatReply(_ message: String, conversationId: String?) -> [MockChat.Step] {
        chatTurns += 1
        let reply = MockChat.reply(to: message, state: snapshot(), latestGrade: session.grades.last, turn: chatTurns,
                                   conversationId: conversationId ?? "conv_mock_\(chatTurns)")
        if let saved = reply.savedMeal {
            chatMeals[saved.meal.mealId] = saved
            broadcast(.live(.card(session.addChatMeal(saved.meal, likelyPeak: reply.likelyPeak))))
            pushState()
        }
        return reply.steps
    }

    /// PATCH /meals for a chat meal: the phone sends scaled macros, so the totals are just their sum.
    func updateMeal(_ id: String, items: [MealItem]) throws -> SavedMeal {
        guard let saved = chatMeals[id] else { throw APIError.http(status: 404, code: "not_found", message: "meal \(id) not found") }
        guard !items.isEmpty else { throw APIError.http(status: 422, code: "invalid", message: "items must not be empty") }
        let meal = saved.meal
        let updated = Meal(mealId: meal.mealId, eatenAt: meal.eatenAt, source: meal.source, items: items,
                           totals: MealTotals(items: items), isStandardBreakfast: false, predictionId: meal.predictionId)
        // Re-simulated like the backend (1.6): the likely peak moves with the carbs.
        let state = snapshot()
        let peak = saved.simulated == true ? MockChat.simulate(items, state: state, turn: chatTurns)?.peakMgDl : nil
        let result = SavedMeal(updated, simulated: saved.simulated, likelyPeakMgDl: peak ?? saved.likelyPeakMgDl, peakAt: saved.peakAt)
        chatMeals[id] = result
        pushState()
        return result
    }

    /// A real phone walk in mock mode: the same summary card and happy mood the backend sends.
    func walkEvent(_ body: WalkEventBody) {
        guard body.type == "walk_completed", let started = body.startedAt else { return }
        let minutes = max(1, Int((body.at.timeIntervalSince(started) / 60).rounded()))
        let steps = body.steps ?? minutes * 105
        let cadence = body.cadenceSpm ?? steps / minutes
        let intensity: WalkIntensity = cadence == 0 ? .sedentary : cadence < 100 ? .light : cadence < 130 ? .moderate : .vigorous
        let walk = WalkSummary(startedAt: started, endedAt: body.at, minutes: minutes, steps: steps, cadenceSpm: cadence,
                               intensity: intensity, forecastPeakDropMgDl: MockChat.walkDrop, effectSource: .literature)
        latestWalk = walk
        broadcast(.live(.card(session.addPhoneWalk(walk, wallNow: .now))))
        broadcast(.live(.mood(.happy)))
        pushState()
    }

    /// Your entries and Gummi's, simulated on the participant's day while acting as them (D-59).
    private func extraEntries() -> [FoodLogEntry] {
        let mine = manualMeals.map { ($0, FoodOrigin.you) } + chatMeals.values.map { ($0, FoodOrigin.gummi) }
        return mine.map { saved, origin in
            FoodLogEntry(meal: saved.meal, origin: origin, graded: false,
                         prediction: saved.likelyPeakMgDl.map {
                             FoodLogPrediction(predictedPeakMgDl: $0, cgmOnlyPeakMgDl: nil, lastValuePeakMgDl: nil, status: .pending)
                         },
                         grade: nil, note: saved.simulated == true ? "Simulated on the participant's day; not graded" : nil)
        }
    }

    func foodLog(date: String?) -> FoodLog {
        guard date == nil || date == session.dateString else { return FoodLog(date: date, entries: []) }
        return session.foodLog(extra: extraEntries())
    }

    func day(date: String?) -> DaySummary {
        guard date == nil || date == session.dateString else { return MockSession.emptyDay(date: date ?? session.dateString) }
        let today = snapshot().today
        return session.daySummary(steps: today.steps, walks: today.walks)
    }

    /// POST /meals from the Log food sheet: macros from the seed foods (20 g carbs for anything unknown).
    func logFood(_ body: LogFoodBody) throws -> Meal {
        guard !body.items.isEmpty else { throw APIError.http(status: 422, code: "invalid", message: "items must not be empty") }
        let items = body.items.map { food -> MealItem in
            if let seed = MockChat.food(in: food.name) {
                var item = seed.item(quantity: food.quantity)
                item.name = food.name
                if let unit = food.unit { item.unit = unit }
                return item
            }
            return MealItem(name: food.name, quantity: 1, unit: food.unit ?? "", carbsG: 20, sugarG: 8, fiberG: 1, proteinG: 3,
                            fatG: 5, calories: 140, nutritionSource: .llmEstimate, editable: true).scaled(toQuantity: food.quantity)
        }
        chatTurns += 1
        let state = snapshot()
        let meal = Meal(mealId: "m_manual_\(chatTurns)", eatenAt: state.replayNow ?? .now, source: .manual, items: items,
                        totals: MealTotals(items: items), isStandardBreakfast: false, predictionId: nil)
        let acting = state.actingAs != nil
        let likely = acting ? MockChat.simulate(items, state: state, turn: chatTurns)?.peakMgDl : nil
        manualMeals.append(SavedMeal(meal, simulated: acting, likelyPeakMgDl: likely))
        broadcast(.live(.card(session.addChatMeal(meal, likelyPeak: likely))))
        pushState()
        return meal
    }

    func restart() -> StreamStatus {
        session.reset()
        paused = false
        resumeAt = nil
        pushState()
        return snapshot().stream
    }

    func setPaused(_ value: Bool) -> StreamStatus {
        paused = value
        resumeAt = nil
        lastTick = .now
        pushState()
        return snapshot().stream
    }

    func setSpeed(_ value: Double) -> StreamStatus {
        minutesPerSecond = max(0.1, value)
        pushState()
        return snapshot().stream
    }

    private func tick() {
        let now = Date.now
        defer { lastTick = now }
        if let resumeAt, now >= resumeAt {
            paused = false
            self.resumeAt = nil
            pushState()
        }
        guard !paused else { return }
        if session.minute >= MockSession.endMinute {
            session.reset()
            pushState()
            return
        }
        let target = session.minute + now.timeIntervalSince(lastTick) * minutesPerSecond
        var changed = false
        for output in session.advance(to: target, wallNow: now) {
            switch output {
            case .event(let event):
                broadcast(.live(event))
                changed = true
            case .pause(let seconds):
                paused = true
                resumeAt = now.addingTimeInterval(seconds)
                changed = true
            }
        }
        // State at most once per second, or right after a scripted beat (CONTRACT section 5).
        if changed || now.timeIntervalSince(lastStatePush) >= 1 { pushState() }
    }

    private func pushState() {
        lastStatePush = .now
        broadcast(.live(.state(snapshot())))
    }

    private func broadcast(_ event: ServiceEvent) {
        for continuation in subscribers.values { continuation.yield(event) }
    }
}
