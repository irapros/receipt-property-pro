import Foundation
import UIKit

/// Processing state of a scanned receipt
enum ReceiptStatus: String, Codable {
    case scanned        // Image captured, not yet OCR'd
    case processing     // OCR in progress
    case reviewed       // User has reviewed extracted data
    case filed          // Saved to destination folder and logged
    case error          // Something went wrong
}

/// A scanned receipt with extracted data
struct Receipt: Identifiable, Codable {
    let id: UUID
    var status: ReceiptStatus
    var scanDate: Date

    // Extracted fields
    var vendor: String
    var amount: Double
    var expenseDate: Date?
    var description: String
    var principal: Double?
    var interest: Double?

    // Filing destination
    var destination: ExpenseDestination?

    // Raw OCR text for reference
    var ocrText: String?

    // Image data (stored separately, referenced by ID)
    var imageFileNames: [String]

    // Generated PDF filename
    var pdfFileName: String?

    // Confidence scores from OCR
    var ocrConfidence: Double?
    var usedClaudeAPI: Bool

    init(
        id: UUID = UUID(),
        scanDate: Date = Date(),
        imageFileNames: [String] = []
    ) {
        self.id = id
        self.status = .scanned
        self.scanDate = scanDate
        self.vendor = ""
        self.amount = 0
        self.description = ""
        self.imageFileNames = imageFileNames
        self.usedClaudeAPI = false
    }

    /// Generate the standard PDF filename: $Amount_Vendor_Description.pdf
    var standardFileName: String {
        let amountStr: String
        if amount == floor(amount) {
            amountStr = String(format: "%.0f", amount)
        } else {
            amountStr = String(format: "%.2f", amount)
        }
        let vendorClean = vendor
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "&", with: "And")
            .replacingOccurrences(of: "/", with: "-")
            .prefix(30)
        let descClean = description
            .replacingOccurrences(of: "/", with: "-")
            .prefix(40)
        return "$\(amountStr)_\(vendorClean)_\(descClean).pdf"
    }

    /// Whether this receipt has a mortgage principal/interest split
    var hasMortgageSplit: Bool {
        principal != nil && interest != nil
    }
}

/// Row in the expense tracker CSV/Excel
struct ExpenseEntry: Codable {
    var date: String          // MM-DD-YYYY
    var vendor: String
    var amount: Double
    var principal: Double?
    var interest: Double?
    var category: String      // Folder path like "Property Specific Files/1845 Tara/Repairs"
    var description: String
    var receiptFilename: String

    init(from receipt: Receipt, properties: [Property]) {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd-yyyy"
        self.date = formatter.string(from: receipt.expenseDate ?? receipt.scanDate)
        self.vendor = receipt.vendor
        self.amount = receipt.amount
        self.principal = receipt.principal
        self.interest = receipt.interest
        self.category = receipt.destination?.folderPath(properties: properties) ?? ""
        self.description = receipt.description
        self.receiptFilename = receipt.standardFileName
    }

    /// CSV header row
    static var csvHeader: String {
        "Date,Vendor,Amount,Principal,Interest,Category,Description,Receipt Filename"
    }

    /// CSV row
    var csvRow: String {
        let p = principal.map { String(format: "%.2f", $0) } ?? ""
        let i = interest.map { String(format: "%.2f", $0) } ?? ""
        let escapedVendor = vendor.contains(",") ? "\"\(vendor)\"" : vendor
        let escapedDesc = description.contains(",") ? "\"\(description)\"" : description
        let escapedCategory = category.contains(",") ? "\"\(category)\"" : category
        let escapedFilename = receiptFilename.contains(",") ? "\"\(receiptFilename)\"" : receiptFilename
        return "\(date),\(escapedVendor),\(String(format: "%.2f", amount)),\(p),\(i),\(escapedCategory),\(escapedDesc),\(escapedFilename)"
    }
}
