import Foundation
import Supabase

/// Everything the app asks of the server. Two versions: the real one (Supabase)
/// and a Demo one with sample data, used when no Supabase keys are set.
protocol FamilyBackend: AnyObject {
    var isDemo: Bool { get }

    /// The member this phone is signed in as, or nil.
    func restoreSession() async throws -> Member?
    func parentSignIn(email: String, password: String) async throws -> Member?
    func parentSignUp(email: String, password: String) async throws
    func createFamily(name: String, ownerName: String, relationship: String) async throws -> Member
    func joinFamily(code: String, deviceName: String) async throws -> Member
    func signOut() async throws

    func family() async throws -> Family
    func members() async throws -> [Member]
    func addMember(name: String, nickname: String?, role: MemberRole, relationship: String,
                   dateOfBirth: Date?, gender: Gender?, emoji: String) async throws -> Member
    func createPairingCode(memberId: UUID) async throws -> PairingCode

    func myDay(memberId: UUID, day: Date) async throws -> [DayItem]
    func setDone(_ done: Bool, activityId: UUID, day: Date) async throws
    func addActivity(_ activity: NewActivity) async throws
}

enum AppConfig {
    static var supabaseURL: URL? {
        guard let host = Bundle.main.object(forInfoDictionaryKey: "SupabaseHost") as? String,
              !host.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return URL(string: "https://\(host.trimmingCharacters(in: .whitespaces))")
    }
    static var supabaseKey: String? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String,
              !key.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return key.trimmingCharacters(in: .whitespaces)
    }

    static func makeBackend() -> FamilyBackend {
        if let url = supabaseURL, let key = supabaseKey {
            return SupabaseBackend(url: url, key: key)
        }
        return DemoBackend()
    }
}

// MARK: - Supabase

final class SupabaseBackend: FamilyBackend {
    let client: SupabaseClient
    var isDemo: Bool { false }

    init(url: URL, key: String) {
        client = SupabaseClient(supabaseURL: url, supabaseKey: key)
    }

    private func me() async throws -> Member? {
        guard let uid = client.auth.currentUser?.id else { return nil }
        let rows: [Member] = try await client.from("family_member")
            .select()
            .eq("user_id", value: uid)
            .limit(1)
            .execute().value
        return rows.first
    }

    func restoreSession() async throws -> Member? {
        // The session is kept in the Keychain, so kids never type a password.
        guard (try? await client.auth.session) != nil else { return nil }
        return try await me()
    }

    func parentSignIn(email: String, password: String) async throws -> Member? {
        _ = try await client.auth.signIn(email: email, password: password)
        return try await me()
    }

    func parentSignUp(email: String, password: String) async throws {
        _ = try await client.auth.signUp(email: email, password: password)
    }

    func createFamily(name: String, ownerName: String, relationship: String) async throws -> Member {
        struct Params: Encodable { let p_family_name: String; let p_owner_name: String; let p_relationship: String }
        let _: UUID = try await client
            .rpc("create_family", params: Params(p_family_name: name, p_owner_name: ownerName, p_relationship: relationship))
            .execute().value
        guard let member = try await me() else { throw FriendlyError(message: "Please try again.") }
        return member
    }

    func joinFamily(code: String, deviceName: String) async throws -> Member {
        if client.auth.currentUser == nil {
            _ = try await client.auth.signInAnonymously()
        }
        struct Params: Encodable { let p_code: String; let p_device_name: String }
        let _: UUID = try await client
            .rpc("redeem_pairing_code", params: Params(p_code: code, p_device_name: deviceName))
            .execute().value
        guard let member = try await me() else { throw FriendlyError(message: "Please try again.") }
        return member
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    func family() async throws -> Family {
        let rows: [Family] = try await client.from("family").select("id,name").limit(1).execute().value
        guard let f = rows.first else { throw FriendlyError(message: "Family not found.") }
        return f
    }

    func members() async throws -> [Member] {
        try await client.from("family_member").select().order("created_at").execute().value
    }

    func addMember(name: String, nickname: String?, role: MemberRole, relationship: String,
                   dateOfBirth: Date?, gender: Gender?, emoji: String) async throws -> Member {
        struct Params: Encodable {
            let p_name: String; let p_role: String; let p_relationship: String
            let p_nickname: String?; let p_date_of_birth: String?; let p_gender: String?; let p_avatar_emoji: String
        }
        let id: UUID = try await client.rpc("add_member", params: Params(
            p_name: name, p_role: role.rawValue, p_relationship: relationship,
            p_nickname: nickname, p_date_of_birth: dateOfBirth.map { DateFormats.day.string(from: $0) },
            p_gender: gender?.rawValue, p_avatar_emoji: emoji)).execute().value
        let rows: [Member] = try await client.from("family_member").select().eq("id", value: id).execute().value
        guard let m = rows.first else { throw FriendlyError(message: "Please try again.") }
        return m
    }

    func createPairingCode(memberId: UUID) async throws -> PairingCode {
        struct Params: Encodable { let p_member_id: UUID }
        let rows: [PairingCode] = try await client
            .rpc("create_pairing_code", params: Params(p_member_id: memberId))
            .execute().value
        guard let code = rows.first else { throw FriendlyError(message: "Please try again.") }
        return code
    }

    func myDay(memberId: UUID, day: Date) async throws -> [DayItem] {
        struct Params: Encodable { let p_member_id: UUID; let p_day: String }
        return try await client
            .rpc("my_day", params: Params(p_member_id: memberId, p_day: DateFormats.day.string(from: day)))
            .execute().value
    }

    func setDone(_ done: Bool, activityId: UUID, day: Date) async throws {
        let date = DateFormats.day.string(from: day)
        if done {
            struct Row: Encodable { let activity_id: UUID; let activity_date: String }
            try await client.from("activity_completion")
                .insert(Row(activity_id: activityId, activity_date: date))
                .execute()
        } else {
            try await client.from("activity_completion")
                .delete()
                .eq("activity_id", value: activityId)
                .eq("activity_date", value: date)
                .execute()
        }
    }

    func addActivity(_ activity: NewActivity) async throws {
        try await client.from("activity").insert(activity).execute()
    }
}

// MARK: - Demo (no server, sample family)

final class DemoBackend: FamilyBackend {
    var isDemo: Bool { true }
    private let familyId = UUID()
    private var me: Member?
    private var all: [Member] = []
    private var activities: [(member: UUID, item: DayItem, repeatType: RepeatType, start: Date)] = []
    private var done: Set<String> = []

    init() {
        func m(_ name: String, _ role: MemberRole, _ rel: String, _ age: Int?, _ g: Gender?, _ theme: ThemeMode, _ emoji: String) -> Member {
            let dob = age.flatMap { Calendar.current.date(byAdding: .year, value: -$0, to: .now) }
            return Member(id: UUID(), familyId: familyId, userId: role == .owner ? UUID() : nil, name: name, nickname: nil,
                          dateOfBirth: dob.map { DateFormats.day.string(from: $0) }, gender: g,
                          relationship: rel, role: role, themeMode: theme, avatarEmoji: emoji)
        }
        all = [
            m("Ajik", .owner, "Papa", nil, nil, .parent, "👨"),
            m("Ibuk", .parent, "Mama", nil, nil, .parent, "👩"),
            m("Radja", .child, "Son", 16, .boy, .teen, "⚽"),
            m("Rada", .child, "Daughter", 14, .girl, .kidsGirl, "🦋"),
            m("Renatta", .child, "Daughter", 10, .girl, .kidsGirl, "🌷"),
            m("Raiya", .child, "Daughter", 8, .girl, .kidsGirl, "🌸"),
            m("Rixty", .child, "Daughter", 6, .girl, .kidsGirl, "🐰"),
        ]
        for kid in all where kid.role == .child {
            add(kid.id, "School", .school, "07:00", "12:30", .weekdays)
            add(kid.id, "Homework", .study, "19:00", "20:00", .daily)
            add(kid.id, "Bedtime", .bedtime, kid.age ?? 10 < 12 ? "20:30" : "21:30", nil, .daily)
        }
    }

    private func add(_ member: UUID, _ title: String, _ c: ActivityCategory, _ s: String, _ e: String?, _ r: RepeatType) {
        let item = DayItem(activityId: UUID(), title: title, icon: c.icon, category: c, startTime: s + ":00",
                           endTime: e.map { $0 + ":00" }, locationName: nil, note: nil, done: false)
        activities.append((member, item, r, Calendar.current.startOfDay(for: .now)))
    }

    func restoreSession() async throws -> Member? { me }
    func parentSignIn(email: String, password: String) async throws -> Member? { me = all[0]; return me }
    func parentSignUp(email: String, password: String) async throws {}
    func createFamily(name: String, ownerName: String, relationship: String) async throws -> Member { me = all[0]; return all[0] }
    func joinFamily(code: String, deviceName: String) async throws -> Member {
        // Demo: any code joins as Raiya.
        me = all.first { $0.name == "Raiya" }
        return me!
    }
    func signOut() async throws { me = nil }
    func family() async throws -> Family { Family(id: familyId, name: "Jaens Family") }
    func members() async throws -> [Member] { all }

    func addMember(name: String, nickname: String?, role: MemberRole, relationship: String,
                   dateOfBirth: Date?, gender: Gender?, emoji: String) async throws -> Member {
        let age = dateOfBirth.flatMap { Calendar.current.dateComponents([.year], from: $0, to: .now).year }
        let theme: ThemeMode = role != .child ? .parent : (age ?? 0) >= 15 ? .teen : gender == .boy ? .kidsBoy : .kidsGirl
        let m = Member(id: UUID(), familyId: familyId, userId: nil, name: name, nickname: nickname,
                       dateOfBirth: dateOfBirth.map { DateFormats.day.string(from: $0) }, gender: gender,
                       relationship: relationship, role: role, themeMode: theme, avatarEmoji: emoji)
        all.append(m)
        return m
    }

    func createPairingCode(memberId: UUID) async throws -> PairingCode {
        let letters = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        return PairingCode(code: String((0..<8).map { _ in letters.randomElement()! }),
                           expiresAt: .now.addingTimeInterval(600))
    }

    func myDay(memberId: UUID, day: Date) async throws -> [DayItem] {
        let wd = Calendar.current.component(.weekday, from: day) // 1 = Sunday
        let key = DateFormats.day.string(from: day)
        return activities.filter { a in
            guard a.member == memberId else { return false }
            switch a.repeatType {
            case .once: return Calendar.current.isDate(a.start, inSameDayAs: day)
            case .daily, .weekly: return true
            case .weekdays: return (2...6).contains(wd)
            }
        }.map { a in
            var item = a.item
            item.done = done.contains("\(item.activityId)|\(key)")
            return item
        }.sorted { $0.startTime < $1.startTime }
    }

    func setDone(_ isDone: Bool, activityId: UUID, day: Date) async throws {
        let k = "\(activityId)|\(DateFormats.day.string(from: day))"
        if isDone { done.insert(k) } else { done.remove(k) }
    }

    func addActivity(_ a: NewActivity) async throws {
        let item = DayItem(activityId: UUID(), title: a.title, icon: a.icon, category: a.category,
                           startTime: a.startTime, endTime: a.endTime, locationName: a.locationName,
                           note: a.note, done: false)
        activities.append((a.memberId, item, a.repeatType, DateFormats.day.date(from: a.startDate) ?? .now))
    }

    /// Demo only: switch who holds the phone.
    func demoSwitch(to member: Member) { me = member }
}
