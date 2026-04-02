import SwiftUI

/// Review and edit extracted receipt data before filing
struct ReceiptReviewView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var processor: ReceiptProcessor
    @Environment(\.dismiss) var dismiss

    @State var receipt: Receipt
    @State private var amountText: String = ""
    @State private var principalText: String = ""
    @State private var interestText: String = ""
    @State private var selectedPropertyId: UUID?
    @State private var selectedCategory: ExpenseCategory = .repairs
    @State private var isOverhead = false
    @State private var selectedOverheadCategory: OverheadCategory = .overhead
    @State private var isFiling = false
    @State private var filedSuccessfully = false
    @State private var filedPDFURL: URL?
    @State private var targetFolderPath: String?
    @State private var showShareSheet = false
    @State private var errorMessage: String?
    @State private var dropboxStatus: String?

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Post-Filing Success View
                if filedSuccessfully {
                    Section {
                        Label("Receipt Filed!", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                    }

                    Section("Saved As") {
                        Text(receipt.standardFileName)
                            .font(.caption)
                            .textSelection(.enabled)
                    }

                    if let path = targetFolderPath {
                        Section("Save to this Dropbox folder") {
                            Text(path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }

                    Section("Next Steps") {
                        Button {
                            showShareSheet = true
                        } label: {
                            Label("Save PDF to Dropbox / Files", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }

                        Button {
                            dismiss()
                        } label: {
                            Label("Done", systemImage: "checkmark")
                                .frame(maxWidth: .infinity)
                        }
                    }

                    if let dbStatus = dropboxStatus {
                        Section("Dropbox") {
                            if dbStatus.starts(with: "Uploaded") {
                                Label(dbStatus, systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                            } else {
                                Label(dbStatus, systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                    .font(.caption)
                            }
                        }
                    }

                    Section("Logged to CSV") {
                        Text("Entry added to expense log. Export from Settings > Export CSV.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    // MARK: - Scanned Image Preview
                    if let firstImage = receipt.imageFileNames.first,
                       let image = FileManagerService.shared.loadImage(filename: firstImage) {
                        Section {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    // MARK: - Extracted Data
                    Section("Receipt Details") {
                        TextField("Vendor", text: $receipt.vendor)
                            .autocapitalization(.words)

                        HStack {
                            Text("$")
                            TextField("Amount", text: $amountText)
                                .keyboardType(.decimalPad)
                        }

                        DatePicker("Date",
                                   selection: Binding(
                                       get: { receipt.expenseDate ?? Date() },
                                       set: { receipt.expenseDate = $0 }
                                   ),
                                   displayedComponents: .date)

                        TextField("Description", text: $receipt.description)
                    }

                    // MARK: - Mortgage Split
                    if receipt.hasMortgageSplit || selectedCategory == .mortgageInterest {
                        Section("Mortgage Payment Split") {
                            HStack {
                                Text("Principal $")
                                TextField("0.00", text: $principalText)
                                    .keyboardType(.decimalPad)
                            }
                            HStack {
                                Text("Interest $")
                                TextField("0.00", text: $interestText)
                                    .keyboardType(.decimalPad)
                            }
                        }
                    }

                    // MARK: - Filing Destination
                    Section("File To") {
                        Toggle("Overhead Expense", isOn: $isOverhead)

                        if isOverhead {
                            Picker("Category", selection: $selectedOverheadCategory) {
                                ForEach(OverheadCategory.allCases) { cat in
                                    Text(cat.rawValue).tag(cat)
                                }
                            }
                        } else {
                            Picker("Property", selection: $selectedPropertyId) {
                                Text("Select Property").tag(nil as UUID?)
                                ForEach(settings.properties.filter { $0.isActive }) { property in
                                    Text(property.name).tag(property.id as UUID?)
                                }
                            }

                            Picker("Category", selection: $selectedCategory) {
                                ForEach(ExpenseCategory.allCases) { cat in
                                    Text(cat.rawValue).tag(cat)
                                }
                            }
                        }
                    }

                    // MARK: - Preview
                    Section("Will be saved as") {
                        Text(previewFilename)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let path = previewFolderPath {
                            Text("Dropbox: .../\(path)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // MARK: - OCR Debug
                    if let ocrText = receipt.ocrText, !ocrText.isEmpty {
                        Section("Raw OCR Text") {
                            Text(ocrText.prefix(500) + (ocrText.count > 500 ? "..." : ""))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // MARK: - Confidence
                    Section {
                        HStack {
                            Text("OCR Confidence")
                            Spacer()
                            Text(String(format: "%.0f%%", (receipt.ocrConfidence ?? 0) * 100))
                                .foregroundStyle(confidenceColor)
                        }
                        if receipt.usedClaudeAPI {
                            Label("AI assisted", systemImage: "sparkles")
                                .font(.caption)
                                .foregroundStyle(.purple)
                        }
                    }
                }
            }
            .navigationTitle(filedSuccessfully ? "Receipt Filed" : "Review Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !filedSuccessfully {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("File Receipt") { fileReceipt() }
                            .fontWeight(.semibold)
                            .disabled(isFiling || receipt.vendor.isEmpty)
                    }
                }
            }
            .onAppear { populateFields() }
            .sheet(isPresented: $showShareSheet) {
                if let url = filedPDFURL {
                    ShareSheetView(items: [url])
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .overlay {
                if isFiling {
                    ProgressView("Filing receipt...")
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // MARK: - Helpers

    private var previewFilename: String {
        var r = receipt
        r.amount = Double(amountText) ?? 0
        return r.standardFileName
    }

    private var previewFolderPath: String? {
        buildDestination()?.folderPath(properties: settings.properties)
    }

    private var confidenceColor: Color {
        let c = receipt.ocrConfidence ?? 0
        if c >= 0.8 { return .green }
        if c >= 0.5 { return .orange }
        return .red
    }

    private func populateFields() {
        amountText = receipt.amount > 0 ? String(format: "%.2f", receipt.amount) : ""
        principalText = receipt.principal.map { String(format: "%.2f", $0) } ?? ""
        interestText = receipt.interest.map { String(format: "%.2f", $0) } ?? ""

        // Populate destination from receipt
        if let dest = receipt.destination {
            switch dest {
            case .property(let propId, let cat):
                selectedPropertyId = propId
                selectedCategory = cat
                isOverhead = false
            case .overhead(let cat):
                selectedOverheadCategory = cat
                isOverhead = true
            }
        }
    }

    private func buildDestination() -> ExpenseDestination? {
        if isOverhead {
            return .overhead(category: selectedOverheadCategory)
        } else if let propId = selectedPropertyId {
            return .property(propertyId: propId, category: selectedCategory)
        }
        return nil
    }

    private func fileReceipt() {
        // Update receipt from form fields
        receipt.amount = Double(amountText) ?? 0
        receipt.principal = Double(principalText)
        receipt.interest = Double(interestText)
        receipt.destination = buildDestination()

        guard receipt.destination != nil else {
            errorMessage = "Please select a property or overhead category"
            return
        }

        isFiling = true
        Task {
            do {
                receipt = try await processor.fileReceipt(receipt)

                // Get the PDF URL for sharing
                let pdfFilename = receipt.standardFileName
                let filedDir = FileManagerService.shared.filedDir
                if let folderPath = receipt.destination?.folderPath(properties: settings.properties) {
                    let localPDF = filedDir.appendingPathComponent(folderPath).appendingPathComponent(pdfFilename)
                    if FileManager.default.fileExists(atPath: localPDF.path) {
                        filedPDFURL = localPDF
                    } else {
                        // Fall back to PDFs dir
                        let altPDF = FileManagerService.shared.pdfsDir.appendingPathComponent(pdfFilename)
                        if FileManager.default.fileExists(atPath: altPDF.path) {
                            filedPDFURL = altPDF
                        }
                    }
                    // Build the full Dropbox path for display
                    targetFolderPath = "\(settings.dropboxBasePath)/\(folderPath)"
                }

                // Capture Dropbox result
                dropboxStatus = processor.lastDropboxResult

                isFiling = false
                filedSuccessfully = true
            } catch {
                isFiling = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
