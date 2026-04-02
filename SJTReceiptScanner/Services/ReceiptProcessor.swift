import Foundation
import UIKit

/// Orchestrates the full receipt processing pipeline
@MainActor
class ReceiptProcessor: ObservableObject {
    @Published var currentReceipt: Receipt?
    @Published var isProcessing = false
    @Published var processingStep = ""
    @Published var errorMessage: String?
    @Published var lastDropboxResult: String?

    private let ocrService = OCRService()
    private let parser = ReceiptParser()
    private let pdfService = PDFService()
    private let fileManager = FileManagerService.shared

    var aiService: AIServiceProtocol?
    var dropboxService: DropboxService?
    var settings: AppSettings?

    /// Rebuild the AI service when provider or key changes
    func refreshAIService() {
        guard let settings else { aiService = nil; return }
        aiService = AIServiceFactory.create(provider: settings.aiProvider, apiKey: settings.activeAPIKey)
    }

    // MARK: - Process Scanned Images

    /// Full pipeline: save images -> OCR -> parse -> (Claude fallback) -> return receipt
    func processImages(_ images: [UIImage]) async {
        isProcessing = true
        errorMessage = nil
        let receiptId = UUID()
        var receipt = Receipt(id: receiptId)

        do {
            // Step 1: Save images
            processingStep = "Saving scans..."
            var imageFilenames: [String] = []
            for (i, image) in images.enumerated() {
                let filename = try fileManager.saveImage(image, receiptId: receiptId, pageIndex: i)
                imageFilenames.append(filename)
            }
            receipt.imageFileNames = imageFilenames

            // Step 2: OCR with Apple Vision
            processingStep = "Reading text..."
            var allText = ""
            var totalConfidence: Double = 0

            for image in images {
                let (text, observations) = try await ocrService.recognizeText(in: image)
                allText += text + "\n"
                totalConfidence += ocrService.averageConfidence(observations)
            }
            receipt.ocrText = allText
            receipt.ocrConfidence = totalConfidence / Double(images.count)

            // Step 3: Parse extracted text
            processingStep = "Extracting data..."
            let parsed = parser.parse(ocrText: allText)
            receipt.amount = parsed.amount ?? 0
            receipt.vendor = parsed.vendor ?? ""
            receipt.expenseDate = parsed.date
            receipt.description = parsed.description ?? ""
            receipt.principal = parsed.principal
            receipt.interest = parsed.interest

            // Step 4: AI fallback if OCR confidence is low or fields missing
            let needsAI = receipt.ocrConfidence ?? 0 < 0.7 ||
                          receipt.vendor.isEmpty ||
                          receipt.amount == 0

            if needsAI, let aiService, settings?.useAIFallback == true {
                let providerName = settings?.aiProvider.displayName ?? "AI"
                processingStep = "Asking \(providerName) for help..."
                do {
                    let analysis = try await aiService.analyzeReceipt(
                        image: images.first!,
                        ocrText: allText,
                        properties: settings?.properties ?? []
                    )
                    // Fill in missing fields from AI
                    if receipt.vendor.isEmpty { receipt.vendor = analysis.vendor ?? "" }
                    if receipt.amount == 0 { receipt.amount = analysis.amount ?? 0 }
                    if receipt.description.isEmpty { receipt.description = analysis.description ?? "" }
                    if receipt.expenseDate == nil, let dateStr = analysis.date {
                        let fmt = DateFormatter()
                        fmt.dateFormat = "MM-dd-yyyy"
                        receipt.expenseDate = fmt.date(from: dateStr)
                    }
                    if receipt.principal == nil { receipt.principal = analysis.principal }
                    if receipt.interest == nil { receipt.interest = analysis.interest }

                    // Suggest destination
                    if let propName = analysis.suggestedProperty,
                       let property = settings?.properties.first(where: { $0.name == propName }),
                       let catStr = analysis.suggestedCategory,
                       let category = ExpenseCategory(rawValue: catStr) {
                        receipt.destination = .property(propertyId: property.id, category: category)
                    } else if let catStr = analysis.suggestedCategory,
                              let overhead = OverheadCategory(rawValue: catStr) {
                        receipt.destination = .overhead(category: overhead)
                    }

                    receipt.usedClaudeAPI = true
                } catch {
                    // AI failed, continue with Vision-only results
                    print("AI fallback failed: \(error)")
                }
            }

            // Step 5: Try auto-suggest category from parsed text if Claude didn't
            if receipt.destination == nil, settings?.autoSuggestCategory == true {
                receipt.destination = autoSuggestDestination(for: receipt)
            }

            receipt.status = .processing
            currentReceipt = receipt

        } catch {
            errorMessage = error.localizedDescription
            receipt.status = .error
            currentReceipt = receipt
        }

        isProcessing = false
        processingStep = ""
    }

    // MARK: - File Receipt

    /// Create PDF, file it, and log the expense
    func fileReceipt(_ receipt: Receipt) async throws -> Receipt {
        var receipt = receipt
        let properties = settings?.properties ?? []

        // Create PDF
        let images = receipt.imageFileNames.compactMap { fileManager.loadImage(filename: $0) }
        guard !images.isEmpty else { throw FileError.imageConversionFailed }

        let pdfURL = try pdfService.createPDF(from: images, filename: receipt.standardFileName)
        receipt.pdfFileName = receipt.standardFileName

        // File to local folder
        if let destination = receipt.destination,
           let folderPath = destination.folderPath(properties: properties) {
            _ = try fileManager.filePDF(at: pdfURL, toFolder: folderPath, filename: receipt.standardFileName)
        }

        // Upload to Dropbox if connected
        print("[Filing] dropboxService exists: \(dropboxService != nil)")
        print("[Filing] isAuthenticated: \(dropboxService?.isAuthenticated ?? false)")
        print("[Filing] destination: \(String(describing: receipt.destination))")
        print("[Filing] basePath: '\(settings?.dropboxBasePath ?? "nil")'")
        if let dropbox = dropboxService, dropbox.isAuthenticated,
           let destination = receipt.destination {
            do {
                let pdfData = try Data(contentsOf: pdfURL)
                let basePath = settings?.dropboxBasePath ?? ""
                let taxYear = settings?.taxYear ?? Calendar.current.component(.year, from: Date())
                let uploadedPath = try await dropbox.fileReceiptToDropbox(
                    pdfData: pdfData,
                    filename: receipt.standardFileName,
                    destination: destination,
                    properties: properties,
                    basePath: basePath,
                    taxYear: taxYear
                )
                print("[Dropbox] Upload succeeded: \(uploadedPath)")
                lastDropboxResult = "Uploaded to Dropbox"
            } catch {
                print("[Dropbox] Upload FAILED: \(error.localizedDescription)")
                lastDropboxResult = "Dropbox upload failed: \(error.localizedDescription)"
            }
        } else if dropboxService != nil && !(dropboxService?.isAuthenticated ?? false) {
            lastDropboxResult = "Not connected to Dropbox"
        }

        // Log to CSV
        let entry = ExpenseEntry(from: receipt, properties: properties)
        try fileManager.appendToExpenseLog(entry)

        // Upload CSV to Dropbox (keeps it synced after each filing)
        if let dropbox = dropboxService, dropbox.isAuthenticated {
            let basePath = settings?.dropboxBasePath ?? ""
            let csvPath = basePath.hasPrefix("/") ? basePath : "/\(basePath)"
            let csvDropboxPath = "\(csvPath)/\(settings?.fullCSVFileName ?? "Expense_Log.csv")"
            if let csvData = try? Data(contentsOf: fileManager.expenseLogURL) {
                do {
                    try await dropbox.uploadFile(data: csvData, dropboxPath: csvDropboxPath)
                    print("[Dropbox] CSV synced to \(csvDropboxPath)")
                } catch {
                    print("[Dropbox] CSV sync failed: \(error.localizedDescription)")
                }
            }
        }

        // Update status
        receipt.status = .filed

        // Save receipt database
        var allReceipts = fileManager.loadReceipts()
        if let idx = allReceipts.firstIndex(where: { $0.id == receipt.id }) {
            allReceipts[idx] = receipt
        } else {
            allReceipts.append(receipt)
        }
        try fileManager.saveReceipts(allReceipts)

        // Cleanup temp images
        fileManager.cleanupScans(for: receipt.id)

        return receipt
    }

    // MARK: - Auto-suggest

    private func autoSuggestDestination(for receipt: Receipt) -> ExpenseDestination? {
        let vendor = receipt.vendor.lowercased()
        let desc = receipt.description.lowercased()
        let text = (receipt.ocrText ?? "").lowercased()
        let properties = settings?.properties ?? []

        // Mortgage keywords -> find property
        if receipt.hasMortgageSplit || desc.contains("mortgage") {
            if let property = matchProperty(in: text, properties: properties) {
                return .property(propertyId: property.id, category: .mortgageInterest)
            }
        }

        // Overhead keywords
        if vendor.contains("apple") || vendor.contains("replit") || vendor.contains("chatgpt") ||
           desc.contains("subscription") || desc.contains("software") {
            return .overhead(category: .overhead)
        }
        if vendor.contains("akb") || desc.contains("bookkeeping") {
            return .overhead(category: .akb)
        }

        // Property-specific keywords
        if let property = matchProperty(in: text, properties: properties) {
            // Determine category
            var category: ExpenseCategory = .repairs

            if vendor.contains("water") || desc.contains("water") || desc.contains("electric") ||
               desc.contains("utility") || desc.contains("garbage") {
                category = .utilities
            } else if vendor.contains("lawn") || vendor.contains("mozingo") || desc.contains("lawn") {
                category = .cleaningAndMaintenance
            } else if desc.contains("tax") || vendor.contains("county") {
                category = .taxes
            } else if desc.contains("insurance") || vendor.contains("nreig") {
                category = .insurance
            } else if vendor.contains("walmart") || vendor.contains("home depot") ||
                      vendor.contains("lowes") || vendor.contains("amazon") {
                category = .supplies
            }

            return .property(propertyId: property.id, category: category)
        }

        return nil
    }

    /// Try to match a property from the OCR text
    private func matchProperty(in text: String, properties: [Property]) -> Property? {
        let lower = text.lowercased()
        // Try matching property names (addresses)
        for property in properties {
            let name = property.name.lowercased()
            // Match key parts of the property name
            let parts = name.components(separatedBy: " ").filter { $0.count > 2 }
            let matchCount = parts.filter { lower.contains($0) }.count
            if matchCount >= 2 || (parts.count == 1 && matchCount == 1) {
                return property
            }
        }
        return nil
    }
}
