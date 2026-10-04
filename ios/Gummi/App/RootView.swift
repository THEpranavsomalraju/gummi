import SwiftUI

/// Tabs: Home, Today, Settings (PROJECT_OVERVIEW section 4), plus in-app banners, the Follow picker, and chat.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            Tab("Home", systemImage: "house", value: AppTab.home) { HomeView() }
            Tab("Today", systemImage: "list.bullet.rectangle", value: AppTab.today) { TodayView() }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) { SettingsView() }
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
        .sheet(item: $model.chatRequest) { request in ChatSheet(request: request) }
        .fullScreenCover(item: $model.walkRequest) { request in WalkView(request: request, service: model.activeService) }
    }
}

/// A glass banner for a new card or alert. Tap to open it in Today, swipe up to dismiss; it leaves on its own after 4 s.
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
        .accessibilityHint("Opens it in Today")
    }
}
