import Foundation
import UserNotifications

/// One local notification to schedule ahead of time.
nonisolated struct PlannedNotification: Equatable, Sendable {
    let id: String
    let fireAt: Date
    let title: String
    let body: String
}

/// iOS suspends Gummi in the background (no SSE, no server push on a free team), so the phone schedules
/// what it can predict before it goes: due meals (State.upcoming_due, already wall time), meal stories when a
/// pending meal prediction's window is covered by delayed data, the 20:00 recap, and a best-guess walk nudge.
/// Replay times become wall times through StreamStatus.replay_anchor and speed.
nonisolated enum NotificationPlanner {
    static let horizon: TimeInterval = 6 * 3600
    static let limit = 30

    static func plan(state: GummiState, displayName: String?, now: Date) -> [PlannedNotification] {
        let stream = state.stream
        guard state.actingAs != nil, stream.running, !stream.paused, let replayNow = state.replayNow else { return [] }
        let who = displayName ?? "your participant"
        var plan: [PlannedNotification] = []

        for due in state.upcomingDue {
            plan.append(PlannedNotification(id: "due_\(due.dueId)", fireAt: due.dueAt, title: due.title, body: "\(due.body). Tap to log it."))
        }

        // A meal is graded once delayed readings cover its 2-hour window.
        for prediction in state.pendingPredictions where prediction.kind == .meal {
            let ready = prediction.windowEnd.addingTimeInterval(Double(stream.delayMinutes) * 60)
            if let fire = stream.wallTime(forReplay: ready) {
                plan.append(PlannedNotification(id: "story_\(prediction.predictionId)", fireAt: fire,
                                                title: "\(prediction.about): two hours later",
                                                body: "Your meal story and my grade are likely ready."))
            }
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Theme.timeZone
        if let recap = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: replayNow), recap > replayNow,
           let fire = stream.wallTime(forReplay: recap) {
            let day = calendar.component(.day, from: recap)
            plan.append(PlannedNotification(id: "recap_\(day)", fireAt: fire, title: "Evening recap",
                                            body: "\(who)'s day in review is likely ready, with one lesson for tomorrow."))
        }

        if let crossing = state.forecast.first(where: { $0.glucoseMgDl >= state.profile.highLineMgDl }),
           let fire = stream.wallTime(forReplay: crossing.t.addingTimeInterval(-30 * 60)) {
            plan.append(PlannedNotification(id: "walk_\(Int(crossing.t.timeIntervalSince1970 / 300))", fireAt: fire,
                                            title: "A walk would likely help soon",
                                            body: "The forecast likely crosses \(Int(state.profile.highLineMgDl)). A 10-minute walk may soften the peak."))
        }

        return Array(plan.filter { $0.fireAt > now && $0.fireAt <= now.addingTimeInterval(horizon) }
            .sorted { $0.fireAt < $1.fireAt }
            .prefix(limit))
    }
}

/// Schedules the plan with UNUserNotificationCenter when the app goes to the background and clears it on return,
/// when in-app banners take over.
nonisolated enum LocalNotifier {
    static let askedKey = "gummi.askedNotifications"

    /// Asked once, in the foreground, the first time the app is following someone: iOS can't show the prompt
    /// from the background.
    static func requestPermissionIfNeeded(defaults: UserDefaults = .standard) async {
        // `-gummi.noPrompts YES` keeps screenshots clean.
        guard !defaults.bool(forKey: askedKey), !defaults.bool(forKey: "gummi.noPrompts") else { return }
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        defaults.set(true, forKey: askedKey)
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    static func schedule(_ plan: [PlannedNotification]) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard !plan.isEmpty else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        for item in plan {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, item.fireAt.timeIntervalSinceNow), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
        }
    }

    static func clear() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }
}

/// Opens Today when a notification is tapped.
final class NotificationTaps: NSObject, UNUserNotificationCenterDelegate {
    var onTap: () -> Void = {}

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run { onTap() }
    }

    /// In the foreground, in-app banners cover it.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        []
    }
}
