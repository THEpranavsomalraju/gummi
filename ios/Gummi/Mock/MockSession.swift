import Foundation

/// The scripted demo day as a pure value: advance the replay clock, get the live events the backend would send.
/// Acting as p_012 (D-61), replay day 4 (D-15) from 05:00 (D-62) to 22:30, with the contract's rules:
/// meals come due and auto-log after 10 replay minutes, data runs 60 minutes behind, grades land when
/// confirmed data covers the 2-hour window, proud only when Gummi beats CGM-only, walk overlap means
/// walk_effect_graded false. Every number here is scripted for the mock and shown under a "Mock" badge.
nonisolated struct MockSession: Sendable {
    static let startMinute = 300.0
    static let endMinute = 1350.0
    static let participant = "p_012"
    static let displayName = "Participant 12"
    static let delayMinutes = 60.0
    static let highLine = 140.0
    static let lowLine = 70.0

    /// Scripted outcome per graded meal: prediction offset from the real peak, CGM-only peak, and three MAEs.
    struct GradeScript: Sendable {
        let peakOffset: Double
        let cgmOnlyPeak: Double
        let gummiMae: Double
        let cgmOnlyMae: Double
        let lastValueMae: Double
        let withinBand: Double
    }

    /// Day 4 (D-15), peaks from Data's demo_day README (DRAFT): Gummi's curve beats CGM-only on every scripted meal
    /// but the cheese bite, which nods. Breakfast overlaps the scripted walk, so it's marked not graded.
    /// The mock MAEs are placeholders shown only under the Mock badge (D-69).
    static let gradeScripts: [Int: GradeScript] = [
        0: GradeScript(peakOffset: -53, cgmOnlyPeak: 112, gummiMae: 21.4, cgmOnlyMae: 33.1, lastValueMae: 38.0, withinBand: 62.5),
        1: GradeScript(peakOffset: 39, cgmOnlyPeak: 161, gummiMae: 14.2, cgmOnlyMae: 27.5, lastValueMae: 41.0, withinBand: 70.8),
        5: GradeScript(peakOffset: -14, cgmOnlyPeak: 109, gummiMae: 9.8, cgmOnlyMae: 7.6, lastValueMae: 14.1, withinBand: 83.3),
        6: GradeScript(peakOffset: -47, cgmOnlyPeak: 112, gummiMae: 18.9, cgmOnlyMae: 29.6, lastValueMae: 31.8, withinBand: 66.7),
        7: GradeScript(peakOffset: -35, cgmOnlyPeak: 129, gummiMae: 15.7, cgmOnlyMae: 24.4, lastValueMae: 30.2, withinBand: 75.0),
        8: GradeScript(peakOffset: -8, cgmOnlyPeak: 135, gummiMae: 7.4, cgmOnlyMae: 21.3, lastValueMae: 18.9, withinBand: 91.7),
    ]

    enum Output: Sendable {
        case event(LiveEvent)
        /// The stream pauses for this many wall seconds, then resumes.
        case pause(seconds: Double)
    }

    struct LoggedMeal: Sendable {
        let meal: Meal
        let loggedAt: Double
    }

    let day: MockDay
    let dayStart: Date
    private(set) var minute = MockSession.startMinute
    var following: String? = MockSession.participant
    private(set) var cards: [StoryCard] = []
    private(set) var logged: [Int: LoggedMeal] = [:]
    private(set) var predictions: [Int: Prediction] = [:]
    private(set) var grades: [Grade] = []
    private(set) var alert: GummiAlert?
    private var lastAlertMinute: Double?
    private(set) var walk: ClosedRange<Double>?
    private var walkPosted = false
    private var proudUntil: Date?
    /// Happy after a real phone walk (wall clock; the mock day runs fast).
    private var happyUntil: Date?
    private var phoneWalks = 0
    private(set) var eventsReleased = 0

    init(day: MockDay, today: Date = .now, timeZone: TimeZone = TimeZone(identifier: "America/New_York")!) {
        self.day = day
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        dayStart = calendar.startOfDay(for: today)
    }

    func date(_ minute: Double) -> Date { dayStart.addingTimeInterval(minute * 60) }
    var dataThrough: Double { minute - Self.delayMinutes }

    mutating func reset() {
        self = MockSession(day: day, today: dayStart.addingTimeInterval(12 * 3600))
    }

    // MARK: Script

    /// Moves the replay clock forward and returns what the backend would push, in order.
    mutating func advance(to newMinute: Double, wallNow: Date) -> [Output] {
        guard newMinute > minute else { return [] }
        var outputs: [Output] = []
        let first = Int(minute.rounded(.down)) + 1, last = Int(min(newMinute, Self.endMinute).rounded(.down))
        if first <= last {
            for m in first...last {
                minute = Double(m)
                outputs += beats(at: m, wallNow: wallNow)
            }
        }
        minute = min(newMinute, Self.endMinute)
        eventsReleased += Int((newMinute - Double(first - 1)) * 3)
        return outputs
    }

    private mutating func beats(at m: Int, wallNow: Date) -> [Output] {
        var out: [Output] = []
        let mm = Double(m)
        for meal in day.meals where meal.minute == m {
            let due = dueCard(for: meal)
            upsert(due)
            out.append(.event(.card(due)))
        }
        for meal in day.meals where meal.minute + 10 == m && logged[meal.index] == nil {
            out += logMeal(meal, source: .replayAuto).events.map(Output.event)
        }
        if m == 360 {
            out.append(.event(.card(card("c_brief", .morningBriefing, at: mm, title: "Good morning",
                                         body: "Participant 12's day starts now. Breakfast came due at 5:56. I'll watch what it does.",
                                         mood: .calm, by: .agent))))
        }
        if let current = alert, mm >= current.expiresAt.timeIntervalSince(dayStart) / 60 {
            alert = nil
        }
        if m >= 360, alert == nil, lastAlertMinute.map({ mm - $0 >= 45 }) ?? true,
           (forecast(at: mm).prefix(13).map(\.glucoseMgDl).max() ?? 0) >= Self.highLine {
            out += raiseWalkAlert(at: mm)
        }
        if let walk, !walkPosted, mm >= walk.upperBound {
            walkPosted = true
            alert = nil
            let summary = WalkSummary(startedAt: date(walk.lowerBound), endedAt: date(walk.upperBound),
                                      minutes: Int(walk.upperBound - walk.lowerBound), steps: 1260, cadenceSpm: 105,
                                      intensity: .moderate, forecastPeakDropMgDl: 14, effectSource: .literature)
            out.append(.event(.card(card("c_walk", .walkSummary, at: mm, title: "Nice walk",
                                         body: "12 minutes at a moderate pace. Modeled effect: about 14 lower at the peak (literature).",
                                         mood: .happy, attachments: CardAttachments(walk: summary)))))
        }
        for (index, prediction) in predictions.sorted(by: { $0.key < $1.key }) where prediction.status == .pending {
            let eaten = Double(day.meals[index].minute)
            if dataThrough >= eaten + 120 {
                out += grade(index, prediction: prediction, at: mm, wallNow: wallNow).map(Output.event)
            }
        }
        if m == 600 { out.append(.pause(seconds: 4)) }
        if m == 1200 {
            let graded = grades.filter(\.walkEffectGraded)
            let line = graded.isEmpty ? "" : " Graded meals today: Gummi off by \(Int(graded.map(\.gummiMaeMgDl).average.rounded())), CGM-only \(Int(graded.compactMap(\.cgmOnlyMaeMgDl).average.rounded()))."
            out.append(.event(.card(card("c_recap", .eveningRecap, at: mm, title: "Today with Participant 12",
                                         body: "The evening sweets were the big ones.\(line) Tomorrow: try a 10-minute walk right after dessert.",
                                         mood: .calm, by: .agent))))
        }
        return out
    }

    /// The user tapped Log it (source replay_due), or the 10-minute auto-log fired (replay_auto).
    mutating func logDue(dueId: String) throws -> (Meal, [LiveEvent]) {
        guard let index = Int(dueId.dropFirst(2)).map({ $0 - 1 }), day.meals.indices.contains(index),
              Double(day.meals[index].minute) <= minute else {
            throw APIError.http(status: 404, code: "not_found", message: "\(dueId) is not due")
        }
        guard logged[index] == nil else {
            throw APIError.http(status: 409, code: "due_already_logged", message: "\(dueId) was logged already")
        }
        return logMeal(day.meals[index], source: .replayDue)
    }

    private mutating func logMeal(_ dayMeal: MockDay.DayMeal, source: MealSource) -> (meal: Meal, events: [LiveEvent]) {
        let index = dayMeal.index
        var prediction: Prediction?
        if let script = Self.gradeScripts[index] {
            prediction = makePrediction(for: dayMeal, script: script)
            predictions[index] = prediction
        }
        let meal = Meal(mealId: "m_\(index + 1)", eatenAt: date(Double(dayMeal.minute)), source: source,
                        items: dayMeal.items, totals: dayMeal.totals, isStandardBreakfast: dayMeal.isStandardBreakfast,
                        predictionId: prediction?.predictionId)
        logged[index] = LoggedMeal(meal: meal, loggedAt: minute)
        var resolved = dueCard(for: dayMeal)
        resolved = StoryCard(cardId: resolved.cardId, type: .mealDue, createdAt: resolved.createdAt, title: resolved.title,
                             body: dayMeal.text + ". Logged.", mood: resolved.mood, actions: [], generatedBy: .template)
        upsert(resolved)
        let body = prediction.map { "I expect a peak near \(Int($0.predictedPeakMgDl)). I'll grade it two hours after eating." }
            ?? "Logged \(dayMeal.text)."
        let loggedCard = card("c_logged_\(index + 1)", .mealLogged, at: minute, title: "\(dayMeal.label) logged",
                              body: body, mood: prediction == nil ? .calm : .rising,
                              attachments: CardAttachments(meal: meal, prediction: prediction))
        return (meal, [.card(resolved), .card(loggedCard)])
    }

    private func makePrediction(for dayMeal: MockDay.DayMeal, script: GradeScript) -> Prediction {
        let start = Double(dayMeal.minute), end = start + 120
        let curve = stride(from: start, through: end, by: 15).map { t in
            let width = 52.0
            let g = day.glucose(at: t) + script.peakOffset * min(1, (t - start) / 40)
            return BandPoint(t: date(t), glucoseMgDl: g.rounded(toPlaces: 1), bandLowMgDl: (g - width / 2).rounded(toPlaces: 1),
                             bandHighMgDl: (g + width / 2).rounded(toPlaces: 1), kind: .forecast)
        }
        let realPeak = day.peak(from: dayMeal.minute, to: dayMeal.minute + 120)?.glucose ?? day.glucose(at: start)
        let lastValue = day.lastReading(atOrBefore: minute - Self.delayMinutes)?.glucose ?? realPeak
        return Prediction(predictionId: "pr_\(dayMeal.index + 1)", kind: .meal, madeAt: date(minute),
                          about: "\(dayMeal.label): \(dayMeal.text)", mealId: "m_\(dayMeal.index + 1)",
                          windowStart: date(start), windowEnd: date(end), predictedPeakMgDl: realPeak + script.peakOffset,
                          predictedCurve: curve, cgmOnlyPeakMgDl: script.cgmOnlyPeak, lastValuePeakMgDl: lastValue, status: .pending)
    }

    private mutating func grade(_ index: Int, prediction: Prediction, at mm: Double, wallNow: Date) -> [LiveEvent] {
        guard let script = Self.gradeScripts[index] else { return [] }
        let dayMeal = day.meals[index]
        let window = Double(dayMeal.minute)...Double(dayMeal.minute + 120)
        let walkOverlaps = walk.map { $0.overlaps(window) } ?? false
        let realPeak = day.peak(from: dayMeal.minute, to: dayMeal.minute + 120)?.glucose ?? prediction.predictedPeakMgDl
        let beatsCgmOnly = script.gummiMae < script.cgmOnlyMae
        var message = "I predicted \(Int(prediction.predictedPeakMgDl)) for \(dayMeal.label.lowercased()). It was \(Int(realPeak)). CGM-only said \(Int(script.cgmOnlyPeak)), last value said \(Int(prediction.lastValuePeakMgDl))."
        if walkOverlaps { message += " Walk effect not graded (replayed data)." }
        let grade = Grade(gradeId: "g_\(index + 1)", predictionId: prediction.predictionId, kind: .meal, gradedAt: date(mm),
                          points: 24, gummiMaeMgDl: script.gummiMae, cgmOnlyMaeMgDl: script.cgmOnlyMae,
                          lastValueMaeMgDl: script.lastValueMae, gummiPeakErrorMgDl: abs(script.peakOffset),
                          withinBandPct: script.withinBand, walkEffectGraded: !walkOverlaps,
                          gummiBeatsCgmOnly: beatsCgmOnly, gummiBeatsLastValue: script.gummiMae < script.lastValueMae,
                          message: message)
        grades.append(grade)
        predictions[index] = Prediction(predictionId: prediction.predictionId, kind: prediction.kind, madeAt: prediction.madeAt,
                                        about: prediction.about, mealId: prediction.mealId, windowStart: prediction.windowStart,
                                        windowEnd: prediction.windowEnd, predictedPeakMgDl: prediction.predictedPeakMgDl,
                                        predictedCurve: prediction.predictedCurve, cgmOnlyPeakMgDl: prediction.cgmOnlyPeakMgDl,
                                        lastValuePeakMgDl: prediction.lastValuePeakMgDl, status: .graded)
        let curve = day.readings.filter { window.contains(Double($0.minute)) }
            .map { GlucosePoint(t: date(Double($0.minute)), glucoseMgDl: $0.glucose, kind: .confirmed) }
        let story = card("c_story_\(index + 1)", .mealStory, at: mm, title: "Your \(dayMeal.label.lowercased()), two hours later",
                         body: "Peak \(Int(realPeak)). \(message)", mood: beatsCgmOnly ? .proud : .calm,
                         attachments: CardAttachments(meal: logged[index]?.meal, grade: grade, curve: curve),
                         actions: [CardAction(label: "Ask Gummi why", kind: .openChat, prompt: "Why did I peak at \(Int(realPeak))?")],
                         by: .agent)
        var events: [LiveEvent] = [.grade(grade), .card(story)]
        if grade.earnsProud {
            proudUntil = wallNow.addingTimeInterval(20)
            events.append(.mood(.proud))
        }
        return events
    }

    private mutating func raiseWalkAlert(at mm: Double) -> [Output] {
        lastAlertMinute = mm
        let peak = forecast(at: mm).prefix(13).map(\.glucoseMgDl).max() ?? Self.highLine
        let raised = GummiAlert(alertId: "a_\(Int(mm))", type: .walkSuggested,
                                message: "Your forecast likely crosses 140 (peak near \(Int(peak))). A 10-minute walk now may help.",
                                createdAt: date(mm), expiresAt: date(mm + 30),
                                action: AlertAction(label: "Start walk", kind: .startWalk, minutes: 10))
        alert = raised
        // The scripted phone walk: only for the first alert of the day.
        if walk == nil { walk = (mm + 5)...(mm + 17) }
        return [.event(.alert(raised)),
                .event(.card(card("c_walk_suggested_\(Int(mm))", .walkSuggested, at: mm, title: "A walk would help",
                                  body: raised.message, mood: .high, attachments: CardAttachments(alert: raised))))]
    }

    /// A real walk from the phone, overlaid on the replayed day (D-28).
    mutating func addPhoneWalk(_ walk: WalkSummary, wallNow: Date) -> StoryCard {
        phoneWalks += 1
        happyUntil = wallNow.addingTimeInterval(60)
        return card("c_phone_walk_\(phoneWalks)", .walkSummary, at: minute, title: "Nice walk",
                    body: "\(walk.minutes) minutes, \(walk.steps.formatted()) steps, \(walk.intensity.rawValue) pace. Modeled effect: about \(Int(walk.forecastPeakDropMgDl)) mg/dL lower peak (literature). Your real walk is shown over the replayed day; its effect on replayed glucose isn't graded.",
                    mood: .happy, attachments: CardAttachments(walk: walk))
    }

    /// A meal Gummi saved from chat. Like the backend (D-59) it sits on the participant's day and is never graded.
    mutating func addChatMeal(_ meal: Meal, likelyPeak: Double?) -> StoryCard {
        let body = likelyPeak.map {
            "Added to your food log. I think this likely peaks near \(Int($0.rounded())) mg/dL. It's simulated on \(Self.displayName)'s day, so I won't grade it."
        } ?? "Saved to your food log."
        let name = meal.items.first?.name ?? "Meal"
        return card("c_\(meal.mealId)", .mealLogged, at: minute, title: "\(name.prefix(1).uppercased() + name.dropFirst()) logged",
                    body: body, mood: .calm, attachments: CardAttachments(meal: meal))
    }

    private func dueCard(for meal: MockDay.DayMeal) -> StoryCard {
        makeCard("c_due_\(meal.index + 1)", .mealDue, at: Double(meal.minute), title: "\(meal.label) time for \(Self.displayName)",
             body: meal.text, mood: .calm,
             actions: [CardAction(label: "Log it", kind: .logDueMeal, dueId: "d_\(meal.index + 1)")])
    }

    /// Builds a card and upserts it into the feed.
    private mutating func card(_ id: String, _ type: CardType, at mm: Double, title: String, body: String, mood: Mood,
                               attachments: CardAttachments? = nil, actions: [CardAction] = [],
                               by: GeneratedBy = .template) -> StoryCard {
        let made = makeCard(id, type, at: mm, title: title, body: body, mood: mood, attachments: attachments,
                            actions: actions, by: by)
        upsert(made)
        return made
    }

    private func makeCard(_ id: String, _ type: CardType, at mm: Double, title: String, body: String, mood: Mood,
                          attachments: CardAttachments? = nil, actions: [CardAction] = [],
                          by: GeneratedBy = .template) -> StoryCard {
        StoryCard(cardId: id, type: type, createdAt: date(mm), title: title, body: body, mood: mood,
                  attachments: attachments, actions: actions, traceId: by == .agent ? "tr_mock_\(id)" : nil,
                  generatedBy: by)
    }

    private mutating func upsert(_ card: StoryCard) {
        if let i = cards.firstIndex(where: { $0.cardId == card.cardId }) {
            cards[i] = card
        } else {
            cards.insert(card, at: 0)
        }
    }

    // MARK: Curves

    private func bandWidth(horizon: Double, mealWindow: Bool) -> Double {
        let points: [(Double, Double)] = mealWindow ? [(0, 51), (30, 55), (60, 57), (120, 55)] : [(0, 26), (30, 31), (60, 39), (120, 46)]
        guard let upper = points.firstIndex(where: { $0.0 >= horizon }) else { return points.last!.1 }
        guard upper > 0 else { return points[0].1 }
        let (h0, w0) = points[upper - 1], (h1, w1) = points[upper]
        return w0 + (w1 - w0) * (horizon - h0) / (h1 - h0)
    }

    private func inMealWindow(_ m: Double) -> Bool {
        logged.values.contains { m - $0.meal.eatenAt.timeIntervalSince(dayStart) / 60 < 180 && m >= $0.meal.eatenAt.timeIntervalSince(dayStart) / 60 }
    }

    /// Gummi's estimate of the delay gap, data_through to now. Bands widen through the gap.
    func estimate(at m: Double) -> [BandPoint] {
        let from = m - Self.delayMinutes
        let nowWidth = bandWidth(horizon: 0, mealWindow: inMealWindow(m))
        return stride(from: from, through: m, by: 5).map { t in
            let g = day.glucose(at: t) + 2
            let width = max(6, nowWidth * (t - from) / Self.delayMinutes)
            return BandPoint(t: date(t), glucoseMgDl: g.rounded(toPlaces: 1), bandLowMgDl: (g - width / 2).rounded(toPlaces: 1),
                             bandHighMgDl: (g + width / 2).rounded(toPlaces: 1), kind: .estimate)
        }
    }

    /// Two hours ahead. Inside a logged meal's window it follows the meal; otherwise it drifts toward the person's mean.
    func forecast(at m: Double) -> [BandPoint] {
        let now = day.glucose(at: m) + 2
        let mealWindow = inMealWindow(m)
        let mealStarts = logged.values.map { $0.meal.eatenAt.timeIntervalSince(dayStart) / 60 }
        return stride(from: 5.0, through: 120, by: 5).map { h in
            let t = m + h
            let covered = mealStarts.contains { t >= $0 && t <= $0 + 240 }
            let g = covered ? day.glucose(at: t) - 4 : now + (112 - now) * (h / 240)
            let width = bandWidth(horizon: h, mealWindow: mealWindow)
            return BandPoint(t: date(t), glucoseMgDl: g.rounded(toPlaces: 1), bandLowMgDl: (g - width / 2).rounded(toPlaces: 1),
                             bandHighMgDl: (g + width / 2).rounded(toPlaces: 1), kind: .forecast)
        }
    }

    // MARK: State

    func snapshot(wallNow: Date, paused: Bool, minutesPerSecond: Double) -> GummiState {
        let speed = minutesPerSecond * 60
        let stream = StreamStatus(running: true, paused: paused, speed: speed, delayMinutes: Int(Self.delayMinutes), participants: 15,
                                  replayClock: String(format: "day4T%02d:%02d", Int(minute) / 60, Int(minute) % 60),
                                  replayAnchor: ReplayAnchor(replayTime: date(minute), wallTime: wallNow),
                                  eventsReleased: eventsReleased, eventsPerSecond: paused ? 0 : 0.05 * speed,
                                  pipelineLagSeconds: nil)
        let dexcom = DexcomStatus(connected: false, environment: .sandbox, dataThrough: nil, delayMinutes: 60, lastSync: nil,
                                  lastError: nil, source: .replay, ingestMode: .statusOnly)
        let profile = ProfileLines(highLineMgDl: Self.highLine, lowLineMgDl: Self.lowLine)
        guard following != nil else {
            return GummiState(userId: "u_mahil", following: nil, actingAs: nil, dexcom: dexcom, gummiView: nil, confirmed: [],
                              estimate: [], forecast: [], mood: .calm, alert: nil, topCard: nil, pendingPredictions: [],
                              today: Today(timeInRangePct: 0, peakMgDl: 0, meals: 0, steps: 0, walks: 0, gummiMaeMgDl: nil,
                                           cgmOnlyMaeMgDl: nil, lastValueMaeMgDl: nil),
                              profile: profile, upcomingDue: [], replayNow: nil, stream: stream, modelVersion: "mock",
                              serverTime: wallNow)
        }

        let through = dataThrough
        let confirmed = day.readings.filter { Double($0.minute) > through - 360 && Double($0.minute) <= through }
            .map { GlucosePoint(t: date(Double($0.minute)), glucoseMgDl: $0.glucose, kind: .confirmed) }
        let estimate = estimate(at: minute)
        let forecast = forecast(at: minute)
        let nowPoint = estimate.last
        let slope = (day.glucose(at: minute) - day.glucose(at: minute - 15)) / 15
        let trend: Trend = slope > 2 ? .risingFast : slope > 1 ? .rising : slope < -2 ? .fallingFast : slope < -1 ? .falling : .flat
        let width = (nowPoint?.bandHighMgDl ?? 0) - (nowPoint?.bandLowMgDl ?? 0)
        let view = nowPoint.map {
            GummiView(glucoseMgDl: $0.glucoseMgDl, bandLowMgDl: $0.bandLowMgDl, bandHighMgDl: $0.bandHighMgDl, trend: trend,
                      asOf: date(minute), minutesSinceConfirmed: Int(minute - (day.lastReading(atOrBefore: through).map { Double($0.minute) } ?? through)),
                      confidence: width < 25 ? .high : width <= 45 ? .medium : .low)
        }

        let soFar = day.readings.filter { Double($0.minute) <= through }
        let inRange = soFar.filter { $0.glucose >= Self.lowLine && $0.glucose <= Self.highLine }.count
        let walkDone = walk.map { minute >= $0.upperBound } ?? false
        let graded = grades.filter(\.walkEffectGraded)
        let today = Today(timeInRangePct: soFar.isEmpty ? 0 : (100 * Double(inRange) / Double(soFar.count)).rounded(toPlaces: 1),
                          peakMgDl: soFar.map(\.glucose).max() ?? 0, meals: logged.count, steps: 3200 + (walkDone ? 1260 : 0),
                          walks: walkDone ? 1 : 0,
                          gummiMaeMgDl: graded.isEmpty ? nil : graded.map(\.gummiMaeMgDl).average.rounded(toPlaces: 1),
                          cgmOnlyMaeMgDl: graded.isEmpty ? nil : graded.compactMap(\.cgmOnlyMaeMgDl).average.rounded(toPlaces: 1),
                          lastValueMaeMgDl: graded.isEmpty ? nil : graded.map(\.lastValueMaeMgDl).average.rounded(toPlaces: 1))

        let upcoming: [UpcomingDue] = paused ? [] : day.meals
            .filter { Double($0.minute) > minute && Double($0.minute) <= minute + 360 }
            .map { meal in
                UpcomingDue(dueId: "d_\(meal.index + 1)",
                            dueAt: wallNow.addingTimeInterval((Double(meal.minute) - minute) / minutesPerSecond),
                            title: "\(meal.label) time for \(Self.displayName)", body: meal.text)
            }

        return GummiState(userId: "u_mahil", following: following, actingAs: following, dexcom: dexcom, gummiView: view,
                          confirmed: confirmed, estimate: estimate, forecast: forecast,
                          mood: mood(view: view, forecast: forecast, wallNow: wallNow),
                          alert: alert, topCard: cards.first, pendingPredictions: predictions.values.filter { $0.status == .pending }
                            .sorted { $0.madeAt < $1.madeAt },
                          today: today, profile: profile, upcomingDue: upcoming, replayNow: date(minute), stream: stream,
                          modelVersion: "mock", serverTime: wallNow)
    }

    /// CONTRACT section 9 priority: low, high, proud, dipping, rising, happy, sleepy, calm.
    private func mood(view: GummiView?, forecast: [BandPoint], wallNow: Date) -> Mood {
        let peak = forecast.map(\.glucoseMgDl).max() ?? 0
        let lowest = min(forecast.map(\.glucoseMgDl).min() ?? .infinity, view?.glucoseMgDl ?? .infinity)
        if lowest <= Self.lowLine { return .low }
        if peak >= Self.highLine { return .high }
        if let proudUntil, wallNow < proudUntil { return .proud }
        if let happyUntil, wallNow < happyUntil { return .happy }
        if view?.trend == .fallingFast { return .dipping }
        if view?.trend == .rising || view?.trend == .risingFast { return .rising }
        if let walk, minute >= walk.upperBound, minute < walk.upperBound + 30 { return .happy }
        if minute < 360 { return .sleepy }
        return .calm
    }
}

nonisolated extension Array where Element == Double {
    var average: Double { isEmpty ? 0 : reduce(0, +) / Double(count) }
}

nonisolated extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let scale = pow(10, Double(places))
        return (self * scale).rounded() / scale
    }
}
