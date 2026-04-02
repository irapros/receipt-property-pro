import Foundation
import Vision
import UIKit

/// Performs OCR on receipt images using Apple Vision framework (offline)
class OCRService {
    /// Recognize text in an image, returning full OCR text and per-line observations
    func recognizeText(in image: UIImage) async throws -> (text: String, observations: [VNRecognizedTextObservation]) {
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(throwing: OCRError.noResults)
                    return
                }
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                let fullText = lines.joined(separator: "\n")
                continuation.resume(returning: (fullText, observations))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Get the average confidence score from observations
    func averageConfidence(_ observations: [VNRecognizedTextObservation]) -> Double {
        guard !observations.isEmpty else { return 0 }
        let total = observations.compactMap { $0.topCandidates(1).first?.confidence }.reduce(0, +)
        return Double(total) / Double(observations.count)
    }
}

enum OCRError: LocalizedError {
    case invalidImage
    case noResults

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "Could not process the image"
        case .noResults: return "No text found in the image"
        }
    }
}
