import Foundation
import Observation
import SwiftUI

nonisolated enum AppTab: Hashable, Sendable {
    case home, today, settings
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
    /// Replay participants for the Follow picker (GET /fleet).
    private(set) var fleet: Fleet?
    private(set) var banner: Banner?
    private(set) var puppetCue: PuppetCue?
    var selectedTab: AppTab = .home
    /// Today scrolls to this card (set by tapping a banner).
    var focusedCardId: String?
    var chatRequest: ChatRequest?
    var showsFollowPicker = false

    @ObservationIgnored private var bannerQueue: [Banner] = []
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

    init(defaults: UserDefaults = .standard, makeService: ServiceFactory? = nil) {
        self.defaults = defaults
        self.makeService = makeService ?? { mode in try AppModel.liveOrMockService(mode, defaults: defaults) }
        let configured = (try? AppConfig.load()) != nil
        mode = defaults.string(forKey: Self.modeKey).flatMap(AppMode.init(rawValue:)) ?? (configured ? .live : .mock)
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
        lastError = nil
        connection = .connecting
        eventsTask = Task { [weak self] in
            await self?.refresh(using: service)
            await self?.autoFollowIfNeeded(using: service)
            for await event in service.events() {
                guard let self, !Task.isCancelled else { break }
                switch event {
                case .live(let live): self.apply(live)
                case .connection(let status): self.connection = status
                }
            }
        }
    }

    /// Closes the live channel. iOS suspends backgrounded apps anyway (CONTRACT section 5).
    func stop() {
        eventsTask?.cancel()
        eventsTask = nil
        connection = .idle
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active: start()
        case .background: stop()
        default: break
        }
    }

    func setMode(_ newMode: AppMode) {
        guard newMode != mode else { return }
        stop()
        defaults.set(newMode.rawValue, forKey: Self.modeKey)
        mode = newMode
        service = nil
        state = nil
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
        guard let service else { return }
        do {
            _ = try await paused ? service.pauseStream() : service.resumeStream()
            lastError = nil
        } catch {
            lastError = "\(error)"
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
                alert = newState.alert
                if let top = newState.topCard { upsert(top) }
                if newState.following == nil { cards = [] }
            case .card(let card):
                let isNew = !cards.contains { $0.cardId == card.cardId }
                upsert(card)
                if isNew, card.type.isKnown, Self.bannerCardTypes.contains(card.type) {
                    enqueue(Banner(id: card.cardId, title: card.title, message: card.body, symbol: card.type.symbol, cardId: card.cardId))
                }
            case .grade(let grade):
                latestGrade = grade
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
        selectedTab = .today
        dismissBanner()
    }

    func cue(_ reaction: PuppetReaction) {
        puppetCue = PuppetCue(reaction: reaction)
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
        } catch {
            lastError = "\(error)"
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
