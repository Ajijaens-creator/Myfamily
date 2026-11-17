import SwiftUI

@MainActor
final class AppState: ObservableObject {
    enum Phase: Equatable { case loading, welcome, needsFamily, signedIn }

    let backend: FamilyBackend
    @Published var phase: Phase = .loading
    @Published var me: Member?
    @Published var family: Family?
    @Published var members: [Member] = []
    /// A join code that came in from the iPhone camera (QR link).
    @Published var pendingJoinCode: String?

    init(backend: FamilyBackend = AppConfig.makeBackend()) {
        self.backend = backend
    }

    var theme: Theme { Theme.of(me?.themeMode ?? .parent) }
    var children: [Member] { members.filter { $0.role == .child } }

    func start() async {
        do {
            if let member = try await backend.restoreSession() {
                try await enter(as: member)
            } else {
                phase = .welcome
            }
        } catch {
            phase = .welcome
        }
    }

    func enter(as member: Member) async throws {
        me = member
        family = try await backend.family()
        members = try await backend.members()
        phase = .signedIn
    }

    func reloadMembers() async {
        if let list = try? await backend.members() {
            members = list
            if let id = me?.id, let updated = list.first(where: { $0.id == id }) { me = updated }
        }
    }

    func signOut() async {
        try? await backend.signOut()
        me = nil; family = nil; members = []
        phase = .welcome
    }

    func handle(url: URL) {
        guard url.scheme == "jaensfamily", url.host == "join",
              let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value else { return }
        if phase != .signedIn { pendingJoinCode = code }
    }
}
