import SwiftUI
import AVFoundation
import UIKit

/// Child phone: scan the QR on Papa's or Mama's phone, or type the code.
struct JoinFamilyView: View {
    @EnvironmentObject var app: AppState
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?
    @State private var scanning = true
    private let theme = Theme.of(.kidsGirl)

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Join your family").font(theme.titleFont).foregroundStyle(theme.textPrimary)
                Text("Ask Papa or Mama to open **Family › Add device**, then point your camera at the code.")
                    .multilineTextAlignment(.center).foregroundStyle(theme.textSecondary)

                if scanning {
                    QRScannerView { scanned in
                        if let parsed = Self.code(from: scanned) {
                            code = parsed
                            scanning = false
                            Task { await join() }
                        }
                    }
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: theme.radius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: theme.radius).stroke(theme.primary, lineWidth: 3))
                }

                Card(theme: theme) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Or type the code").font(.headline)
                        TextField("ABCD 2345", text: $code)
                            .font(.system(.title2, design: .monospaced).weight(.bold))
                            .textInputAutocapitalization(.characters).autocorrectionDisabled()
                            .padding(12)
                            .background(theme.primarySoft, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                ErrorText(message: error)
                PrimaryButton(title: "Join", systemImage: "person.badge.plus", theme: theme, busy: busy) {
                    Task { await join() }
                }
            }
            .padding(20)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("Join Family")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let pending = app.pendingJoinCode {
                code = pending
                app.pendingJoinCode = nil
                scanning = false
                Task { await join() }
            }
        }
    }

    static func code(from scanned: String) -> String? {
        if let url = URL(string: scanned), url.scheme == "jaensfamily",
           let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value {
            return value
        }
        return nil
    }

    private func join() async {
        error = nil
        let clean = code.uppercased().filter { $0.isLetter || $0.isNumber }
        guard clean.count == 8 else { error = "The code has 8 letters and numbers."; return }
        busy = true; defer { busy = false }
        do {
            let member = try await app.backend.joinFamily(code: clean, deviceName: UIDevice.current.name)
            try await app.enter(as: member)
        } catch {
            self.error = FriendlyError.from(error)
            scanning = true
        }
    }
}

/// Camera QR reader (AVFoundation). Shows a friendly note if the camera is off.
struct QRScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let vc = ScannerController()
        vc.onCode = onCode
        return vc
    }
    func updateUIViewController(_ vc: ScannerController, context: Context) {}

    final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onCode: ((String) -> Void)?
        private let session = AVCaptureSession()
        private var preview: AVCaptureVideoPreviewLayer?
        private var delivered = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { granted ? self.setup() : self.showNote("Camera is off. Type the code below.") }
            }
        }

        private func setup() {
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else {
                showNote("No camera here. Type the code below."); return
            }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            view.layer.addSublayer(layer)
            preview = layer
            DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            preview?.frame = view.bounds
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if session.isRunning { session.stopRunning() }
        }

        private func showNote(_ text: String) {
            let label = UILabel()
            label.text = text
            label.textColor = .white
            label.numberOfLines = 0
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            ])
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard !delivered,
                  let value = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
            delivered = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onCode?(value)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.delivered = false }
        }
    }
}
