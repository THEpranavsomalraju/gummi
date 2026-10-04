import Charts
import SwiftUI

/// The day at a glance (GET /day): time in range, the hourly band, tiles for meals, activity and Gummi's
/// predictions, the best call and biggest spike, highlights in Gummi's voice, and the evening recap.
struct DayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DaySwitcher(selected: model.dayDate, loaded: model.day?.date) { date in
                        model.dayDate = date
                        Task { await model.loadDay() }
                    }
                    if let day = model.day {
                        content(day)
                    } else {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Loading your day").foregroundStyle(Theme.secondaryText)
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                    }
                    SafetyLine()
                }
                .padding()
            }
            .refreshable { await model.loadDay() }
            .navigationTitle("Day")
            .background(Theme.background)
            .task { await model.loadDay() }
        }
    }

    @ViewBuilder
    private func content(_ day: DaySummary) -> some View {
        if day.dataStatus == .stale {
            Label("No new readings in over 3 hours, so Gummi isn't estimating. Resume the replay to continue.",
                  systemImage: "exclamationmark.triangle")
                .font(.footnote.weight(.semibold))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        if day.dataStatus == DataStatus.none {
            ContentUnavailableView {
                Label("Nobody followed yet", systemImage: "person.crop.circle.badge.plus")
            } description: {
                Text("Follow a study participant to see their day.")
            } actions: {
                Button("Follow someone") { model.showsFollowPicker = true }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
            }
        } else {
            if let glucose = day.glucose {
                DayHero(glucose: glucose)
                if !day.hourly.isEmpty { HourlyStrip(hours: day.hourly, peak: glucose.peak) }
            } else {
                tile { Text("No readings yet today").font(.headline).frame(maxWidth: .infinity, minHeight: 80) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 1 : 2),
                      spacing: 12) {
                mealsTile(day.meals)
                activityTile(day.activity)
                predictionsTile(day.predictions)
                sourceTile
            }
            if let best = day.bestCall { bestCall(best) }
            if let spike = day.biggestSpike { biggestSpike(spike) }
            if !day.highlights.isEmpty { highlights(day.highlights) }
            if let recap = day.recap {
                StoryCardView(card: recap, style: .full)
            } else {
                tile {
                    Label("Gummi's recap lands at 8 PM", systemImage: "moon.stars")
                        .font(.subheadline).foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: Tiles

    private func mealsTile(_ meals: DayMeals) -> some View {
        tile(title: "Meals", symbol: "fork.knife") {
            Text("\(meals.count)").font(.system(.title, design: .rounded).bold().monospacedDigit())
            Text("\(Int(meals.carbsG.rounded())) g carbs").font(.subheadline.monospacedDigit())
            if let biggest = meals.biggest {
                Text("Biggest: \(biggest.food), \(Int(biggest.carbsG.rounded())) g")
                    .font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(3)
            }
        }
    }

    private func activityTile(_ activity: DayActivity) -> some View {
        tile(title: "Activity", symbol: "figure.walk") {
            Text(activity.steps.formatted()).font(.system(.title, design: .rounded).bold().monospacedDigit())
            Text("steps").font(.subheadline)
            Text("\(activity.walks) walk\(activity.walks == 1 ? "" : "s") · \(activity.walkMinutes) min")
                .font(.caption.monospacedDigit()).foregroundStyle(Theme.secondaryText)
        }
    }

    private func predictionsTile(_ predictions: DayPredictions) -> some View {
        tile(title: "My predictions", symbol: "checkmark.seal") {
            if predictions.graded == 0 {
                Text("First grades land 3 hours after a meal").font(.subheadline).foregroundStyle(Theme.secondaryText)
            } else {
                Text("\(predictions.graded) graded").font(.subheadline.weight(.semibold))
                ErrorBars(me: predictions.gummiMaeMgDl, cgmOnly: predictions.cgmOnlyMaeMgDl, lastValue: predictions.lastValueMaeMgDl)
                if let pct = predictions.beatCgmOnlyPct {
                    Text("Beat CGM-only \(Int(pct.rounded()))%").font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private var sourceTile: some View {
        tile(title: "Data", symbol: "sensor.tag.radiowaves.forward") {
            if model.mode == .mock {
                Text("Demo data").font(.subheadline.weight(.semibold))
                Text("Replaying the BIG IDEAs study on the phone").font(.caption).foregroundStyle(Theme.secondaryText)
            } else {
                Text("BIG IDEAs replay").font(.subheadline.weight(.semibold))
                let dexcom = model.state?.dexcom
                Text(dexcom?.connected == true ? "Dexcom sandbox connected (status only)" : "Dexcom not connected")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
            }
        }
    }

    // MARK: Cards

    private func bestCall(_ best: DayBestCall) -> some View {
        tile(title: "Best call of the day", symbol: "star.fill") {
            Text(best.message).font(.subheadline)
            Text("Off by \(Int(best.gummiPeakErrorMgDl.rounded())) mg/dL at the peak" + (best.about.map { " · \($0)" } ?? ""))
                .font(.caption.monospacedDigit()).foregroundStyle(Theme.secondaryText)
        }
    }

    private func biggestSpike(_ spike: DaySpike) -> some View {
        tile(title: "Biggest spike", symbol: "chart.line.uptrend.xyaxis") {
            Text("\(Int(spike.peakMgDl.rounded())) mg/dL at \(FoodLogText.time(spike.at))")
                .font(.headline.monospacedDigit())
            if let meal = spike.afterMeal {
                Text("After \(meal.lowercased())").font(.subheadline).foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private func highlights(_ lines: [String]) -> some View {
        tile(title: "Gummi's highlights", symbol: "sparkles") {
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle().fill(Theme.accent).frame(width: 6, height: 6)
                    Text(line).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func tile<Content: View>(title: String? = nil, symbol: String? = nil,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Label(title, systemImage: symbol ?? "circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .textCase(.uppercase)
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// A time-in-range ring with the average, peak, and low beside it.
private struct DayHero: View {
    let glucose: DayGlucose
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                                                  : AnyLayout(HStackLayout(spacing: 20))
        layout {
            ZStack {
                Circle().stroke(Theme.accent.opacity(0.15), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: glucose.timeInRangePct / 100)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(Int(glucose.timeInRangePct.rounded()))%")
                        .font(.system(.title, design: .rounded).bold().monospacedDigit())
                    Text("in range").font(.caption).foregroundStyle(Theme.secondaryText)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .padding(18)
            }
            .frame(width: 130, height: 130)
            VStack(alignment: .leading, spacing: 10) {
                stat("Average", "\(Int(glucose.averageMgDl.rounded())) mg/dL")
                stat("Peak", "\(Int(glucose.peak.mgDl.rounded())) at \(FoodLogText.time(glucose.peak.at))")
                stat("Low", "\(Int(glucose.low.mgDl.rounded())) at \(FoodLogText.time(glucose.low.at))")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Int(glucose.timeInRangePct.rounded())) percent in range. Average \(Int(glucose.averageMgDl.rounded())). Peak \(Int(glucose.peak.mgDl.rounded())). Low \(Int(glucose.low.mgDl.rounded())).")
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption).foregroundStyle(Theme.secondaryText)
            Text(value).font(.headline.monospacedDigit())
        }
    }
}

/// Each hour's min-to-max band with its average, the 70 and 140 lines, and the peak.
struct HourlyStrip: View {
    let hours: [DayHour]
    let peak: DayMoment

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("By the hour", systemImage: "clock")
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent).textCase(.uppercase)
            Chart {
                ForEach(hours) { hour in
                    AreaMark(x: .value("Hour", hour.hour), yStart: .value("Min", hour.minMgDl), yEnd: .value("Max", hour.maxMgDl))
                        .foregroundStyle(Theme.band)
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("Hour", hour.hour), y: .value("Average", hour.avgMgDl))
                        .foregroundStyle(Theme.confirmedLine)
                        .interpolationMethod(.catmullRom)
                }
                RuleMark(y: .value("High", 140)).foregroundStyle(Theme.rangeLine).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                RuleMark(y: .value("Low", 70)).foregroundStyle(Theme.rangeLine).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                if let top = hours.max(by: { $0.maxMgDl < $1.maxMgDl }) {
                    PointMark(x: .value("Hour", top.hour), y: .value("Peak", top.maxMgDl))
                        .foregroundStyle(Theme.accent)
                        .annotation(position: .top) {
                            Text("\(Int(peak.mgDl.rounded()))").font(.caption2.bold().monospacedDigit())
                        }
                }
            }
            .chartXScale(domain: 0...23)
            .chartYScale(domain: Self.yDomain(hours))
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                    AxisGridLine()
                    AxisValueLabel { Text(Self.hourLabel(value.as(Int.self) ?? 0)) }
                }
            }
            .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
            .frame(height: 150)
            .accessibilityHidden(true)
        }
        .padding(14)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// The day's range plus the 70 and 140 lines, with a little room.
    nonisolated static func yDomain(_ hours: [DayHour]) -> ClosedRange<Double> {
        let low = min(hours.map(\.minMgDl).min() ?? 70, 70) - 10
        let high = max(hours.map(\.maxMgDl).max() ?? 140, 140) + 15
        return low...high
    }

    static func hourLabel(_ hour: Int) -> String {
        switch hour {
        case 0: "12 AM"
        case 12: "12 PM"
        case 23: "11 PM"
        default: hour < 12 ? "\(hour) AM" : "\(hour - 12) PM"
        }
    }
}

/// Me, CGM-only, and last value as three small bars (shorter is better).
private struct ErrorBars: View {
    let me: Double?
    let cgmOnly: Double?
    let lastValue: Double?

    var body: some View {
        let values = [("Me", me), ("CGM-only", cgmOnly), ("Last value", lastValue)]
        let top = values.compactMap(\.1).max() ?? 1
        VStack(alignment: .leading, spacing: 4) {
            ForEach(values, id: \.0) { label, value in
                HStack(spacing: 6) {
                    Text(label).font(.caption2).frame(width: 58, alignment: .leading)
                    GeometryReader { geometry in
                        Capsule()
                            .fill(label == "Me" ? Theme.accent : Theme.secondaryText.opacity(0.5))
                            .frame(width: max(4, geometry.size.width * (value ?? 0) / top))
                    }
                    .frame(height: 8)
                    Text(value.map { "\(Int($0.rounded()))" } ?? "n/a").font(.caption2.monospacedDigit()).frame(width: 26, alignment: .trailing)
                }
            }
            Text("Average error, mg/dL").font(.caption2).foregroundStyle(Theme.secondaryText)
        }
    }
}
