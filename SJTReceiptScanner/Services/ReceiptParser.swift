import Foundation

/// Parses OCR text to extract structured receipt data
class ReceiptParser {

    /// Extract all receipt fields from OCR text
    func parse(ocrText: String) -> ParsedReceipt {
        var result = ParsedReceipt()
        let text = ocrText.lowercased()
        let originalText = ocrText

        result.vendor = extractVendor(from: originalText)
        result.amount = extractAmount(from: originalText)
        result.date = extractDate(from: originalText)
        result.description = extractDescription(from: originalText, vendor: result.vendor)
        result.isMortgage = detectMortgage(text: text)

        if result.isMortgage {
            let split = extractMortgageSplit(from: originalText)
            result.principal = split.principal
            result.interest = split.interest
        }

        return result
    }

    // MARK: - Amount Extraction

    private func extractAmount(from text: String) -> Double? {
        let lines = text.components(separatedBy: "\n")

        // Strategy 1: Look for labeled total lines (most reliable)
        // These patterns match "TOTAL: 123.08", "INVOICE TOTAL: 123.08", "AMOUNT DUE: 123.08", etc.
        let labeledTotalPatterns = [
            #"(?i)invoice\s*(?:\d+\s+)?total\s*[:.]?\s*\$?([\d,]+\.\d{2})"#,
            #"(?i)(?:order|transaction|grand|net)\s*total\s*[:.]?\s*\$?([\d,]+\.\d{2})"#,
            #"(?i)(?:amount\s*(?:due|paid|charged|tendered))\s*[:.]?\s*\$?([\d,]+\.\d{2})"#,
            #"(?i)(?:balance\s*due|payment\s*amount|total\s*charged)\s*[:.]?\s*\$?([\d,]+\.\d{2})"#,
            #"(?i)(?:total\s*amount)\s*[:.]?\s*\$?([\d,]+\.\d{2})"#,
        ]

        for pattern in labeledTotalPatterns {
            if let match = firstMatch(pattern: pattern, in: text),
               let amount = parseDouble(match), amount > 0 {
                return amount
            }
        }

        // Strategy 2: Look for "TOTAL" on a line with a number at the end
        // Handles: "TOTAL    123.08" or "TOTAL TAX 10.68"
        // We want the first "TOTAL" that is NOT "SUBTOTAL", "TOTAL TAX", "TOTAL SAVINGS"
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()

            // Skip subtotal, tax, savings, discount lines
            if lower.contains("subtotal") || lower.contains("total tax") ||
               lower.contains("total saving") || lower.contains("total discount") ||
               lower.contains("# of items") {
                continue
            }

            // Match lines that have "total" followed by a number
            if lower.contains("total") {
                if let match = firstMatch(pattern: #"([\d,]+\.\d{2})\s*$"#, in: trimmed),
                   let amount = parseDouble(match), amount > 0 {
                    return amount
                }
            }
        }

        // Strategy 3: Look for AMOUNT on payment confirmation lines
        // Handles: "MLRCC: XXXX9630 AMOUNT: 123.08 AUTHCD: 001150"
        if let match = firstMatch(pattern: #"(?i)amount\s*[:.]?\s*\$?([\d,]+\.\d{2})"#, in: text),
           let amount = parseDouble(match), amount > 0 {
            return amount
        }

        // Strategy 4: Look for dollar sign amounts, but skip savings/discount lines
        var dollarAmounts: [Double] = []
        for line in lines {
            let lower = line.lowercased()
            if lower.contains("saving") || lower.contains("discount") || lower.contains("coupon") ||
               lower.contains("off") || lower.contains("rewards") {
                continue
            }
            let matches = allMatches(pattern: #"\$\s*([\d,]+\.\d{2})"#, in: line)
            for m in matches {
                if let val = parseDouble(m), val > 0 {
                    dollarAmounts.append(val)
                }
            }
        }
        if let largest = dollarAmounts.sorted(by: >).first {
            return largest
        }

        // Strategy 5: Last resort — find the largest standalone number that looks like a total
        // Look at last ~15 lines where totals usually appear
        let bottomLines = lines.suffix(15)
        var candidates: [Double] = []
        for line in bottomLines {
            let lower = line.lowercased()
            if lower.contains("saving") || lower.contains("discount") || lower.contains("items purchased") {
                continue
            }
            let matches = allMatches(pattern: #"([\d,]+\.\d{2})"#, in: line)
            for m in matches {
                if let val = parseDouble(m), val > 1 {
                    candidates.append(val)
                }
            }
        }
        return candidates.sorted(by: >).first
    }

    // MARK: - Vendor Extraction

    private func extractVendor(from text: String) -> String? {
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !lines.isEmpty else { return nil }

        // Known vendor patterns
        let knownVendors: [(pattern: String, name: String)] = [
            ("walmart", "Walmart"),
            ("home depot", "Home Depot"),
            ("lowes|lowe'?s", "Lowes"),
            ("amazon", "Amazon"),
            ("apple\\.com|apple store", "Apple"),
            ("pennymac", "PennyMac"),
            ("shellpoint", "Shellpoint"),
            ("newrez", "NewRez"),
            ("fay servicing", "Fay Servicing"),
            ("amerifirst", "Amerifirst Bank"),
            ("merchants.*farmers", "Merchants & Farmers Bank"),
            ("caldwell", "Caldwell And Sons"),
            ("fhs homes", "FHS Homes"),
            ("mozingo", "Mozingo Lawn Care"),
            ("prattville.*water", "Prattville Water Works"),
            ("replit", "Replit"),
            ("nreig", "NREIG"),
            ("akb", "AKB"),
            ("verizon", "Verizon"),
            ("at&t|at ?& ?t", "AT&T"),
            ("harbor freight", "Harbor Freight"),
            ("tractor supply", "Tractor Supply"),
            ("sherwin.?williams", "Sherwin-Williams"),
            ("ace hardware", "Ace Hardware"),
            ("menards", "Menards"),
        ]

        let lowerText = text.lowercased()
        for vendor in knownVendors {
            if lowerText.range(of: vendor.pattern, options: .regularExpression) != nil {
                return vendor.name
            }
        }

        // Heuristic: first non-empty line that looks like a business name
        // Skip very short lines, URLs, and header-like text
        for line in lines.prefix(8) {
            let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = clean.lowercased()
            if clean.count > 2 && clean.count < 50 &&
               !clean.contains("$") && !clean.contains("@") &&
               !lower.contains("receipt") && !lower.contains("invoice") &&
               !lower.contains("learn more") && !lower.contains("http") &&
               !lower.contains("www.") && !lower.contains(".com") &&
               !lower.starts(with: "-") && !lower.starts(with: "=") &&
               clean.rangeOfCharacter(from: .letters) != nil {
                return clean
            }
        }

        return nil
    }

    // MARK: - Date Extraction

    private func extractDate(from text: String) -> Date? {
        let datePatterns: [(pattern: String, format: String)] = [
            (#"(\d{1,2}/\d{1,2}/\d{4})"#, "M/d/yyyy"),
            (#"(\d{1,2}/\d{1,2}/\d{2})\b"#, "M/d/yy"),
            (#"(\d{1,2}-\d{1,2}-\d{4})"#, "M-d-yyyy"),
            (#"(\d{1,2}-\d{1,2}-\d{2})\b"#, "M-d-yy"),
            (#"(\d{4}-\d{2}-\d{2})"#, "yyyy-MM-dd"),
        ]

        for (pattern, format) in datePatterns {
            if let match = firstMatch(pattern: pattern, in: text) {
                let formatter = DateFormatter()
                formatter.dateFormat = format
                formatter.locale = Locale(identifier: "en_US_POSIX")
                if let date = formatter.date(from: match),
                   date > Calendar.current.date(byAdding: .year, value: -2, to: Date())! {
                    return date
                }
            }
        }

        // Try natural language dates: "February 17, 2026"
        let monthPattern = #"(?i)((?:january|february|march|april|may|june|july|august|september|october|november|december)\s+\d{1,2},?\s+\d{4})"#
        if let match = firstMatch(pattern: monthPattern, in: text) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            for format in ["MMMM d, yyyy", "MMMM d yyyy"] {
                formatter.dateFormat = format
                if let date = formatter.date(from: match) { return date }
            }
        }

        return nil
    }

    // MARK: - Description

    private func extractDescription(from text: String, vendor: String?) -> String? {
        let lower = text.lowercased()

        // Mortgage statements
        if detectMortgage(text: lower) {
            return "Mortgage Payment"
        }

        // Service invoices with labeled descriptions
        if let match = firstMatch(pattern: #"(?i)(?:description|service|memo|for)\s*[:]\s*(.{5,60})"#, in: text) {
            return match.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Property tax
        if lower.contains("property tax") || lower.contains("tax due") {
            return "Property Tax"
        }

        // Utility bills
        if lower.contains("water") && (lower.contains("sewer") || lower.contains("garbage")) {
            return "Water Sewer Garbage"
        }
        if lower.contains("electric") && !lower.contains("electrical") { return "Electric Bill" }

        // Lawn care
        if lower.contains("lawn care") || lower.contains("mowing") || lower.contains("yard") {
            return "Routine Lawn Care"
        }
        if lower.contains("plumbing") || lower.contains("drain") { return "Plumbing Repair" }
        if lower.contains("insurance") || lower.contains("premium") { return "Insurance" }

        // For retail stores, try to summarize what was bought
        if let vendorName = vendor?.lowercased() {
            if ["lowes", "home depot", "harbor freight", "ace hardware", "menards", "tractor supply"]
                .contains(where: { vendorName.contains($0) }) {
                return "Supplies"
            }
            if vendorName.contains("walmart") || vendorName.contains("amazon") {
                return "Supplies"
            }
        }

        return nil
    }

    // MARK: - Mortgage Detection

    private func detectMortgage(text: String) -> Bool {
        let mortgageKeywords = [
            "principal", "interest", "mortgage", "loan payment",
            "payment split", "escrow", "loan billing", "regular payment"
        ]
        let matches = mortgageKeywords.filter { text.contains($0) }
        return matches.count >= 2
    }

    // MARK: - Mortgage P&I Split

    private func extractMortgageSplit(from text: String) -> (principal: Double?, interest: Double?) {
        let principalPatterns = [
            #"(?i)principal\s*(?:paid|payment|split|due)?[:\s]*\$?([\d,]+\.?\d{0,2})"#,
            #"(?i)principal\s+payment\s+split\s+out\s+([\d,]+\.?\d{0,2})"#,
        ]
        let interestPatterns = [
            #"(?i)interest\s*(?:paid|payment|split|due)?[:\s]*\$?([\d,]+\.?\d{0,2})"#,
            #"(?i)interest\s+payment\s+split\s+out\s+([\d,]+\.?\d{0,2})"#,
        ]

        var principal: Double?
        var interest: Double?

        for p in principalPatterns {
            if let match = firstMatch(pattern: p, in: text), let val = parseDouble(match), val > 0 {
                principal = val
                break
            }
        }

        for p in interestPatterns {
            if let match = firstMatch(pattern: p, in: text), let val = parseDouble(match), val > 0 {
                interest = val
                break
            }
        }

        return (principal, interest)
    }

    // MARK: - Regex Helpers

    private func firstMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[captureRange])
    }

    private func allMatches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let captureRange = Range(match.range(at: 1), in: text)
            else { return nil }
            return String(text[captureRange])
        }
    }

    private func parseDouble(_ str: String) -> Double? {
        let cleaned = str.replacingOccurrences(of: ",", with: "")
        return Double(cleaned)
    }
}

/// Result of parsing OCR text
struct ParsedReceipt {
    var amount: Double?
    var vendor: String?
    var date: Date?
    var description: String?
    var principal: Double?
    var interest: Double?
    var isMortgage: Bool = false
}
