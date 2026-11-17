import SwiftUI

struct AddActivityView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let member: Member
    let day: Date
    let onSaved: () -> Void

    @State private var title = ""
    @State private var category: ActivityCategory = .school
    @State private var date: Date
    @State private var start = Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: .now)!
    @State private var hasEnd = false
    @State private var end = Calendar.current.date(bySettingHour: 16, minute: 0, second: 0, of: .now)!
    @State private var repeatType: RepeatType = .once
    @State private var weekdays: Set<Int> = []
    @State private var place = ""
    @State private var note = ""
    @State private var reminder: Int? = 10
    @State private var busy = false
    @State private var error: String?

    init(member: Member, day: Date, onSaved: @escaping () -> Void) {
        self.member = member; self.day = day; self.onSaved = onSaved
        _date = State(initialValue: day)
    }

    private let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Activity name", text: $title)
                    Picker("Icon", selection: $category) {
                        ForEach(ActivityCategory.allCases) { c in Text("\(c.icon) \(c.label)").tag(c) }
                    }
                }
                Section("When") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    DatePicker("Start", selection: $start, displayedComponents: .hourAndMinute)
                    Toggle("End time", isOn: $hasEnd)
                    if hasEnd { DatePicker("End", selection: $end, displayedComponents: .hourAndMinute) }
                    Picker("Repeat", selection: $repeatType) {
                        ForEach(RepeatType.allCases) { Text($0.label).tag($0) }
                    }
                    if repeatType == .weekly {
                        HStack {
                            ForEach(1...7, id: \.self) { d in
                                let on = weekdays.contains(d)
                                Button(dayNames[d - 1]) {
                                    if on { weekdays.remove(d) } else { weekdays.insert(d) }
                                }
                                .font(.caption.bold())
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .background(on ? app.theme.primary : app.theme.primarySoft, in: Capsule())
                                .foregroundStyle(on ? .white : app.theme.primary)
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Picker("Reminder", selection: $reminder) {
                        Text("None").tag(Int?.none)
                        Text("At start").tag(Int?.some(0))
                        Text("10 min before").tag(Int?.some(10))
                        Text("30 min before").tag(Int?.some(30))
                        Text("1 hour before").tag(Int?.some(60))
                    }
                }
                Section("Optional") {
                    TextField("Place", text: $place)
                    TextField("Note", text: $note, axis: .vertical)
                }
                Section {
                    ErrorText(message: error)
                    PrimaryButton(title: "Save Activity", theme: app.theme, busy: busy) { Task { await save() } }
                        .listRowInsets(EdgeInsets())
                }
            }
            .navigationTitle("Add for \(member.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func save() async {
        error = nil
        let name = title.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { error = "Give the activity a name."; return }
        if hasEnd, end <= start { error = "End time must be after start."; return }
        if repeatType == .weekly, weekdays.isEmpty { error = "Pick at least one day."; return }
        guard let me = app.me else { return }
        busy = true; defer { busy = false }
        let activity = NewActivity(
            familyId: member.familyId, memberId: member.id, title: name, icon: category.icon,
            category: category, startDate: DateFormats.day.string(from: date),
            startTime: DateFormats.hhmm(start), endTime: hasEnd ? DateFormats.hhmm(end) : nil,
            locationName: place.isEmpty ? nil : place, note: note.isEmpty ? nil : note,
            repeatType: repeatType, repeatDays: repeatType == .weekly ? weekdays.sorted() : [],
            reminderOffset: reminder, createdBy: me.id)
        do {
            try await app.backend.addActivity(activity)
            onSaved()
            dismiss()
        } catch {
            self.error = FriendlyError.from(error)
        }
    }
}
