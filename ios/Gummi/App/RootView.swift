import SwiftUI

/// Tabs: Home, Food, Activity, Day (Pranav's layout, 2026-10-04), plus in-app banners, the Follow picker, chat,
/// walks, and Settings (a sheet from Home's gear).
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            Tab("Home", systemImage: "house", value: AppTab.home) { HomeView() }
            Tab("Food", systemImage: "fork.knife", value: AppTab.food) { FoodLogView() }
            Tab("Activity", systemImage: "bell", value: AppTab.activity) { ActivityView() }
                .badge(model.activityUnseen)
            Tab("Day", systemImage: "chart.bar.doc.horizontal", value: AppTab.day) { DayView() }
        }
        .overlay(alignment: .top) {
            if let banner = model.banner {
                BannerView(banner: banner, onTap: model.openBanner, onDismiss: model.dismissBanner)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .id(banner.id)
            }
        }
        .animation(.snappy, value: model.banner)
        .sheet(isPresented: $model.showsFollowPicker) { FollowPickerView() }
        .sheet(isPresented: $model.showsSettings) { SettingsView() }
        .sheet(item: $model.chatRequest) { request in ChatSheet(request: request) }
        .fullScreenCover(item: $model.walkRequest) { request in WalkView(request: request, service: model.activeService) }
    }
}

/// A glass banner for a new card or alert. Tap to open it in Activity, swipe up to dismiss; it leaves on its own after 4 s.
struct BannerView: View {
    let banner: Banner
    let onTap: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: banner.symbol)
                .font(.title3)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(banner.title).font(.subheadline.bold())
                Text(banner.message)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .gesture(DragGesture(minimumDistance: 10).onEnded { value in
            if value.translation.height < -20 { onDismiss() }
        })
        .sensoryFeedback(.impact(weight: .light), trigger: banner.id)
        .task(id: banner.id) {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { onDismiss() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens it in Activity")
    }
}
