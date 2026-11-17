import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var app: AppState
    @State private var showParent = false
    @State private var showJoin = false
    private let theme = Theme.of(.parent)

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Text("🏡").font(.system(size: 80))
                VStack(spacing: 8) {
                    Text("Family OS").font(.largeTitle.bold())
                    Text("Our family, one simple app.")
                        .foregroundStyle(theme.textSecondary)
                }
                Spacer()
                if app.backend.isDemo {
                    Label("Demo mode: sample family, nothing is saved", systemImage: "sparkles")
                        .font(.footnote).foregroundStyle(theme.textSecondary)
                }
                VStack(spacing: 12) {
                    PrimaryButton(title: "Join Family", systemImage: "qrcode.viewfinder", theme: Theme.of(.kidsGirl)) {
                        showJoin = true
                    }
                    Button { showParent = true } label: {
                        Text("I'm a parent").fontWeight(.semibold)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .overlay(RoundedRectangle(cornerRadius: theme.radius).stroke(theme.primary, lineWidth: 2))
                    }
                    .foregroundStyle(theme.primary)
                }
            }
            .padding(24)
            .background(theme.background.ignoresSafeArea())
            .navigationDestination(isPresented: $showParent) { ParentAuthView() }
            .navigationDestination(isPresented: $showJoin) { JoinFamilyView() }
            .onChange(of: app.pendingJoinCode) { _, code in if code != nil { showJoin = true } }
            .onAppear { if app.pendingJoinCode != nil { showJoin = true } }
        }
    }
}
