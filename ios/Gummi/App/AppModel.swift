import Foundation
import Observation
import SwiftUI

nonisolated enum AppTab: Hashable, Sendable {
    case home, food, activity, day
}

/// An in-app banner for a new card or alert while the app is in the foreground.
nonisolated struct Banner: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let message: String
    let symbol: String
    /// The card to scroll to in Today when the banner is tapped.
    let cardId: String?
}

/// Something the app asks Gummi to do, like cheering when you open a winning grade.
nonisolated struct PuppetCue: Equatable, Sendable {
    let id = UUID()
    let reaction: PuppetReaction
}

/// What the connection capsule says when updates aren't flowing. Nil while live.
nonisolated struct ConnectionNotice: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case reconnecting, offline, asleep }
    let kind: Kind
    let text: String

    /// `lastUpdated` is when the last live data arrived; cached State stays on screen meanwhile.
    static func from(_ connection: ConnectionStatus, problem: APIError?, lastUpdated: Date?, now: Date) -> ConnectionNotice? {
        let updated = lastUpdated.map { date -> String in
            let seconds = now.timeIntervalSince(date)
            if seconds < 60 { return "updated just now" }
            if seconds < 3600 { return "updated \(Int(seconds / 60)) min ago" }
            return "updated \(date.formatted(Date.FormatStyle(date: .omitted, time: .shortened)))"
        }
        func with(_ head: String) -> String { [head, updated].compactMap { $0 }.joined(separator: " · ") }
        if problem?.code == "app_unavailable", connection != .live {
            return ConnectionNotice(kind: .asleep, text: with("Server asleep"))
        }
        switch connection {
        case .live, .idle: return nil
        case .connecting, .reconnecting: return ConnectionNotice(kind: .reconnecting, text: "Reconnecting…")
        case .polling, .offline: return ConnectionNotice(kind: .offline, text: with("Offline"))
        }
    }
}

/// Opens the chat sheet, optionally with a question filled in.
nonisolated struct ChatRequest: Identifiable, Equatable, Sendable {
    let id = UUID()
    var prompt: String?
}

/// The one model every screen reads. It holds the latest State plus the card feed and applies
/// live events with animation, so the UI updates without any refresh.
@Observable
final class AppModel {
    typealias ServiceFactory = (AppMode) throws -> any GummiService

    private(set) var mode: AppMode
    private(set) var state: GummiState?
    /// Newest first, keyed by card_id: a card event with a known id replaces it (CONTRACT 1.3 upsert).
    private(set) var cards: [StoryCard] = []
    private(set) var latestGrade: Grade?
    private(set) var alert: GummiAlert?
    private(set) var mood: Mood = .calm
    private(set) var connection: ConnectionStatus = .idle
    private(set) var lastUpdated: Date?
    private(set) var lastError: String?
    /// Why the backend can't be reached (for example app_unavailable when the Databricks App is stopped).
    private(set) var serverProblem: APIError?
    /// A demo control call in flight ("Starting…"), shown on its button.
    private(set) var streamAction: String?
    private(set) var streamError: String?
    /// Replay participants for the Follow picker (GET /fleet).
    private(set) var fleet: Fleet?
    private(set) var banner: Banner?
    private(set) var puppetCue: PuppetCue?
    var selectedTab: AppTab = .home {
        didSet { if selectedTab == .activity { activityUnseen = 0 } }
    }
    var showsSettings = false
    /// New cards since Activity was last open (the tab badge).
    private(set) var activityUnseen = 0
    /// GET /foodlog for `foodDate` (nil is the backend's today).
    private(set) var foodLog: FoodLog?
    var foodDate: String?
    /// GET /day for `dayDate`.
    private(set) var day: DaySummary?
    var dayDate: String?
    /// The meal Food should open (a meal card tapped in Activity).
    var focusedMealId: String?
    /// Today scrolls to this card (set by tapping a banner).
    var focusedCardId: String?
    var chatRequest: ChatRequest?
    /// One conversation per app session; "New chat" clears it.
    let chat = ChatModel()
    var showsFollowPicker = false
    /// Opens the walk screen.
    var walkRequest: WalkRequest?
    /// A grade that just landed, played over Home's chart.
    private(set) var gradeMoment: GradeMoment?

    @ObservationIgnored private var bannerQueue: [Banner] = []
    @ObservationIgnored private var foodRefresh: Task<Void, Never>?
    @ObservationIgnored private var dayRefresh: Task<Void, Never>?
    /// Every prediction seen while pending, so a grade can show what Gummi predicted.
    @ObservationIgnored private var predictions: [String: Prediction] = [:]
    @ObservationIgnored private let stepsUploader: StepsUploader?
    @ObservationIgnored private let usesSystemServices: Bool
    @ObservationIgnored private var stepsTask: Task<Void, Never>?
    /// Card types and alerts that get an in-app banner (ios/CLAUDE.md Phase 3).
    nonisolated static let bannerCardTypes: Set<CardType> = [.walkSuggested, .mealDue, .mealStory, .eveningRecap]

    @ObservationIgnored private var service: (any GummiService)?
    @ObservationIgnored private var eventsTask: Task<Void, Never>?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let makeService: ServiceFactory

    nonisolated static let modeKey = "gummi.mode"
    nonisolated static let mockSpeedKey = "gummi.mockSpeed"
    nonisolated static let didAutoFollowKey = "gummi.didAutoFollow"
    /// D-61: the demo participant the app follows on first launch.
    nonisolated static let defaultParticipant = "p_012"

    /// `systemServices` is on for the real app (HealthKit steps to /vitals, notification permission) and off for tests.
    init(defaults: UserDefaults = .standard, makeService: ServiceFactory? = nil, systemServices: Bool = false) {
        self.defaults = defaults
        usesSystemServices = systemServices
        stepsUploader = systemServices ? StepsUploader(defaults: defaults) : nil
        self.makeService = makeService ?? { mode in try AppModel.liveOrMockService(mode, defaults: defaults) }
        let configured = (try? AppConfig.load()) != nil
        mode = defaults.string(forKey: Self.modeKey).flatMap(AppMode.init(rawValue:)) ?? (configured ? .live : .mock)
        chat.actingAsName = { [weak self] in self?.displayName(for: self?.state?.actingAs) }
    }

    var isRunning: Bool { eventsTask != nil }

    // MARK: Lifecycle

    /// Fetches State and the feed, then follows the live channel. Called on launch and on every foreground.
    func start() {
        guard eventsTask == nil else { return }
        let service: any GummiService
        do {
            service = try self.service ?? makeService(mode)
        } catch {
            lastError = "\(error)"
            connection = .offline("\(error)")
            return
        }
        self.service = service
        chat.service = service
        startStepsUpload(using: service)
        lastError = nil
        connection = .connecting
        eventsTask = Task { [weak self] in
            await self?.refresh(using: service)
            await self?.autoFollowIfNeeded(using: service)
            if let self, self.usesSystemServices, self.state?.actingAs != nil {
                Task { await LocalNotifier.requestPermissionIfNeeded() }
            }
            for await event in service.events() {
                guard let self, !Task.isCancelled else { break }
                switch event {
                case .live(let live): self.apply(live)
                case .connection(let status):
                    self.connection = status
                    if status == .live { self.serverProblem = nil }
                case .problem(let error): self.serverProblem = error
                }
            }
        }
    }

    /// Closes the live channel. iOS suspends backgrounded apps anyway (CONTRACT section 5).
    func stop() {
        eventsTask?.cancel()
        eventsTask = nil
        stepsTask?.cancel()
        stepsTask = nil
        connection = .idle
    }

    /// Steps to /vitals on open and every 5 minutes while open, live mode only (mock must not move the cursor).
    private func startStepsUpload(using service: any GummiService) {
        guard let stepsUploader, mode == .live, stepsTask == nil else { return }
        stepsTask = Task {
            while !Task.isCancelled {
                _ = try? await stepsUploader.uploadNew(using: service)
                try? await Task.sleep(for: .seconds(StepsUploader.bucket))
            }
        }
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            LocalNotifier.clear()
            start()
        case .background:
            scheduleNotifications()
            stop()
        default: break
        }
    }

    func setMode(_ newMode: AppMode) {
        guard newMode != mode else { return }
        stop()
        defaults.set(newMode.rawValue, forKey: Self.modeKey)
        mode = newMode
        service = nil
        chat.newChat()
        chat.service = nil
        state = nil
        foodLog = nil
        day = nil
        serverProblem = nil
        cards = []
        latestGrade = nil
        alert = nil
        mood = .calm
        lastUpdated = nil
        start()
    }

    func reconnect() {
        stop()
        start()
    }

    // MARK: Actions

    func logDueMeal(_ dueId: String) async {
        guard let service else { return }
        do {
            _ = try await service.logDueMeal(dueId: dueId)
        } catch let error as APIError where error.code == "due_already_logged" {
            // Already logged (auto-log won the race). The upserted card arrives on the live channel.
        } catch {
            lastError = "\(error)"
        }
    }

    func setPaused(_ paused: Bool) async {
        await streamControl(paused ? "Pausing…" : "Resuming…") { try await $0.setPaused(paused) }
    }

    // MARK: Demo controls (shared stream: everyone following, and the projector, see the change)

    func startStream() async { await streamControl("Starting…") { _ = try await $0.startStream() } }
    func stopStream() async { await streamControl("Stopping…") { _ = try await $0.stopStream() } }
    func setStreamSpeed(_ speed: Double) async {
        await streamControl("Changing speed…") { _ = try await $0.setStreamSpeed(speed) }
    }

    /// Runs one control, shows its progress text, then refetches State so the screen matches at once.
    private func streamControl(_ label: String, _ action: (any GummiService) async throws -> Void) async {
        guard let service, streamAction == nil else { return }
        streamAction = label
        defer { streamAction = nil }
        do {
            try await action(service)
            streamError = nil
            apply(.state(try await service.snapshot()))
        } catch {
            streamError = (error as? APIError).map { if case .http(_, _, let message) = $0 { message } else { "\($0)" } } ?? "\(error)"
        }
    }

    /// GET /health through the current service, for the debug menu.
    func ping() async -> String {
        guard let service = try? service ?? makeService(mode) else { return "No service" }
        let started = Date.now
        do {
            let health = try await service.health()
            let ms = Int(Date.now.timeIntervalSince(started) * 1000)
            return "\(health.status), mode \(health.mode.rawValue), \(health.version), \(ms) ms"
        } catch {
            return "\(error)"
        }
    }

    // MARK: Applying events

    func apply(_ event: LiveEvent) {
        withAnimation(.snappy) {
            switch event {
            case .state(let newState):
                state = newState
                mood = newState.mood
                for prediction in newState.pendingPredictions { predictions[prediction.predictionId] = prediction }
                alert = newState.alert
                if let top = newState.topCard { upsert(top) }
                if newState.following == nil { cards = [] }
            case .card(let card):
                let isNew = !cards.contains { $0.cardId == card.cardId }
                upsert(card)
                if isNew, card.type.isKnown, selectedTab != .activity { activityUnseen += 1 }
                if [.mealDue, .mealLogged, .mealStory].contains(card.type) { scheduleFoodRefresh() }
                if [.mealStory, .mealLogged, .eveningRecap, .walkSummary].contains(card.type) { scheduleDayRefresh() }
                if isNew, card.type.isKnown, Self.bannerCardTypes.contains(card.type) {
                    enqueue(Banner(id: card.cardId, title: card.title, message: card.body, symbol: card.type.symbol, cardId: card.cardId))
                }
            case .grade(let grade):
                scheduleDayRefresh()
                scheduleFoodRefresh()
                let isNew = latestGrade?.gradeId != grade.gradeId
                latestGrade = grade
                if isNew {
                    gradeMoment = GradeMoment(grade: grade, prediction: predictions[grade.predictionId])
                    // Proud spins only when Gummi beat CGM-only (and the mood hasn't already spun him).
                    if !grade.earnsProud { cue(.nod) } else if mood != .proud { cue(.cheer) }
                }
            case .alert(let newAlert):
                if alert?.alertId != newAlert.alertId, newAlert.type == .highForecast || newAlert.type == .lowForecast {
                    enqueue(Banner(id: newAlert.alertId, title: newAlert.type == .highForecast ? "Heading high" : "Heading low",
                                   message: newAlert.message, symbol: "exclamationmark.triangle", cardId: nil))
                }
                alert = newAlert
            case .mood(let newMood):
                if newMood.isKnown { mood = newMood }
            case .ping, .unknown:
                break
            }
            lastUpdated = .now
        }
    }

    // MARK: Banners, cues, and sheets

    private func enqueue(_ new: Banner) {
        guard banner?.id != new.id, !bannerQueue.contains(where: { $0.id == new.id }) else { return }
        if banner == nil { banner = new } else { bannerQueue.append(new) }
    }

    func dismissBanner() {
        withAnimation(.snappy) { banner = bannerQueue.isEmpty ? nil : bannerQueue.removeFirst() }
    }

    /// Tapping a banner opens Today at its card.
    func openBanner() {
        focusedCardId = banner?.cardId
        selectedTab = .activity
        dismissBanner()
    }

    func cue(_ reaction: PuppetReaction) {
        puppetCue = PuppetCue(reaction: reaction)
    }

    /// The capsule's notice. `-gummi.forceConnection reconnecting|offline|asleep` fakes one for screenshots (debug builds).
    func connectionNotice(now: Date = .now) -> ConnectionNotice? {
        #if DEBUG
        switch defaults.string(forKey: "gummi.forceConnection") {
        case "reconnecting": return ConnectionNotice.from(.reconnecting(attempt: 2), problem: nil, lastUpdated: lastUpdated, now: now)
        case "offline": return ConnectionNotice.from(.polling, problem: nil, lastUpdated: now.addingTimeInterval(-120), now: now)
        case "asleep": return ConnectionNotice.from(.polling, problem: .http(status: 503, code: "app_unavailable", message: ""),
                                                    lastUpdated: now.addingTimeInterval(-600), now: now)
        default: break
        }
        #endif
        return ConnectionNotice.from(connection, problem: serverProblem, lastUpdated: lastUpdated, now: now)
    }

    // MARK: Food and Day

    func loadFoodLog() async {
        guard let service else { return }
        do { foodLog = try await service.foodLog(date: foodDate) } catch { lastError = "\(error)" }
    }

    func loadDay() async {
        guard let service else { return }
        do { day = try await service.day(date: dayDate) } catch { lastError = "\(error)" }
    }

    /// A burst of live events triggers one fetch, half a second after the last.
    private func scheduleFoodRefresh() {
        foodRefresh?.cancel()
        foodRefresh = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await self?.loadFoodLog()
        }
    }

    private func scheduleDayRefresh() {
        dayRefresh?.cancel()
        dayRefresh = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await self?.loadDay()
        }
    }

    func logFood(name: String, quantity: Double, unit: String?) async -> Bool {
        guard let service else { return false }
        do {
            _ = try await service.logFood(LogFoodBody(items: [.init(name: name, quantity: quantity, unit: unit)]))
            await loadFoodLog()
            return true
        } catch {
            lastError = "\(error)"
            return false
        }
    }

    func savePortions(mealId: String, items: [MealItem]) async -> Bool {
        guard let service else { return false }
        do {
            _ = try await service.updateMeal(id: mealId, items: items)
            await loadFoodLog()
            return true
        } catch {
            lastError = "\(error)"
            return false
        }
    }

    func startWalk(minutes: Int = 10) {
        walkRequest = WalkRequest(minutes: minutes)
    }

    /// The service a walk talks to.
    var activeService: (any GummiService)? { service }

    func prediction(for id: String) -> Prediction? { predictions[id] }

    /// Dismisses the grade moment (only `id`'s, when given, so a newer one stays).
    func dismissGradeMoment(_ id: UUID? = nil) {
        guard id == nil || gradeMoment?.id == id else { return }
        withAnimation(.snappy) { gradeMoment = nil }
    }

    /// Before suspension: schedule what's coming while the app can't listen (CONTRACT section 5, D-29).
    private func scheduleNotifications() {
        guard usesSystemServices, let state else { return }
        let plan = NotificationPlanner.plan(state: state, displayName: displayName(for: state.actingAs), now: .now)
        let application = UIApplication.shared
        var task = UIBackgroundTaskIdentifier.invalid
        task = application.beginBackgroundTask { application.endBackgroundTask(task) }
        Task {
            await LocalNotifier.schedule(plan)
            application.endBackgroundTask(task)
        }
    }

    func askGummi(_ prompt: String? = nil) {
        chatRequest = ChatRequest(prompt: prompt)
    }

    // MARK: Following

    func loadFleet() async {
        guard let service else { return }
        do { fleet = try await service.fleet() } catch { lastError = "\(error)" }
    }

    /// Acts as a replay participant (or nobody). Cards belong to whoever is followed, so the feed reloads.
    func follow(_ userId: String?) async {
        guard let service else { return }
        do {
            let newState = try await service.follow(userId)
            withAnimation(.snappy) { cards = [] }
            apply(.state(newState))
            await loadFoodLog()
            await loadDay()
            let feed = try await service.feed()
            withAnimation(.snappy) { feed.forEach(upsert) }
        } catch {
            lastError = "\(error)"
        }
    }

    /// "Participant 12" for "p_012", from the fleet when it's loaded.
    func displayName(for userId: String?) -> String? {
        guard let userId else { return nil }
        if let entry = fleet?.entries.first(where: { $0.userId == userId }) { return entry.displayName }
        if userId.hasPrefix("p_"), let number = Int(userId.dropFirst(2)) { return "Participant \(number)" }
        return userId
    }

    private func upsert(_ card: StoryCard) {
        guard card.type.isKnown else { return }
        if let index = cards.firstIndex(where: { $0.cardId == card.cardId }) {
            cards[index] = card
        } else {
            let index = cards.firstIndex { $0.createdAt < card.createdAt } ?? cards.endIndex
            cards.insert(card, at: index)
        }
    }

    private func refresh(using service: any GummiService) async {
        do {
            apply(.state(try await service.snapshot()))
            let feed = try await service.feed()
            withAnimation(.snappy) { feed.forEach(upsert) }
            foodLog = try? await service.foodLog(date: foodDate)
            day = try? await service.day(date: dayDate)
        } catch {
            lastError = "\(error)"
            serverProblem = error as? APIError
        }
    }

    /// D-61: on first launch in live mode, follow the demo participant once. Never again after the user unfollows.
    private func autoFollowIfNeeded(using service: any GummiService) async {
        guard mode == .live, !defaults.bool(forKey: Self.didAutoFollowKey), let state, state.following == nil else { return }
        do {
            apply(.state(try await service.follow(Self.defaultParticipant)))
            defaults.set(true, forKey: Self.didAutoFollowKey)
        } catch {
            lastError = "\(error)"
        }
    }

    nonisolated static func liveOrMockService(_ mode: AppMode, defaults: UserDefaults) throws -> any GummiService {
        switch mode {
        case .live:
            do { return LiveGummiService(config: try AppConfig.load()) } catch { throw APIError.notConfigured("\(error)") }
        case .mock:
            let speed = defaults.double(forKey: mockSpeedKey)
            return MockGummiService(day: try MockDay.load(), minutesPerSecond: speed > 0 ? speed : 6)
        }
    }
}
