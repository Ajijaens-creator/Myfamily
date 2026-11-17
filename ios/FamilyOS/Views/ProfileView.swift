import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var app: AppState
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            List {
                if let me = app.me {
                    Section {
                        HStack(spacing: 16) {
                            Avatar(member: me, size: 64)
                            VStack(alignment: .leading) {
                                Text(me.displayName).font(.title2.bold())
                                Text("\(me.role.label) · \(app.family?.name ?? "")").foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    if app.backend.isDemo, let demo = app.backend as? DemoBackend {
                        Section("Demo: who holds this phone?") {
                            ForEach(app.members) { m in
                                Button {
                                    demo.demoSwitch(to: m)
                                    Task { try? await app.enter(as: m) }
                                } label: {
                                    HStack { Avatar(member: m, size: 32); Text(m.displayName); Spacer()
                                        if m.id == me.id { Image(systemName: "checkmark") } }
                                }
                                .foregroundStyle(.primary)
                            }
                        }
                    }
                    Section {
                        if me.role.isParent || app.backend.isDemo {
                            Button("Sign out", role: .destructive) { confirmSignOut = true }
                        } else {
                            Text("This phone stays signed in. Ask Papa if you need to change it.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                }
            }
            .navigationTitle("Profile")
            .confirmationDialog("Sign out of Family OS?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { Task { await app.signOut() } }
            }
        }
    }
}
