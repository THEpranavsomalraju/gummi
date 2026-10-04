import SwiftUI

/// A small capsule when live updates aren't flowing: reconnecting, offline, or the server asleep.
/// The cached State stays on screen; tap to try again. Shows only after a second, so a quick reconnect never flashes.
struct ConnectionCapsule: View {
    @Environment(AppModel.self) private var model
    @State private var visible = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let notice = model.connectionNotice(now: context.date)
            Group {
                if let notice, visible {
                    HStack(spacing: 8) {
                        Button {
                            model.reconnect()
                        } label: {
                            HStack(spacing: 6) {
                                switch notice.kind {
                                case .reconnecting: ProgressView().controlSize(.mini)
                                case .offline: Image(systemName: "wifi.slash")
                                case .asleep: Image(systemName: "moon.zzz.fill")
                                }
                                Text(notice.text)
                            }
                        }
                        .accessibilityHint("Tries to reconnect")
                        if notice.kind == .asleep, model.mode == .live {
                            Button("Use demo data") { model.setMode(.mock) }
                                .fontWeight(.bold)
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .buttonStyle(.plain)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .glassSurface(in: Capsule())
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: notice)
            .task(id: notice?.kind) {
                guard notice != nil else { visible = false; return }
                try? await Task.sleep(for: .seconds(1))
                if !Task.isCancelled { withAnimation(.snappy) { visible = true } }
            }
        }
    }
}
