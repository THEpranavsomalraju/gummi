import Foundation

/// MockAPI's scripted chat. A message is routed by keywords to the same event order the backend's agent emits
/// (agent/chat.py): mood thinking, each tool's start and end followed by its card, the reply in 24-character tokens,
/// the final mood, then done. Numbers come from the mock day's State, so the cards and the reply agree.
nonisolated enum MockChat {
    struct Step: Sendable {
        let delay: Duration
        let event: ChatEvent
    }

    struct Reply: Sendable {
        var steps: [Step]
        /// The meal log_meal saved, for the engine to keep (PATCH) and announce (meal_logged card).
        var savedMeal: SavedMeal? = nil
        var likelyPeak: Double? = nil
    }

    enum Route: Equatable, Sendable {
        case simulate, logMeal, walk, today, grade, state, spike
        /// Anything else: what Gummi can do, without leading with the estimate.
        case help
        /// "mock error": the backend's failure path (apology, gummi_view card, error, done).
        case failure
        /// "mock busy": the rate_limited error with no done.
        case busy
    }

    /// One seed food: macros for one portion.
    struct Seed: Sendable {
        let keyword: String
        let name: String
        let unit: String
        let carbs: Double
        let sugar: Double
        let fiber: Double
        let protein: Double
        let fat: Double
        let calories: Double

        func item(quantity: Double) -> MealItem {
            MealItem(name: name, quantity: 1, unit: unit, carbsG: carbs, sugarG: sugar, fiberG: fiber, proteinG: protein,
                     fatG: fat, calories: calories, nutritionSource: .seed, editable: true)
                .scaled(toQuantity: quantity)
        }
    }

    static let seeds: [Seed] = [
        Seed(keyword: "cookie", name: "cookie", unit: "", carbs: 22, sugar: 12, fiber: 0.5, protein: 1.5, fat: 7, calories: 160),
        Seed(keyword: "granola", name: "granola bar", unit: "bar", carbs: 29, sugar: 12, fiber: 2, protein: 3, fat: 6, calories: 190),
        Seed(keyword: "apple", name: "apple", unit: "medium", carbs: 25, sugar: 19, fiber: 4.4, protein: 0.5, fat: 0.3, calories: 95),
        Seed(keyword: "banana", name: "banana", unit: "medium", carbs: 27, sugar: 14, fiber: 3.1, protein: 1.3, fat: 0.4, calories: 105),
        Seed(keyword: "pizza", name: "pizza", unit: "slice", carbs: 35, sugar: 4, fiber: 2, protein: 12, fat: 10, calories: 285),
        Seed(keyword: "bagel", name: "bagel", unit: "", carbs: 48, sugar: 6, fiber: 2, protein: 10, fat: 1.5, calories: 245),
        Seed(keyword: "ice cream", name: "ice cream", unit: "cup", carbs: 32, sugar: 28, fiber: 1, protein: 5, fat: 14, calories: 270),
        Seed(keyword: "rice", name: "rice", unit: "cup", carbs: 45, sugar: 0, fiber: 0.6, protein: 4.3, fat: 0.4, calories: 205),
        Seed(keyword: "soda", name: "soda", unit: "can", carbs: 39, sugar: 39, fiber: 0, protein: 0, fat: 0, calories: 150),
        Seed(keyword: "yogurt", name: "greek yogurt", unit: "cup", carbs: 9, sugar: 7, fiber: 0, protein: 20, fat: 5, calories: 150),
    ]

    /// Modeled post-meal walking effect for 10 minutes, labeled literature (DATA_NOTES section 6).
    static let walkDrop = 14.0

    static func route(_ message: String) -> Route {
        let text = message.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { text.contains($0) } }
        if text.contains("mock busy") { return .busy }
        if text.contains("mock error") { return .failure }
        // Telling Gummi you ate something logs it; asking whether you can eat it simulates (Pranav's routing fix).
        let asks = has(["can i", "should i", "could i", "is it ok", "would it"])
        if !asks, text.range(of: #"\b(add|added|log|logged|ate|had)\b"#, options: .regularExpression) != nil { return .logMeal }
        if has(["can i eat", "can i have", "should i eat", "should i have", "is it ok"]) { return .simulate }
        if food(in: text) != nil, text.contains("?") { return .simulate }
        if text.contains("walk") { return .walk }
        if has(["spike", "why did i", "peak"]) { return .spike }
        if has(["grade", "how did you do", "accura", "predict"]) { return .grade }
        if has(["today", "how am i", "doing", "my day"]) { return .today }
        if has(["right now", "estimate", "current", "my glucose", "my sugar", "where am i"]) { return .state }
        return .help
    }

    static func food(in text: String) -> Seed? {
        seeds.first { text.lowercased().contains($0.keyword) }
    }

    static func quantity(in text: String) -> Double {
        let text = text.lowercased()
        if text.contains("half") { return 0.5 }
        if let number = text.split(whereSeparator: { !$0.isNumber }).compactMap({ Double($0) }).first, number > 0 {
            return number
        }
        let words: [(String, Double)] = [("two", 2), ("three", 3), ("four", 4)]
        return words.first { text.contains($0.0) }?.1 ?? 1
    }

    // MARK: Replies

    static func reply(to message: String, state: GummiState, latestGrade: Grade?, turn: Int, conversationId: String) -> Reply {
        var script = Script()
        let traceId = "tr_mock_chat_\(turn)"
        let acting = state.actingAs.map { _ in MockSession.displayName }
        let high = state.profile.highLineMgDl

        switch route(message) {
        case .busy:
            return Reply(steps: [Step(delay: .milliseconds(80), event: .error(code: "rate_limited", message: "One message at a time, please."))])

        case .failure:
            script.say("Sorry, I lost my train of thought there. Try me again in a moment.")
            if let view = state.gummiView { script.card(.gummiView(view)) }
            script.steps.append(Step(delay: .milliseconds(40), event: .error(code: "internal", message: "The coach is unavailable right now.")))
            script.steps.append(Step(delay: .milliseconds(20), event: .done(conversationId: conversationId, traceId: nil)))
            return Reply(steps: script.steps)

        case .simulate:
            let seed = food(in: message) ?? seeds[0]
            let item = seed.item(quantity: quantity(in: message))
            guard let simulation = simulate([item], state: state, turn: turn) else {
                script.tool("simulate_food", card: nil)
                script.say("I can't simulate that yet: I'm not following anyone. Pick a participant from the header first.")
                script.end(mood: .calm, conversationId: conversationId, traceId: traceId)
                return Reply(steps: script.steps)
            }
            script.tool("simulate_food", card: .simulation(simulation))
            guard simulation.isReliable else {
                script.say("That's more than I've learned to predict: about \(Int(simulation.requestedCarbsG ?? 0)) g of carbs. It would very likely spike you well above your range. A smaller portion is something I can actually forecast.")
                script.end(mood: .high, conversationId: conversationId, traceId: traceId)
                return Reply(steps: script.steps)
            }
            let peak = Int(simulation.peakMgDl.rounded())
            let at = clock(simulation.peakAt)
            let half = simulation.alternatives.first.map { Int($0.peakMgDl.rounded()) } ?? peak
            switch simulation.verdict {
            case .go:
                script.say("Go for it! With the \(item.name) you'd likely peak near \(peak) around \(at), under your \(Int(high)) line.")
            case .goWithTweak:
                script.say("You can, with a tweak. The \(item.name) likely takes you near \(peak) around \(at). Half a portion keeps you near \(half), or a 10-minute walk after likely trims about \(Int(walkDrop)) (literature).")
            default:
                script.say("I'd wait on that one. The \(item.name) likely peaks near \(peak) around \(at), over your \(Int(high)) line. A 10-minute walk first could help (literature).")
            }
            let mood: Mood = simulation.verdict == .go ? .calm : simulation.verdict == .goWithTweak ? .rising : .high
            script.end(mood: mood, conversationId: conversationId, traceId: traceId)
            return Reply(steps: script.steps)

        case .logMeal:
            let seed = food(in: message) ?? seeds[1]
            let item = seed.item(quantity: quantity(in: message))
            let meal = Meal(mealId: "m_chat_\(turn)", eatenAt: state.replayNow ?? .now, source: .chat, items: [item],
                            totals: MealTotals(items: [item]), isStandardBreakfast: false, predictionId: nil)
            let likelySimulation = acting == nil ? nil : simulate([item], state: state, turn: turn)
            let likely = likelySimulation?.peakMgDl
            let saved = SavedMeal(meal, simulated: acting != nil, likelyPeakMgDl: likely, peakAt: likelySimulation?.peakAt)
            script.tool("log_meal", card: .mealSaved(saved))
            if let acting, let likely {
                script.say("Got it, I added \(amount(item)) to the food log. I think it likely peaks near \(Int(likely.rounded())). It's simulated on \(acting)'s day, so I won't grade it.")
            } else {
                script.say("Saved \(amount(item)) to your food log. No glucose data is connected for you, so there's no prediction.")
            }
            script.end(mood: .calm, conversationId: conversationId, traceId: traceId)
            return Reply(steps: script.steps, savedMeal: saved, likelyPeak: likely)

        case .walk:
            guard let peak = state.forecast.max(by: { $0.glucoseMgDl < $1.glucoseMgDl }) else {
                script.tool("suggest_walk", card: nil)
                script.say("A walk is always nice, but I'm not following anyone yet, so I can't model it.")
                script.end(mood: .calm, conversationId: conversationId, traceId: traceId)
                return Reply(steps: script.steps)
            }
            let suggestion = WalkSuggestion(minutes: 10, start: state.replayNow, forecastPeakMgDl: peak.glucoseMgDl,
                                            forecastPeakDropMgDl: walkDrop, effectSource: .literature)
            script.tool("suggest_walk", card: .walkSuggestion(suggestion))
            let value = Int(peak.glucoseMgDl.rounded())
            if peak.glucoseMgDl >= high {
                script.say("Yes! Your forecast likely peaks near \(value) around \(clock(peak.t)). A 10-minute walk now could trim about \(Int(walkDrop)) mg/dL (literature).")
            } else {
                script.say("Your forecast likely peaks near \(value), under your line. A walk is still a nice idea: 10 minutes could trim about \(Int(walkDrop)) mg/dL (literature).")
            }
            script.end(mood: .rising, conversationId: conversationId, traceId: traceId)
            return Reply(steps: script.steps)

        case .today:
            script.tool("today_summary", card: nil)
            script.tool("get_state", card: state.gummiView.map(ChatCard.gummiView))
            let today = state.today
            var text = "So far today: \(Int(today.timeInRangePct.rounded()))% in range, Dexcom peak \(Int(today.peakMgDl.rounded())), \(today.meals) meal\(today.meals == 1 ? "" : "s") logged."
            if let gummi = today.gummiMaeMgDl {
                text += " On graded meals I was off by \(Int(gummi.rounded())) on average, CGM-only by \(today.cgmOnlyMaeMgDl.map { "\(Int($0.rounded()))" } ?? "n/a"), last value by \(today.lastValueMaeMgDl.map { "\(Int($0.rounded()))" } ?? "n/a")."
            } else {
                text += " No graded meals yet."
            }
            if let view = state.gummiView { text += " My estimate for now is likely around \(Int(view.glucoseMgDl.rounded()))." }
            script.say(text)
            script.end(mood: .calm, conversationId: conversationId, traceId: traceId)
            return Reply(steps: script.steps)

        case .spike:
            script.tool("explain_spike", card: nil)
            script.selfCheck()
            if let latestGrade {
                script.say("Your biggest recent rise came after a meal. \(latestGrade.message) Carbs drive most of it; a short walk after eating usually softens the peak (literature).")
            } else {
                script.say("No spike to explain yet. Once a meal's two-hour window closes, I can tell you what drove it.")
            }
            script.end(mood: .calm, conversationId: conversationId, traceId: traceId)
            return Reply(steps: script.steps)

        case .grade:
            script.tool("get_history", card: latestGrade.map(ChatCard.grade))
            if let latestGrade {
                script.say(latestGrade.message)
            } else {
                script.say("Nothing graded yet. I grade each meal two hours after it's eaten, next to CGM-only and last value.")
            }
            script.end(mood: .calm, conversationId: conversationId, traceId: traceId)
            return Reply(steps: script.steps)

        case .help:
            script.say("I can log food, check a food before you eat it, suggest a walk, or explain a spike. What would you like?")
            script.end(mood: .calm, conversationId: conversationId, traceId: traceId)
            return Reply(steps: script.steps)

        case .state:
            script.tool("get_state", card: state.gummiView.map(ChatCard.gummiView))
            if let view = state.gummiView {
                script.say("My estimate for now is likely around \(Int(view.glucoseMgDl.rounded())), \(view.trend.rawValue.replacingOccurrences(of: "_", with: " ")). Ask me about a food, a walk, or how today is going.")
            } else {
                script.say("I'm not following anyone yet. Pick a participant from the header and I'll coach their day.")
            }
            script.end(mood: .calm, conversationId: conversationId, traceId: traceId)
            return Reply(steps: script.steps)
        }
    }

    /// The forecast with and without the food: a carb bump that peaks 45 minutes after eating.
    static func simulate(_ items: [MealItem], state: GummiState, turn: Int) -> Simulation? {
        guard let now = state.estimate.last, !state.forecast.isEmpty else { return nil }
        let start = BandPoint(t: now.t, glucoseMgDl: now.glucoseMgDl, bandLowMgDl: now.bandLowMgDl,
                              bandHighMgDl: now.bandHighMgDl, kind: .forecast)
        let baseline = [start] + state.forecast
        let carbs = items.map(\.carbsG).reduce(0, +)
        func bump(_ point: BandPoint, scale: Double) -> Double {
            let minutes = point.t.timeIntervalSince(now.t) / 60
            return carbs * 1.4 * scale * (minutes / 45) * exp(1 - minutes / 45)
        }
        func curve(scale: Double) -> [BandPoint] {
            baseline.map { point in
                let added = bump(point, scale: scale)
                return BandPoint(t: point.t, glucoseMgDl: (point.glucoseMgDl + added).rounded(toPlaces: 1),
                                 bandLowMgDl: (point.bandLowMgDl + added - 3).rounded(toPlaces: 1),
                                 bandHighMgDl: (point.bandHighMgDl + added + 3).rounded(toPlaces: 1), kind: .forecast)
            }
        }
        let withFood = curve(scale: 1)
        guard let peak = withFood.max(by: { $0.glucoseMgDl < $1.glucoseMgDl }) else { return nil }
        let halfPeak = curve(scale: 0.5).map(\.glucoseMgDl).max() ?? peak.glucoseMgDl
        let walkPeak = peak.glucoseMgDl - min(walkDrop, carbs * 0.5)
        let high = state.profile.highLineMgDl
        let verdict: Verdict = peak.glucoseMgDl < high ? .go : min(halfPeak, walkPeak) < high ? .goWithTweak : .wait
        let name = items.first?.name ?? "that"
        // Like the backend (1.6): past about 140 g of carbs the model is out of its depth, so no peak is quoted.
        let reliable = carbs <= 140
        return Simulation(items: items, eatAt: now.t, baselineCurve: baseline, withFoodCurve: withFood,
                          peakMgDl: peak.glucoseMgDl, peakAt: peak.t, verdict: verdict,
                          summary: "With the \(name) you'd likely peak near \(Int(peak.glucoseMgDl.rounded())).",
                          alternatives: [Alternative(label: "Half portion", peakMgDl: halfPeak.rounded(toPlaces: 1)),
                                         Alternative(label: "Walk 10 minutes after", peakMgDl: walkPeak.rounded(toPlaces: 1),
                                                     effectSource: .literature)],
                          method: .model, predictionId: "pr_sim_\(turn)",
                          reliable: reliable ? nil : false, requestedCarbsG: reliable ? nil : carbs.rounded())
    }

    private static func clock(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: Theme.timeZone))
    }

    /// "a cookie", "half a bagel", "2 cookies".
    private static func amount(_ item: MealItem) -> String {
        switch item.quantity {
        case 1: "aeiou".contains(item.name.prefix(1)) ? "an \(item.name)" : "a \(item.name)"
        case 0.5: "half a \(item.name)"
        default: "\(item.quantity.formatted()) \(item.name)s"
        }
    }

    /// Builds the event list with the backend's pacing: tools first, then the checked reply in 24-character tokens.
    private struct Script {
        var steps: [Step] = [Step(delay: .zero, event: .mood(.thinking))]

        mutating func tool(_ name: String, card: ChatCard?) {
            // 1.6: tool events carry the chip label.
            let label = ToolChip(id: 0, name: name).label
            steps.append(Step(delay: .milliseconds(250), event: .tool(name: name, status: .start, label: label)))
            steps.append(Step(delay: .milliseconds(650), event: .tool(name: name, status: .end, label: label)))
            if let card { self.card(card) }
        }

        /// The backend's self-check rewrite chip (1.6).
        mutating func selfCheck() {
            steps.append(Step(delay: .milliseconds(200), event: .tool(name: "self_check", status: .start, label: "Double-checking myself…")))
            steps.append(Step(delay: .milliseconds(500), event: .tool(name: "self_check", status: .end, label: "Checked ✓")))
        }

        mutating func card(_ card: ChatCard) {
            steps.append(Step(delay: .milliseconds(40), event: .card(card)))
        }

        mutating func say(_ text: String) {
            var rest = Substring(text)
            var first = true
            while !rest.isEmpty {
                steps.append(Step(delay: .milliseconds(first ? 450 : 25), event: .token(String(rest.prefix(24)))))
                rest = rest.dropFirst(24)
                first = false
            }
        }

        mutating func end(mood: Mood, conversationId: String, traceId: String?) {
            steps.append(Step(delay: .milliseconds(40), event: .mood(mood)))
            steps.append(Step(delay: .milliseconds(20), event: .done(conversationId: conversationId, traceId: traceId)))
        }
    }
}
