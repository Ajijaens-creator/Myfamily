import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
            FamilyView()
                .tabItem { Label("Family", systemImage: "person.3.fill") }
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .tint(app.theme.primary)
    }
}

/// Parents see each child's day. A child sees their own My Day.
struct HomeView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        NavigationStack {
            Group {
                if let me = app.me, me.role.isParent {
                    ParentHome()
                } else if let me = app.me {
                    MyDayView(member: me, canEdit: false, greeting: true)
                }
            }
        }
    }
}

struct ParentHome: View {
    @EnvironmentObject var app: AppState
    @State private var progress: [UUID: (done: Int, total: Int)] = [:]

    var body: some View {
        let theme = app.theme
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Hi \(app.me?.displayName ?? "")! \(theme.greetingEmoji)")
                    .font(theme.titleFont).foregroundStyle(theme.textPrimary)
                Text("Today in \(app.family?.name ?? "the family")")
                    .foregroundStyle(theme.textSecondary)
                if app.children.isEmpty {
                    EmptyState(emoji: "👶", text: "Add your children in Family.", theme: theme)
                }
                ForEach(app.children) { child in
                    NavigationLink {
                        MyDayView(member: child, canEdit: true, greeting: false)
                    } label: {
                        Card(theme: theme) {
                            HStack(spacing: 14) {
                                Avatar(member: child)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(child.displayName).font(.headline).foregroundStyle(theme.textPrimary)
                                    if let p = progress[child.id] {
                                        Text(p.total == 0 ? "No activities today" : "\(p.done) of \(p.total) done")
                                            .font(.subheadline).foregroundStyle(theme.textSecondary)
                                        if p.total > 0 {
                                            ProgressView(value: Double(p.done), total: Double(p.total))
                                                .tint(Theme.of(child.themeMode).primary)
                                        }
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(theme.textSecondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("Home")
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
        .refreshable { await app.reloadMembers(); await load() }
    }

    private func load() async {
        for child in app.children {
            if let items = try? await app.backend.myDay(memberId: child.id, day: .now) {
                progress[child.id] = (items.filter(\.done).count, items.count)
            }
        }
    }
}
