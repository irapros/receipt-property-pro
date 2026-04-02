import Foundation
import UIKit

/// Claude (Anthropic) implementation of AIServiceProtocol
class ClaudeAIService: AIServiceProtocol {
    private let apiKey: String
    private let baseURL = "https://api.anthropic.com/v1/messages"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    // MARK: - Receipt Analysis (Image + Text)

    func analyzeReceipt(image: UIImage, ocrText: String?, properties: [Property]) async throws -> ReceiptAnalysis {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw AIServiceError.invalidImage
        }
        let base64Image = imageData.base64EncodedString()
        let prompt = AIPromptBuilder.receiptAnalysisPrompt(ocrText: ocrText, properties: properties)

        let content: [[String: Any]] = [
            [
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": base64Image
                ]
            ],
            [
                "type": "text",
                "text": prompt
            ]
        ]

        let body: [String: Any] = [
            "model": "claude-sonnet-4-5-20250929",
            "max_tokens": 1024,
            "messages": [
                ["role": "user", "content": content]
            ]
        ]

        let data = try await makeRequest(body: body)
        let text = try extractText(from: data)
        return try AIResponseParser.parseAnalysis(from: text)
    }

    // MARK: - Category Suggestion (Text Only)

    func suggestCategory(vendor: String, amount: Double, description: String, ocrText: String, properties: [Property]) async throws -> (propertyName: String?, category: String) {
        let prompt = AIPromptBuilder.categorySuggestionPrompt(vendor: vendor, amount: amount, description: description, ocrText: ocrText, properties: properties)

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 256,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        let data = try await makeRequest(body: body)
        let text = try extractText(from: data)
        return try AIResponseParser.parseSuggestion(from: text)
    }

    // MARK: - Network

    private func makeRequest(body: [String: Any]) async throws -> Data {
        guard !apiKey.isEmpty else { throw AIServiceError.noAPIKey }

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.networkError("Invalid response")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown"
            throw AIServiceError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }
        return data
    }

    // MARK: - Parse Claude Response Envelope

    private func extractText(from data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let textBlock = content.first(where: { $0["type"] as? String == "text" }),
              let text = textBlock["text"] as? String else {
            throw AIServiceError.parseError
        }
        return text
    }
}
