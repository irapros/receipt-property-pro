import Foundation
import UIKit

/// Google Gemini implementation of AIServiceProtocol
class GeminiAIService: AIServiceProtocol {
    private let apiKey: String

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    private func baseURL(model: String) -> String {
        "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
    }

    // MARK: - Receipt Analysis (Image + Text)

    func analyzeReceipt(image: UIImage, ocrText: String?, properties: [Property]) async throws -> ReceiptAnalysis {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw AIServiceError.invalidImage
        }
        let base64Image = imageData.base64EncodedString()
        let prompt = AIPromptBuilder.receiptAnalysisPrompt(ocrText: ocrText, properties: properties)

        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        [
                            "inline_data": [
                                "mime_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ],
                        [
                            "text": prompt
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "maxOutputTokens": 1024
            ]
        ]

        let data = try await makeRequest(model: "gemini-2.0-flash", body: body)
        let text = try extractText(from: data)
        return try AIResponseParser.parseAnalysis(from: text)
    }

    // MARK: - Category Suggestion (Text Only)

    func suggestCategory(vendor: String, amount: Double, description: String, ocrText: String, properties: [Property]) async throws -> (propertyName: String?, category: String) {
        let prompt = AIPromptBuilder.categorySuggestionPrompt(vendor: vendor, amount: amount, description: description, ocrText: ocrText, properties: properties)

        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "maxOutputTokens": 256
            ]
        ]

        let data = try await makeRequest(model: "gemini-2.0-flash", body: body)
        let text = try extractText(from: data)
        return try AIResponseParser.parseSuggestion(from: text)
    }

    // MARK: - Network

    private func makeRequest(model: String, body: [String: Any]) async throws -> Data {
        guard !apiKey.isEmpty else { throw AIServiceError.noAPIKey }

        let urlString = baseURL(model: model)
        guard let url = URL(string: urlString) else {
            throw AIServiceError.networkError("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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

    // MARK: - Parse Gemini Response Envelope

    private func extractText(from data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let textPart = parts.first,
              let text = textPart["text"] as? String else {
            throw AIServiceError.parseError
        }
        return text
    }
}
