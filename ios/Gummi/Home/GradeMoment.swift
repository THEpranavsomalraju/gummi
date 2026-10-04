import Charts
import SwiftUI

/// A grade that just landed, shown over Home's chart.
nonisolated struct GradeMoment: Identifiable, Equatable, Sendable {
    let id = UUID()
    let grade: Grade
    /// Gummi's predicted curve for the window, when the phone saw the prediction while it was pending.
    let prediction: Prediction?
}

/// Gummi's prediction (dotted) with what really happened drawing in solid from left to right.
struct RevealingCurves: View {
    let predicted: [(Date, Double)]
    let actual: [(Date, Double)]
    var height: CGFloat = 90
    var duration: Double = 1.2
    @State private var progress: CGFloat = 0

    var body: some View {
        let domain = yDomain
        let xDomain = xRange
        ZStack {
            chart(predicted, dash: [1, 4], color: Theme.secondaryText, domain: domain, xDomain: xDomain)
            chart(actual, dash: [], color: Theme.confirmedLine, domain: domain, xDomain: xDomain)
                .mask(alignment: .leading) {
                    GeometryReader { geometry in
                        Rectangle().frame(width: geometry.size.width * progress)
                    }
                }
        }
        .frame(height: height)
        .onAppear {
            progress = 0
            withAnimation(.easeInOut(duration: duration).delay(0.3)) { progress = 1 }
        }
        .accessibilityHidden(true)
    }

    private func chart(_ points: [(Date, Double)], dash: [CGFloat], color: Color,
                       domain: ClosedRange<Double>, xDomain: ClosedRange<Date>) -> some View {
        Chart(Array(points.enumerated()), id: \.offset) { _, point in
            LineMark(x: .value("Time", point.0), y: .value("mg/dL", point.1))
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: dash.isEmpty ? 2.5 : 2, lineCap: .round, dash: dash))
                .foregroundStyle(color)
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: domain)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }

    private var yDomain: ClosedRange<Double> {
        let values = (predicted + actual).map(\.1)
        let low = (values.min() ?? 80) - 8, high = (values.max() ?? 160) + 8
        return low...max(high, low + 20)
    }

    private var xRange: ClosedRange<Date> {
        let dates = (predicted + actual).map(\.0)
        let start = dates.min() ?? .now
        return start...max(dates.max() ?? start, start.addingTimeInterval(60))
    }
}

/// The grade moment over Home's chart: the curve draws in, then the three-number badge pops.
struct GradeMomentView: View {
    @Environment(AppModel.self) private var model
    let moment: GradeMoment
    @State private var showsBadge = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(moment.prediction?.about ?? "Prediction graded", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "xmark").font(.caption.bold()).foregroundStyle(Theme.secondaryText)
            }
            if let prediction = moment.prediction {
                RevealingCurves(predicted: prediction.predictedCurve.map { ($0.t, $0.glucoseMgDl) },
                                actual: actual(in: prediction), height: 70)
            }
            if showsBadge {
                GradeBadge(grade: moment.grade, compact: true)
                    .transition(.scale(scale: 0.8, anchor: .leading).combined(with: .opacity))
            }
        }
        .padding(12)
        .glassSurface(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { model.dismissGradeMoment() }
        .task(id: moment.id) {
            showsBadge = false
            try? await Task.sleep(for: .seconds(moment.prediction == nil ? 0.1 : 1.5))
            withAnimation(.bouncy) { showsBadge = true }
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { model.dismissGradeMoment(moment.id) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Prediction graded. \(moment.grade.threeNumberBadge)")
    }

    /// Real readings in the graded window, from the latest State.
    private func actual(in prediction: Prediction) -> [(Date, Double)] {
        (model.state?.confirmed ?? [])
            .filter { $0.t >= prediction.windowStart && $0.t <= prediction.windowEnd }
            .map { ($0.t, $0.glucoseMgDl) }
    }
}
