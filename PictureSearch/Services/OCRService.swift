import CoreGraphics
import Foundation
import Vision

protocol OCRServicing {
    func recognizeText(in image: CGImage) async throws -> OCRRecognitionResult
}

enum OCRServiceError: LocalizedError, Equatable {
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .recognitionFailed(let message):
            return "OCR 识别失败：\(message)"
        }
    }
}

struct OCRService: OCRServicing {
    func recognizeText(in image: CGImage) async throws -> OCRRecognitionResult {
        try await Task.detached(priority: .utility) {
            let startDate = Date()
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "en-US"]

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                throw OCRServiceError.recognitionFailed(error.localizedDescription)
            }

            let lines = request.results?
                .compactMap { observation in
                    observation.topCandidates(1).first?.string
                } ?? []
            let text = OCRTextNormalizer.normalize(lines)

            return OCRRecognitionResult(
                text: text,
                durationSeconds: Date().timeIntervalSince(startDate)
            )
        }.value
    }
}
