import Foundation
import UIKit

// MARK: - Shared Types

/// Result of AI receipt analysis (shared across all providers)
struct ReceiptAnalysis {
    var vendor: String?
    var amount: Double?
    var date: String?
    var description: String?
    var principal: Double?
    var interest: Double?
    var suggestedProperty: String?
    var suggestedCategory: String?
    var isMortgage: Bool
    var confidence: Double
}

/// Errors that any AI provider can throw
enum AIServiceError: LocalizedError {
    case noAPIKey
    case invalidImage
    case networkError(String)
    case apiError(statusCode: Int, message: String)
    case parseError
    case providerNotConfigured

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "API key not configured. Go to Settings to add it."
        case .invalidImage: return "Could not process image for AI analysis"
        case .networkError(let msg): return "Network error: \(msg)"
        case .apiError(let code, let msg): return "API error (\(code)): \(msg)"
        case .parseError: return "Could not parse AI response"
        case .providerNotConfigured: return "No AI provider selected. Go to Settings to choose one."
        }
    }
}

// MARK: - AI Service Protocol

/// Protocol that all AI providers implement
protocol AIServiceProtocol {
    /// Analyze a receipt image with optional OCR text context
    func analyzeReceipt(image: UIImage, ocrText: String?, properties: [Property]) async throws -> ReceiptAnalysis

    /// Text-only category suggestion (cheaper/faster)
    func suggestCategory(vendor: String, amount: Double, description: String, ocrText: String, properties: [Property]) async throws -> (propertyName: String?, category: String)
}

// MARK: - Factory

/// Creates the appropriate AI service based on provider selection
class AIServiceFactory {
    static func create(provider: AIProvider, apiKey: String) -> AIServiceProtocol? {
        guard provider != .none, !apiKey.isEmpty else { return nil }
        switch provider {
        case .none: return nil
        case .claude: return ClaudeAIService(apiKey: apiKey)
        case .openai: return OpenAIService(apiKey: apiKey)
        case .gemini: return GeminiAIService(apiKey: apiKey)
        }
    }
}

// MARK: - Shared Prompt Builder

/// Builds the analysis prompt shared across providers
struct AIPromptBuilder {
    static func receiptAnalysisPrompt(ocrText: String?, properties: [Property]) -> String {
        let propertyList = properties.map { $0.name }.joined(separator: ", ")
        let categories = ExpenseCategory.allCases.map { $0.rawValue }.joined(separator: ", ")

        var prompt = """
        Analyze this receipt/statement image and extract the following information as JSON:

        {
            "vendor": "Company or person name",
            "amount": 0.00,
            "date": "MM-DD-YYYY",
            "description": "Brief description of what was paid for",
            "principal": null,
            "interest": null,
            "suggested_property": "Property name or null if overhead",
            "suggested_category": "Category name",
            "is_mortgage": false,
            "confidence": 0.95
        }

        Available properties: \(propertyList)
        Available categories: \(categories)
        Also available: Overhead categories (AKB, Advertising, Cash, Overhead, Verizon)

        Rules:
        - For mortgage/loan statements, extract principal and interest from the payment split
        - If it's a business overhead expense (software, subscriptions, etc.), suggest "Overhead" as category
        - Match the property based on any address or property reference in the receipt
        - Return ONLY valid JSON, no markdown
        """

        if let ocrText, !ocrText.isEmpty {
            prompt += "\n\nOCR text already extracted:\n\(ocrText.prefix(2000))"
        }
        return prompt
    }

    static func categorySuggestionPrompt(vendor: String, amount: Double, description: String, ocrText: String, properties: [Property]) -> String {
        let propertyList = properties.map { $0.name }.joined(separator: ", ")
        let categories = ExpenseCategory.allCases.map { $0.rawValue }.joined(separator: ", ")

        return """
        Given this expense, suggest the best property and category.

        Vendor: \(vendor)
        Amount: $\(String(format: "%.2f", amount))
        Description: \(description)
        Receipt text (first 1000 chars): \(ocrText.prefix(1000))

        Properties: \(propertyList)
        Categories: \(categories)
        Overhead categories: AKB, Advertising, Cash, Overhead, Verizon

        Return ONLY JSON: {"property": "name or null", "category": "category name"}
        """
    }
}

// MARK: - Shared Response Parser

struct AIResponseParser {
    static func parseAnalysis(from jsonText: String) throws -> ReceiptAnalysis {
        // Strip markdown code fences if present
        var cleaned = jsonText.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```json") { cleaned = String(cleaned.dropFirst(7)) }
        if cleaned.hasPrefix("```") { cleaned = String(cleaned.dropFirst(3)) }
        if cleaned.hasSuffix("```") { cleaned = String(cleaned.dropLast(3)) }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8),
              let analysis = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIServiceError.parseError
        }

        return ReceiptAnalysis(
            vendor: analysis["vendor"] as? String,
            amount: analysis["amount"] as? Double,
            date: analysis["date"] as? String,
            description: analysis["description"] as? String,
            principal: analysis["principal"] as? Double,
            interest: analysis["interest"] as? Double,
            suggestedProperty: analysis["suggested_property"] as? String,
            suggestedCategory: analysis["suggested_category"] as? String,
            isMortgage: analysis["is_mortgage"] as? Bool ?? false,
            confidence: analysis["confidence"] as? Double ?? 0.5
        )
    }

    static func parseSuggestion(from jsonText: String) throws -> (propertyName: String?, category: String) {
        var cleaned = jsonText.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```json") { cleaned = String(cleaned.dropFirst(7)) }
        if cleaned.hasPrefix("```") { cleaned = String(cleaned.dropFirst(3)) }
        if cleaned.hasSuffix("```") { cleaned = String(cleaned.dropLast(3)) }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8),
              let suggestion = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIServiceError.parseError
        }

        let property = suggestion["property"] as? String
        let category = suggestion["category"] as? String ?? "Overhead"
        return (property, category)
    }
}
