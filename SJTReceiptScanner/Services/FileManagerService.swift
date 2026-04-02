import Foundation
import UIKit

/// Manages local file storage for receipts, images, and expense log
class FileManagerService {
    static let shared = FileManagerService()

    private let fm = FileManager.default

    /// App's Documents directory
    private var documentsDir: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    /// Directory for scanned images (before PDF conversion)
    var scansDir: URL {
        let url = documentsDir.appendingPathComponent("Scans")
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Directory for generated PDFs
    var pdfsDir: URL {
        let url = documentsDir.appendingPathComponent("PDFs")
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Directory for filed receipts (local mirror of Dropbox structure)
    var filedDir: URL {
        let url = documentsDir.appendingPathComponent("Filed")
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Path to the local expense log CSV
    var expenseLogURL: URL {
        documentsDir.appendingPathComponent("Expense_Log.csv")
    }

    /// Path to the receipt database
    var receiptDatabaseURL: URL {
        documentsDir.appendingPathComponent("receipts.json")
    }

    // MARK: - Image Storage

    /// Save a scanned image, returns the filename
    func saveImage(_ image: UIImage, receiptId: UUID, pageIndex: Int) throws -> String {
        let filename = "\(receiptId.uuidString)_\(pageIndex).jpg"
        let url = scansDir.appendingPathComponent(filename)
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            throw FileError.imageConversionFailed
        }
        try data.write(to: url)
        return filename
    }

    /// Load a scanned image
    func loadImage(filename: String) -> UIImage? {
        let url = scansDir.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    // MARK: - PDF Filing

    /// Move a PDF to the correct local folder (mirroring Dropbox structure)
    func filePDF(at sourceURL: URL, toFolder relativePath: String, filename: String) throws -> URL {
        let destFolder = filedDir.appendingPathComponent(relativePath)
        try fm.createDirectory(at: destFolder, withIntermediateDirectories: true)

        let destURL = destFolder.appendingPathComponent(filename)
        if fm.fileExists(atPath: destURL.path) {
            try fm.removeItem(at: destURL)
        }
        try fm.copyItem(at: sourceURL, to: destURL)
        return destURL
    }

    // MARK: - Expense Log CSV

    /// Append an entry to the expense log CSV
    func appendToExpenseLog(_ entry: ExpenseEntry) throws {
        let url = expenseLogURL
        var csvContent: String

        if fm.fileExists(atPath: url.path) {
            csvContent = try String(contentsOf: url, encoding: .utf8)
            if !csvContent.hasSuffix("\n") { csvContent += "\n" }
        } else {
            csvContent = ExpenseEntry.csvHeader + "\n"
        }

        csvContent += entry.csvRow + "\n"
        try csvContent.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Rebuild the entire CSV from the current receipt database
    func rebuildExpenseLog(from receipts: [Receipt], properties: [Property]) throws {
        var csvContent = ExpenseEntry.csvHeader + "\n"

        for receipt in receipts where receipt.status == .filed {
            let entry = ExpenseEntry(from: receipt, properties: properties)
            csvContent += entry.csvRow + "\n"
        }

        try csvContent.write(to: expenseLogURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Receipt Database

    /// Save all receipts
    func saveReceipts(_ receipts: [Receipt]) throws {
        let data = try JSONEncoder().encode(receipts)
        try data.write(to: receiptDatabaseURL)
    }

    /// Load all receipts
    func loadReceipts() -> [Receipt] {
        guard let data = try? Data(contentsOf: receiptDatabaseURL),
              let receipts = try? JSONDecoder().decode([Receipt].self, from: data)
        else { return [] }
        return receipts
    }

    // MARK: - Dropbox Path

    /// Get the full Dropbox path for a receipt
    func dropboxPath(basePath: String, relativeFolderPath: String, filename: String) -> String {
        "\(basePath)/\(relativeFolderPath)/\(filename)"
    }

    // MARK: - Cleanup

    /// Remove temporary scan images after PDF is created
    func cleanupScans(for receiptId: UUID) {
        let prefix = receiptId.uuidString
        if let contents = try? fm.contentsOfDirectory(at: scansDir, includingPropertiesForKeys: nil) {
            for url in contents where url.lastPathComponent.hasPrefix(prefix) {
                try? fm.removeItem(at: url)
            }
        }
    }
}

enum FileError: LocalizedError {
    case imageConversionFailed
    case directoryCreationFailed

    var errorDescription: String? {
        switch self {
        case .imageConversionFailed: return "Failed to convert image to JPEG"
        case .directoryCreationFailed: return "Failed to create directory"
        }
    }
}
