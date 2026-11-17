import SwiftUI

/// Parents sign in with email. Ajik creates the family the first time.
struct ParentAuthView: View {
    @EnvironmentObject var app: AppState
    enum Step { case signIn, createFamily }
    @State private var step: Step = .signIn
    @State private var isNewAccount = false
    @State private var email = ""
    @State private var password = ""
    @State private var familyName = "Jaens Family"
    @State private var ownerName = "Ajik"
    @State private var relationship = "Papa"
    @State private var busy = false
    @State private var error: String?
    @State private var info: String?
    private let theme = Theme.of(.parent)

    var body: some View {
        Form {
            switch step {
            case .signIn:
                Section {
                    Picker("", selection: $isNewAccount) {
                        Text("Sign in").tag(false)
                        Text("New account").tag(true)
                    }
                    .pickerStyle(.segmented)
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password (8+ characters)", text: $password)
                        .textContentType(isNewAccount ? .newPassword : .password)
                }
                Section {
                    ErrorText(message: error)
                    if let info { Label(info, systemImage: "envelope.badge").foregroundStyle(theme.success) }
                    PrimaryButton(title: isNewAccount ? "Create account" : "Sign in", theme: theme, busy: busy) {
                        Task { await submitAuth() }
                    }
                    .listRowInsets(EdgeInsets())
                }
                Section {
                    Text("Kids don't need a password. Add them in the app, then they scan a QR code on their phone.")
                        .font(.footnote).foregroundStyle(theme.textSecondary)
                }
            case .createFamily:
                Section("Your family") {
                    TextField("Family name", text: $familyName)
                    TextField("Your name", text: $ownerName)
                    Picker("You are", selection: $relationship) {
                        Text("Papa").tag("Papa"); Text("Mama").tag("Mama"); Text("Guardian").tag("Guardian")
                    }
                }
                Section {
                    ErrorText(message: error)
                    PrimaryButton(title: "Create Family", systemImage: "house.fill", theme: theme, busy: busy) {
                        Task { await createFamily() }
                    }
                    .listRowInsets(EdgeInsets())
                }
            }
        }
        .navigationTitle(step == .signIn ? "Parent" : "Create Family")
    }

    private func submitAuth() async {
        error = nil; info = nil
        guard email.contains("@"), password.count >= 8 else {
            error = "Enter your email and a password of 8 or more characters."; return
        }
        busy = true; defer { busy = false }
        do {
            if isNewAccount {
                try await app.backend.parentSignUp(email: email, password: password)
                // If the project asks for email confirmation, sign-in fails until the link is tapped.
                let member: Member?
                do {
                    member = try await app.backend.parentSignIn(email: email, password: password)
                } catch {
                    info = "Check your email and tap the link, then sign in."
                    isNewAccount = false
                    return
                }
                if let member, !app.backend.isDemo {
                    try await app.enter(as: member)
                } else {
                    step = .createFamily
                }
            } else {
                if let member = try await app.backend.parentSignIn(email: email, password: password) {
                    try await app.enter(as: member)
                } else {
                    step = .createFamily
                }
            }
        } catch {
            self.error = FriendlyError.from(error)
        }
    }

    private func createFamily() async {
        error = nil
        guard !familyName.trimmingCharacters(in: .whitespaces).isEmpty,
              !ownerName.trimmingCharacters(in: .whitespaces).isEmpty else {
            error = "Please fill in both names."; return
        }
        busy = true; defer { busy = false }
        do {
            let member = try await app.backend.createFamily(name: familyName, ownerName: ownerName, relationship: relationship)
            try await app.enter(as: member)
        } catch {
            self.error = FriendlyError.from(error)
        }
    }
}
