import SwiftUI
import PDFKit

/// Simple document save view — bypasses receipt parsing entirely.
/// User scans a document, names it, and saves/shares as PDF.
struct DocumentSaveView: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    let images: [UIImage]

    @State private var filename = ""
    @State private var isSaving = false
    @State private var savedMessage: String?
    @State private var errorMessage: String?
    @State private var selectedPageIndex = 0
    @State private var pdfURLToShare: URL?
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            Form {
                // Preview
                Section {
                    TabView(selection: $selectedPageIndex) {
                        ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .automatic))
                    .frame(height: 350)
                } header: {
                    Text("\(images.count) page\(images.count == 1 ? "" : "s") scanned")
                }

                // Filename
                Section {
                    TextField("Document name", text: $filename)
                        .autocapitalization(.words)
                        .autocorrectionDisabled()
                } header: {
                    Text("Filename")
                } footer: {
                    if !filename.isEmpty {
                        Text("Will be saved as: \(sanitizedFilename).pdf")
                            .foregroundStyle(.secondary)
                    }
                }

                // Actions
                Section {
                    // Share — opens iOS share sheet (Save to Files, Dropbox, AirDrop, etc.)
                    Button {
                        preparePDFAndShare()
                    } label: {
                        Label("Share / Save to Files", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(filename.isEmpty || isSaving)

                    // Save locally inside the app
                    Button {
                        saveDocumentLocally()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("Save to App Storage", systemImage: "internaldrive")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(filename.isEmpty || isSaving)
                } header: {
                    Text("Save Options")
                } footer: {
                    Text("\"Share / Save to Files\" lets you save to Files app, Dropbox, AirDrop, or any other app. \"Save to App Storage\" keeps a copy inside this app.")
                }

                if let msg = savedMessage {
                    Section {
                        Label(msg, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                if let err = errorMessage {
                    Section {
                        Label(err, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Save Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = pdfURLToShare {
                    ShareSheetView(items: [url])
                }
            }
        }
    }

    private var sanitizedFilename: String {
        filename
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)
    }

    private func generatePDFURL() -> URL? {
        let pdfService = PDFService()
        return try? pdfService.createPDF(from: images, filename: "\(sanitizedFilename).pdf")
    }

    private func preparePDFAndShare() {
        guard !filename.isEmpty else { return }
        errorMessage = nil

        // Generate PDF to temp location
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(sanitizedFilename).pdf")

        if let sourceURL = generatePDFURL(), let data = try? Data(contentsOf: sourceURL) {
            try? data.write(to: tempURL)
            pdfURLToShare = tempURL
            showShareSheet = true
        } else {
            errorMessage = "Failed to generate PDF"
        }
    }

    private func saveDocumentLocally() {
        guard !filename.isEmpty else { return }
        isSaving = true
        errorMessage = nil
        savedMessage = nil

        Task {
            do {
                let pdfService = PDFService()
                let pdfFilename = "\(sanitizedFilename).pdf"
                let pdfURL = try pdfService.createPDF(from: images, filename: pdfFilename)

                // Save to app's local Documents/Filed/Documents/ folder
                let fileManager = FileManagerService.shared
                let docsFolder = "Documents"
                _ = try fileManager.filePDF(at: pdfURL, toFolder: docsFolder, filename: pdfFilename)

                await MainActor.run {
                    savedMessage = "Saved \(pdfFilename) to app storage"
                    isSaving = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }
}

// MARK: - Share Sheet (UIKit wrapper for SwiftUI)

/// Presents UIActivityViewController as a SwiftUI sheet — avoids the "already presenting" crash.
struct ShareSheetView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
