import Foundation
import UIKit
import PDFKit

/// Creates PDF files from scanned receipt images
class PDFService {

    /// Create a PDF from one or more scanned images
    func createPDF(from images: [UIImage], filename: String) throws -> URL {
        let pdfDocument = PDFDocument()

        for (index, image) in images.enumerated() {
            // Scale image to fit letter size while maintaining aspect ratio
            let pageImage = fitToLetterSize(image)
            guard let page = PDFPage(image: pageImage) else {
                throw PDFError.pageCreationFailed
            }
            pdfDocument.insert(page, at: index)
        }

        // Save to temporary directory first
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        guard pdfDocument.write(to: tempURL) else {
            throw PDFError.writeFailed
        }

        return tempURL
    }

    /// Resize image to fit US Letter page (8.5 x 11 inches at 72 DPI)
    private func fitToLetterSize(_ image: UIImage) -> UIImage {
        let letterWidth: CGFloat = 612   // 8.5 * 72
        let letterHeight: CGFloat = 792  // 11 * 72
        let margin: CGFloat = 36         // 0.5 inch margins

        let maxWidth = letterWidth - (margin * 2)
        let maxHeight = letterHeight - (margin * 2)

        let imageSize = image.size
        let widthRatio = maxWidth / imageSize.width
        let heightRatio = maxHeight / imageSize.height
        let scale = min(widthRatio, heightRatio, 1.0)  // Don't upscale

        let newSize = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: letterWidth, height: letterHeight))
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: letterWidth, height: letterHeight)))

            let x = (letterWidth - newSize.width) / 2
            let y = (letterHeight - newSize.height) / 2
            image.draw(in: CGRect(x: x, y: y, width: newSize.width, height: newSize.height))
        }
    }
}

enum PDFError: LocalizedError {
    case pageCreationFailed
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .pageCreationFailed: return "Failed to create PDF page from image"
        case .writeFailed: return "Failed to save PDF file"
        }
    }
}
