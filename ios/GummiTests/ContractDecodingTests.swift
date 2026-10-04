import Foundation
import Testing
@testable import Gummi

/// Every fixture is either captured from the deployed App (live_*) or hand-written and validated
/// against backend/gummi_api/models.py with Pydantic (except card_unknown_type, which is deliberately off-contract).
@Suite("Contract decoding")
struct ContractDecodingTests {
    typealias Check = @Sendable (Data) throws -> Void

    nonisolated static func check<T: Decodable & Sendable>(_: T.Type) -> Check {
        { _ = try JSONCoding.decoder().decode(T.self, from: $0) }
    }

    /// Fixture name to contract type. Everything here must decode.
    nonisolated static let fixtureTypes: [String: Check] = [
        "live_state": check(GummiState.self), "state_full": check(GummiState.self), "state_null": check(GummiState.self),
        "foodlog": check(FoodLog.self), "day_full": check(DaySummary.self), "day_stale": check(DaySummary.self),
        "day_empty": check(DaySummary.self),
        "live_stream_status": check(StreamStatus.self), "stream_status_stopped": check(StreamStatus.self),
        "live_fleet": check(Fleet.self), "live_profile": check(Profile.self), "live_dexcom_status": check(DexcomStatus.self),
        "live_health": check(Health.self), "live_error_not_found": check(APIErrorBody.self),
        "prediction": check(Prediction.self), "grade_walk_not_graded": check(Grade.self), "grade_null_cgm_only": check(Grade.self),
        "meal": check(Meal.self), "simulation": check(Simulation.self), "walk_summary": check(WalkSummary.self), "alert": check(GummiAlert.self),
        "card_meal_due": check(StoryCard.self), "card_meal_due_resolved": check(StoryCard.self), "card_meal_logged": check(StoryCard.self),
        "card_meal_story": check(StoryCard.self), "card_walk_summary": check(StoryCard.self), "card_walk_suggested": check(StoryCard.self),
        "card_morning_briefing": check(StoryCard.self), "card_unknown_type": check(StoryCard.self),
    ]

    @Test("Every fixture decodes", arguments: fixtureTypes.keys.sorted())
    func decodes(name: String) throws {
        let check = try #require(Self.fixtureTypes[name])
        try check(Fixtures.data(name))
    }

    @Test func everyFixtureFileIsCovered() throws {
        let urls = Fixtures.bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        let names = Set(urls.map { $0.deletingPathExtension().lastPathComponent }).subtracting(["feed"])
        #expect(names == Set(Self.fixtureTypes.keys))
    }

    @Test func fullStateWhileActingAs() throws {
        let state = try Fixtures.decode(GummiState.self, "state_full")
        #expect(state.actingAs == "p_012")
        #expect(state.following == "p_012")
        #expect(state.mood == .high)
        #expect(state.gummiView?.trend == .risingFast)
        #expect(state.gummiView?.confidence == .low)
        #expect(state.alert?.action.kind == .startWalk)
        #expect(state.alert?.action.minutes == 10)
        #expect(state.topCard?.type == .walkSuggested)
        #expect(state.topCard?.attachments?.alert?.alertId == "a_1")
        #expect(state.upcomingDue.first?.dueId == "d_2")
        #expect(state.replayNow == JSONCoding.parseDate("2026-10-03T06:10:00-04:00"))
        #expect(state.stream.replayAnchor.replayTime != nil)
        #expect(state.today.cgmOnlyMaeMgDl == 10.8)
        #expect(state.modelVersion == "gummi_model_v1.2")
    }

    @Test func nullableStateFields() throws {
        let state = try Fixtures.decode(GummiState.self, "state_null")
        #expect(state.following == nil && state.actingAs == nil)
        #expect(state.gummiView == nil && state.alert == nil && state.topCard == nil && state.replayNow == nil)
        #expect(state.confirmed.isEmpty && state.forecast.isEmpty)
        #expect(state.today.gummiMaeMgDl == nil)
        #expect(state.stream.replayClock == nil)
        #expect(state.stream.pipelineLagSeconds == nil)
        #expect(state.stream.replayAnchor.wallTime == nil)
        #expect(state.dexcom.lastSync == nil)
    }

    @Test func liveFleetFromTheDeployedApp() throws {
        let fleet = try Fixtures.decode(Fleet.self, "live_fleet")
        #expect(fleet.entries.count == 15)
        #expect(!fleet.entries.contains { $0.userId == "p_015" })
        #expect(fleet.entries.allSatisfy { $0.lastGrade != nil })
        #expect(fleet.entries.first?.lastGrade?.kind == .nowcast)
    }

    @Test func mealDueResolvesByUpsert() throws {
        let due = try Fixtures.decode(StoryCard.self, "card_meal_due")
        let resolved = try Fixtures.decode(StoryCard.self, "card_meal_due_resolved")
        #expect(due.type == .mealDue)
        #expect(due.pendingDueId == "d_1")
        #expect(resolved.cardId == due.cardId)
        #expect(resolved.pendingDueId == nil)
        #expect(resolved.body.hasSuffix("Logged."))
    }

    @Test func attachmentsPerCardType() throws {
        let logged = try Fixtures.decode(StoryCard.self, "card_meal_logged")
        #expect(logged.attachments?.meal?.isStandardBreakfast == true)
        #expect(logged.attachments?.prediction?.cgmOnlyPeakMgDl == 139)
        let story = try Fixtures.decode(StoryCard.self, "card_meal_story")
        #expect(story.attachments?.grade?.gradeId == "g_1")
        #expect(story.attachments?.curve?.count == 3)
        #expect(story.actions.first?.kind == .openChat)
        let walk = try Fixtures.decode(StoryCard.self, "card_walk_summary")
        #expect(walk.attachments?.walk?.effectSource == .literature)
        let brief = try Fixtures.decode(StoryCard.self, "card_morning_briefing")
        #expect(brief.attachments == nil)
        #expect(brief.generatedBy == .agent)
    }

    @Test func gradesCarryHonestyFlags() throws {
        let notGraded = try Fixtures.decode(Grade.self, "grade_walk_not_graded")
        #expect(notGraded.walkEffectGraded == false)
        #expect(notGraded.earnsProud)
        let noCgmOnly = try Fixtures.decode(Grade.self, "grade_null_cgm_only")
        #expect(noCgmOnly.cgmOnlyMaeMgDl == nil)
        #expect(noCgmOnly.gummiBeatsCgmOnly == nil)
        #expect(!noCgmOnly.earnsProud)
    }

    @Test func simulationAndWalkEnums() throws {
        let sim = try Fixtures.decode(Simulation.self, "simulation")
        #expect(sim.verdict == .goWithTweak)
        #expect(sim.method == .model)
        #expect(sim.items.first?.unit == "")
        #expect(sim.alternatives.last?.effectSource == .literature)
        #expect(sim.alternatives.first?.effectSource == nil)
    }

    @Test func unknownValuesNeverFailADecode() throws {
        let card = try Fixtures.decode(StoryCard.self, "card_unknown_type")
        #expect(card.type == .unknown)
        #expect(!card.type.isKnown)
        let json = Data(#"{"mood":"ecstatic"}"#.utf8)
        struct Box: Decodable { let mood: Mood }
        #expect(try JSONCoding.decoder().decode(Box.self, from: json).mood == .unknown)
    }

    @Test func errorBodyAndDates() throws {
        let error = try Fixtures.decode(APIErrorBody.self, "live_error_not_found")
        #expect(error.error.code == "not_found")
        #expect(JSONCoding.parseDate("2026-10-03T22:07:23-04:00") != nil)
        #expect(JSONCoding.parseDate("2026-10-04T02:07:23Z") == JSONCoding.parseDate("2026-10-03T22:07:23-04:00"))
        #expect(JSONCoding.parseDate("2026-10-04T02:07:23.250Z") != nil)
        #expect(JSONCoding.parseDate("day6T08:15") == nil)
    }

    @Test func stateRoundTrips() throws {
        let state = try Fixtures.decode(GummiState.self, "state_full")
        let data = try JSONCoding.encoder().encode(state)
        #expect(try JSONCoding.decoder().decode(GummiState.self, from: data) == state)
    }

    @Test func replayAnchorConvertsToWallClock() throws {
        let stream = try Fixtures.decode(StreamStatus.self, "live_stream_status")
        let anchorReplay = try #require(stream.replayAnchor.replayTime)
        let anchorWall = try #require(stream.replayAnchor.wallTime)
        // One replay hour at 60x is one wall minute.
        let wall = try #require(stream.wallTime(forReplay: anchorReplay.addingTimeInterval(3600)))
        #expect(abs(wall.timeIntervalSince(anchorWall) - 60) < 0.001)
        let stopped = try Fixtures.decode(StreamStatus.self, "stream_status_stopped")
        #expect(stopped.wallTime(forReplay: anchorReplay) == nil)
    }
}
