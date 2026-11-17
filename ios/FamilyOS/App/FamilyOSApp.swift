import SwiftUI

@main
struct FamilyOSApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .task { await app.start() }
                .onOpenURL { app.handle(url: $0) }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        Group {
            switch app.phase {
            case .loading:
                ProgressView().controlSize(.large)
            case .welcome, .needsFamily:
                WelcomeView()
            case .signedIn:
                MainTabView()
            }
        }
        .animation(.easeInOut, value: app.phase)
    }
}
