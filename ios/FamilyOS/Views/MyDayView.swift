import SwiftUI

struct MyDayView: View {
    @EnvironmentObject var app: AppState
    let member: Member
    let canEdit: Bool
    let greeting: Bool
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var items: [DayItem] = []
    @State private var loading = true
    @State private var error: String?
    @State private var showAdd = false

    private var theme: Theme { Theme.of(member.themeMode) }
    private var isMine: Bool { member.id == app.me?.id }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if greeting {
                    Text("Hi \(member.displayName)! \(theme.greetingEmoji)")
                        .font(theme.titleFont).foregroundStyle(theme.textPrimary)
                }
                header
                WeekStrip(selected: $day, theme: theme)
                ErrorText(message: error)
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
                } else if items.isEmpty {
                    EmptyState(emoji: "☀️", text: "No activities today", theme: theme)
                } else {
                    ForEach(items) { item in row(item) }
                }
            }
            .padding(20)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle(greeting ? "" : member.displayName)
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdd = true } label: { Label("Add Activity", systemImage: "plus.circle.fill") }
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddActivityView(member: member, day: day) { Task { await load() } }
        }
        .task(id: day) { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("My Day").font(.title2.bold()).foregroundStyle(theme.textPrimary)
                Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer()
            if !items.isEmpty {
                let done = items.filter(\.done).count
                Text("\(done)/\(items.count)")
                    .font(.headline.monospacedDigit())
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(theme.primarySoft, in: Capsule())
                    .foregroundStyle(theme.primary)
            }
        }
    }

    private func row(_ item: DayItem) -> some View {
        let status = item.status(on: day)
        let canTick = isMine && Calendar.current.isDateInToday(day)
        return Card(theme: theme) {
            HStack(spacing: 14) {
                Text(item.icon).font(.system(size: 30))
                    .frame(width: 52, height: 52)
                    .background(theme.primarySoft, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).font(.headline).foregroundStyle(theme.textPrimary)
                    Text(item.endTime.map { "\(item.timeLabel) – \($0.prefix(5))" } ?? item.timeLabel)
                        .font(.subheadline.monospacedDigit()).foregroundStyle(theme.textSecondary)
                    if let place = item.locationName, !place.isEmpty {
                        Label(place, systemImage: "mappin").font(.caption).foregroundStyle(theme.textSecondary)
                    }
                }
                Spacer()
                Button {
                    Task { await toggle(item) }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: status.symbol).font(.system(size: 30))
                        Text(status.label).font(.caption2.bold())
                    }
                    .foregroundStyle(color(status))
                    .frame(minWidth: 60, minHeight: 52)
                }
                .disabled(!canTick)
                .accessibilityLabel(canTick ? (item.done ? "Undo done" : "Mark as done") : status.label)
            }
        }
    }

    private func color(_ s: ItemStatus) -> Color {
        switch s {
        case .done: return theme.success
        case .now: return theme.primary
        case .missed: return theme.warning
        case .upcoming: return theme.textSecondary
        }
    }

    private func load() async {
        loading = items.isEmpty
        defer { loading = false }
        do {
            items = try await app.backend.myDay(memberId: member.id, day: day)
            error = nil
        } catch {
            self.error = FriendlyError.from(error)
        }
    }

    private func toggle(_ item: DayItem) async {
        guard let i = items.firstIndex(of: item) else { return }
        let newValue = !item.done
        items[i].done = newValue // feels instant; put back if it fails
        if newValue { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        do {
            try await app.backend.setDone(newValue, activityId: item.activityId, day: day)
        } catch {
            items[i].done = !newValue
            self.error = FriendlyError.from(error)
        }
    }
}

struct WeekStrip: View {
    @Binding var selected: Date
    let theme: Theme

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let days = (-3...3).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
        HStack(spacing: 6) {
            ForEach(days, id: \.self) { d in
                let isSel = cal.isDate(d, inSameDayAs: selected)
                Button { selected = d } label: {
                    VStack(spacing: 4) {
                        Text(d.formatted(.dateTime.weekday(.narrow))).font(.caption)
                        Text(d.formatted(.dateTime.day())).font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(isSel ? theme.primary : theme.surface, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(isSel ? .white : (cal.isDateInToday(d) ? theme.primary : theme.textPrimary))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
