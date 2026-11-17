import Foundation

enum MemberRole: String, Codable, CaseIterable {
    case owner = "FAMILY_OWNER"
    case parent = "PARENT_GUARDIAN"
    case child = "CHILD"

    var isParent: Bool { self != .child }
    var label: String {
        switch self {
        case .owner: return "Family Owner"
        case .parent: return "Parent"
        case .child: return "Child"
        }
    }
}

enum ThemeMode: String, Codable {
    case kidsBoy = "KIDS_BOY", kidsGirl = "KIDS_GIRL", teen = "TEEN", parent = "PARENT"
}

enum Gender: String, Codable, CaseIterable {
    case boy = "BOY", girl = "GIRL"
}

enum ActivityCategory: String, Codable, CaseIterable, Identifiable {
    case school = "SCHOOL", study = "STUDY", sport = "SPORT", family = "FAMILY"
    case health = "HEALTH", bedtime = "BEDTIME", other = "OTHER"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .school: return "🏫"
        case .study: return "📘"
        case .sport: return "⚽"
        case .family: return "🏠"
        case .health: return "💊"
        case .bedtime: return "🌙"
        case .other: return "⭐"
        }
    }
    var label: String { rawValue.capitalized }
}

enum RepeatType: String, Codable, CaseIterable, Identifiable {
    case once = "ONCE", daily = "DAILY", weekdays = "WEEKDAYS", weekly = "WEEKLY"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .once: return "Once"
        case .daily: return "Every day"
        case .weekdays: return "School days"
        case .weekly: return "Some days"
        }
    }
}

struct Member: Codable, Identifiable, Hashable {
    let id: UUID
    var familyId: UUID
    var userId: UUID?
    var name: String
    var nickname: String?
    var dateOfBirth: String?
    var gender: Gender?
    var relationship: String
    var role: MemberRole
    var themeMode: ThemeMode
    var avatarEmoji: String

    enum CodingKeys: String, CodingKey {
        case id, name, nickname, gender, relationship, role
        case familyId = "family_id", userId = "user_id", dateOfBirth = "date_of_birth"
        case themeMode = "theme_mode", avatarEmoji = "avatar_emoji"
    }

    var displayName: String { (nickname?.isEmpty == false ? nickname : nil) ?? name }
    var hasDevice: Bool { userId != nil }
    var age: Int? {
        guard let dob = dateOfBirth, let date = DateFormats.day.date(from: dob) else { return nil }
        return Calendar.current.dateComponents([.year], from: date, to: .now).year
    }
}

struct Family: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
}

/// One row of My Day (from the `my_day` database function).
struct DayItem: Codable, Identifiable, Hashable {
    let activityId: UUID
    var title: String
    var icon: String
    var category: ActivityCategory
    var startTime: String
    var endTime: String?
    var locationName: String?
    var note: String?
    var done: Bool

    var id: UUID { activityId }

    enum CodingKeys: String, CodingKey {
        case title, icon, category, note, done
        case activityId = "activity_id", startTime = "start_time", endTime = "end_time"
        case locationName = "location_name"
    }

    var timeLabel: String { String(startTime.prefix(5)) }

    /// Upcoming / Now / Missed are worked out from the clock, never stored.
    func status(on day: Date, now: Date = .now) -> ItemStatus {
        if done { return .done }
        guard Calendar.current.isDateInToday(day) else {
            return day < now ? .missed : .upcoming
        }
        let start = DateFormats.time(startTime, on: day)
        let end = endTime.map { DateFormats.time($0, on: day) }
        if let start, now < start { return .upcoming }
        if let end { return now <= end ? .now : .missed }
        return .now
    }
}

enum ItemStatus {
    case upcoming, now, done, missed
    var label: String {
        switch self {
        case .upcoming: return "Upcoming"
        case .now: return "Now"
        case .done: return "Done"
        case .missed: return "Missed"
        }
    }
    var symbol: String {
        switch self {
        case .upcoming: return "circle"
        case .now: return "play.circle.fill"
        case .done: return "checkmark.circle.fill"
        case .missed: return "exclamationmark.circle"
        }
    }
}

struct NewActivity: Encodable {
    var familyId: UUID
    var memberId: UUID
    var title: String
    var icon: String
    var category: ActivityCategory
    var startDate: String
    var startTime: String
    var endTime: String?
    var locationName: String?
    var note: String?
    var repeatType: RepeatType
    var repeatDays: [Int]
    var reminderOffset: Int?
    var createdBy: UUID

    enum CodingKeys: String, CodingKey {
        case title, icon, category, note
        case familyId = "family_id", memberId = "member_id", startDate = "start_date"
        case startTime = "start_time", endTime = "end_time", locationName = "location_name"
        case repeatType = "repeat_type", repeatDays = "repeat_days"
        case reminderOffset = "reminder_offset", createdBy = "created_by"
    }
}

struct PairingCode: Codable, Hashable {
    var code: String
    var expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case code
        case expiresAt = "expires_at"
    }

    /// What the QR holds. The iPhone camera opens the app with it.
    var joinURL: URL { URL(string: "jaensfamily://join?code=\(code)")! }
}

enum DateFormats {
    static let day: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func time(_ hhmm: String, on day: Date) -> Date? {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day)
    }

    static func hhmm(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}

/// Short, friendly error text. Never technical.
struct FriendlyError: LocalizedError {
    let message: String
    var errorDescription: String? { message }

    static func from(_ error: Error) -> String {
        if let f = error as? FriendlyError { return f.message }
        let text = String(describing: error)
        for known in ["This code has expired", "already in a family", "Only the family owner", "Invalid login credentials"] {
            if text.contains(known) {
                if known == "Invalid login credentials" { return "Email or password is not right." }
                if let range = text.range(of: known) {
                    let tail = text[range.lowerBound...]
                    return String(tail.prefix { $0 != "\"" && $0 != "\n" })
                }
            }
        }
        if (error as NSError).domain == NSURLErrorDomain { return "No internet. Try again in a moment." }
        return "Something went wrong. Please try again."
    }
}
