import SwiftUI
import CoreImage.CIFilterBuiltins

struct FamilyView: View {
    @EnvironmentObject var app: AppState
    @State private var showAdd = false
    @State private var pairing: Member?

    private var isOwner: Bool { app.me?.role == .owner }

    var body: some View {
        NavigationStack {
            List {
                ForEach(app.members) { m in
                    HStack(spacing: 14) {
                        Avatar(member: m, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.displayName).font(.headline)
                            Text([m.relationship, m.age.map { "\($0) yrs" }].compactMap { $0 }.joined(separator: " · "))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if m.role != .owner {
                            if m.hasDevice {
                                Label("Phone linked", systemImage: "iphone").labelStyle(.iconOnly)
                                    .foregroundStyle(.green)
                                    .accessibilityLabel("Phone linked")
                            }
                            if isOwner {
                                Button(m.hasDevice ? "New phone" : "Add device") { pairing = m }
                                    .buttonStyle(.bordered).font(.caption.bold())
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(app.family?.name ?? "Family")
            .toolbar {
                if isOwner {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showAdd = true } label: { Label("Add Member", systemImage: "person.badge.plus") }
                    }
                }
            }
            .refreshable { await app.reloadMembers() }
            .sheet(isPresented: $showAdd) { AddMemberView() }
            .sheet(item: $pairing, onDismiss: { Task { await app.reloadMembers() } }) { m in PairDeviceView(member: m) }
        }
    }
}

struct AddMemberView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var nickname = ""
    @State private var role: MemberRole = .child
    @State private var gender: Gender = .girl
    @State private var dob = Calendar.current.date(byAdding: .year, value: -8, to: .now)!
    @State private var relationship = "Daughter"
    @State private var emoji = "🌸"
    @State private var busy = false
    @State private var error: String?
    private let emojis = ["🌸", "🦋", "🌷", "🐰", "⚽", "🚀", "🦖", "🎨", "🎧", "👩", "👨", "🙂"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Nickname (optional)", text: $nickname)
                    Picker("Role", selection: $role) {
                        Text("Child").tag(MemberRole.child)
                        Text("Parent").tag(MemberRole.parent)
                    }
                    .pickerStyle(.segmented)
                }
                if role == .child {
                    Section("Child") {
                        Picker("Boy or girl", selection: $gender) {
                            Text("Girl").tag(Gender.girl); Text("Boy").tag(Gender.boy)
                        }
                        .pickerStyle(.segmented)
                        DatePicker("Birthday", selection: $dob, in: ...Date.now, displayedComponents: .date)
                        Text("The look is picked from age: under 15 gets the kids look, 15+ the teen look.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Avatar") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6)) {
                        ForEach(emojis, id: \.self) { e in
                            Text(e).font(.largeTitle)
                                .padding(4)
                                .background(e == emoji ? Color.accentColor.opacity(0.2) : .clear, in: Circle())
                                .onTapGesture { emoji = e }
                        }
                    }
                }
                Section {
                    ErrorText(message: error)
                    PrimaryButton(title: "Save", theme: app.theme, busy: busy) { Task { await save() } }
                        .listRowInsets(EdgeInsets())
                }
            }
            .navigationTitle("Add Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onChange(of: gender) { _, g in relationship = g == .boy ? "Son" : "Daughter" }
            .onChange(of: role) { _, r in relationship = r == .parent ? "Mama" : (gender == .boy ? "Son" : "Daughter") }
        }
    }

    private func save() async {
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { error = "Please enter a name."; return }
        busy = true; defer { busy = false }
        do {
            _ = try await app.backend.addMember(
                name: clean, nickname: nickname.isEmpty ? nil : nickname, role: role, relationship: relationship,
                dateOfBirth: role == .child ? dob : nil, gender: role == .child ? gender : nil, emoji: emoji)
            await app.reloadMembers()
            dismiss()
        } catch {
            self.error = FriendlyError.from(error)
        }
    }
}

/// Parent phone shows a QR for 10 minutes. The child's phone scans it to join.
struct PairDeviceView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let member: Member
    @State private var code: PairingCode?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Avatar(member: member, size: 72)
                Text("Add \(member.displayName)'s phone").font(.title2.bold())
                Text("On \(member.displayName)'s iPhone: open Family OS, tap **Join Family**, then scan this code.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                if let code {
                    Image(uiImage: QRCode.image(for: code.joinURL.absoluteString))
                        .interpolation(.none).resizable().scaledToFit()
                        .frame(width: 240, height: 240)
                        .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityLabel("Pairing QR code")
                    Text("\(code.code.prefix(4)) \(code.code.suffix(4))")
                        .font(.system(.title, design: .monospaced).weight(.bold))
                        .textSelection(.enabled)
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let left = Int(code.expiresAt.timeIntervalSince(ctx.date))
                        if left > 0 {
                            Text("Works for \(left / 60):\(String(format: "%02d", left % 60))")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else {
                            Button("Code expired. Make a new one") { Task { await make() } }
                        }
                    }
                } else if error == nil {
                    ProgressView()
                }
                ErrorText(message: error)
                Spacer()
            }
            .padding(24)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await make() }
        }
    }

    private func make() async {
        do {
            code = try await app.backend.createPairingCode(memberId: member.id)
            error = nil
        } catch {
            self.error = FriendlyError.from(error)
        }
    }
}

enum QRCode {
    static func image(for text: String) -> UIImage {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        let context = CIContext()
        if let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
           let cg = context.createCGImage(output, from: output.extent) {
            return UIImage(cgImage: cg)
        }
        return UIImage(systemName: "qrcode") ?? UIImage()
    }
}
