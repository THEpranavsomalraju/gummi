import Charts
import SwiftUI

/// Home's compact chart: confirmed Dexcom readings (solid), Gummi's estimate of the delay gap (dotted, with a band),
/// and the 2-hour forecast (dashed, with a band), with the high and low lines. Line style, not color alone,
/// tells the three apart.
struct GlucoseChart: View {
    let state: GummiState

    private var now: Date? { state.replayNow ?? state.estimate.last?.t }
    private var high: Double { state.profile.highLineMgDl }
    private var low: Double { state.profile.lowLineMgDl }

    var body: some View {
        VStack(spacing: 6) {
            if state.confirmed.isEmpty && state.estimate.isEmpty {
                ContentUnavailableView("Waiting for readings", systemImage: "waveform.path.ecg",
                                       description: Text("The chart fills in as the replay streams."))
            } else {
                chart
                legend
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    private var chart: some View {
        Chart {
            ForEach(state.estimate, id: \.t) { point in
                AreaMark(x: .value("Time", point.t), yStart: .value("Low", point.bandLowMgDl),
                         yEnd: .value("High", point.bandHighMgDl), series: .value("Band", "estimate"))
                    .foregroundStyle(Theme.band)
            }
            ForEach(state.forecast, id: \.t) { point in
                AreaMark(x: .value("Time", point.t), yStart: .value("Low", point.bandLowMgDl),
                         yEnd: .value("High", point.bandHighMgDl), series: .value("Band", "forecast"))
                    .foregroundStyle(Theme.band.opacity(0.7))
            }
            ForEach(state.confirmed, id: \.t) { point in
                LineMark(x: .value("Time", point.t), y: .value("mg/dL", point.glucoseMgDl), series: .value("Series", "Dexcom"))
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .foregroundStyle(Theme.confirmedLine)
            }
            ForEach(state.estimate, id: \.t) { point in
                LineMark(x: .value("Time", point.t), y: .value("mg/dL", point.glucoseMgDl), series: .value("Series", "Estimate"))
                    .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, dash: [0.5, 4]))
                    .foregroundStyle(Theme.estimateLine)
            }
            ForEach(state.forecast, id: \.t) { point in
                LineMark(x: .value("Time", point.t), y: .value("mg/dL", point.glucoseMgDl), series: .value("Series", "Forecast"))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [7, 5]))
                    .foregroundStyle(Theme.estimateLine)
            }
            RuleMark(y: .value("High", high))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(Theme.rangeLine)
                .annotation(position: .top, alignment: .leading) {
                    Text("\(Int(high))").font(.caption2).foregroundStyle(Theme.secondaryText)
                }
            RuleMark(y: .value("Low", low))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(Theme.rangeLine)
                .annotation(position: .bottom, alignment: .leading) {
                    Text("\(Int(low))").font(.caption2).foregroundStyle(Theme.secondaryText)
                }
            if let now, let estimate = state.gummiView {
                RuleMark(x: .value("Now", now))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Theme.secondaryText.opacity(0.5))
                PointMark(x: .value("Now", now), y: .value("mg/dL", estimate.glucoseMgDl))
                    .symbolSize(40)
                    .foregroundStyle(Theme.estimateLine)
                    .annotation(position: .top, spacing: 4) {
                        Text("Gummi's estimate \(Int(estimate.glucoseMgDl.rounded()))")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.cardSurface, in: Capsule())
                    }
            }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 2)) {
                AxisGridLine().foregroundStyle(Theme.rangeLine.opacity(0.3))
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) {
                AxisGridLine().foregroundStyle(Theme.rangeLine.opacity(0.3))
                AxisValueLabel()
            }
        }
        .environment(\.timeZone, Theme.timeZone)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            LegendItem(title: "Dexcom", dash: [])
            LegendItem(title: "Gummi's estimate", dash: [0.5, 4])
            LegendItem(title: "Forecast", dash: [7, 5])
        }
        .font(.caption2)
        .foregroundStyle(Theme.secondaryText)
    }

    private var yDomain: ClosedRange<Double> {
        let values = state.confirmed.map(\.glucoseMgDl) + state.estimate.map(\.bandHighMgDl) + state.forecast.map(\.bandHighMgDl)
            + state.estimate.map(\.bandLowMgDl) + state.forecast.map(\.bandLowMgDl)
        let lowest = min(values.min() ?? low, low) - 10
        let highest = max(values.max() ?? high, high) + 10
        return lowest...highest
    }

    private var summary: String {
        var parts: [String] = []
        if let last = state.confirmed.last { parts.append("Dexcom \(Int(last.glucoseMgDl.rounded()))") }
        if let view = state.gummiView { parts.append("Gummi's estimate \(Int(view.glucoseMgDl.rounded())), \(view.trend.rawValue.replacingOccurrences(of: "_", with: " "))") }
        if let peak = state.forecast.max(by: { $0.glucoseMgDl < $1.glucoseMgDl }) {
            parts.append("forecast peak \(Int(peak.glucoseMgDl.rounded())) at \(peak.t.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: Theme.timeZone)))")
        }
        return parts.isEmpty ? "No readings yet" : parts.joined(separator: ", ")
    }
}

/// A legend swatch drawn with the series' line style.
struct LegendItem: View {
    let title: String
    let dash: [CGFloat]
    var color = Theme.confirmedLine

    var body: some View {
        HStack(spacing: 5) {
            Canvas { context, size in
                var path = Path()
                path.move(to: CGPoint(x: 0, y: size.height / 2))
                path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: dash))
            }
            .frame(width: 22, height: 6)
            Text(title)
        }
    }
}
