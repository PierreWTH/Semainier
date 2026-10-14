import SwiftUI
import VisionKit

/// Caméra plein écran qui détecte les EAN-13 / EAN-8, avec saisie manuelle du code.
struct BarcodeScannerView: View {
    var onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var manual = ""
    @FocusState private var typing: Bool

    private var cameraAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if cameraAvailable {
                DataScanner(onCode: onCode)
                    .ignoresSafeArea()
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(.white.opacity(0.85), lineWidth: 3)
                    .frame(width: 280, height: 160)
                    .allowsHitTesting(false)
            } else {
                ContentUnavailableView(
                    "Caméra indisponible",
                    systemImage: "barcode.viewfinder",
                    description: Text("Saisis le code-barres à la main ci-dessous.")
                )
                .foregroundStyle(.white)
            }
        }
        .safeAreaInset(edge: .top) {
            HStack {
                Text("Scanner un produit").font(.headline).foregroundStyle(.white)
                Spacer()
                Button("Fermer", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
            }
            .padding(.horizontal)
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                TextField("Ou tape le code (EAN)", text: $manual)
                    .keyboardType(.numberPad)
                    .focused($typing)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .glassEffect(.regular, in: .capsule)
                Button("Valider") { onCode(manual.filter(\.isNumber)) }
                    .buttonStyle(.glassProminent)
                    .disabled(manual.filter(\.isNumber).count < 8)
            }
            .padding()
        }
        .onAppear { if !cameraAvailable { typing = true } }
    }
}

private struct DataScanner: UIViewControllerRepresentable {
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        context.coordinator.onCode = onCode
        if !vc.isScanning { try? vc.startScanning() }
    }

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) {
        vc.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCode: (String) -> Void
        private var done = false

        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in items {
                if case .barcode(let b) = item, let code = b.payloadStringValue?.filter(\.isNumber), code.count >= 8 {
                    done = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    scanner.stopScanning()
                    onCode(code)
                    return
                }
            }
        }
    }
}
