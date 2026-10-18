import Foundation
import Vision
import AppKit

let files = CommandLine.arguments.dropFirst()

for file in files {
    let url = URL(fileURLWithPath: file)

    guard let image = NSImage(contentsOf: url),
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else {
        fputs("Cannot read \(file)\n", stderr)
        continue
    }

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["ja-JP"]
    request.usesLanguageCorrection = false

    do {
        try VNImageRequestHandler(cgImage: cgImage).perform([request])

        let results = request.results ?? []
        let candidate = results.first?.topCandidates(1).first

        print("glyph-work/glyphs/\(url.lastPathComponent)\t\(candidate?.string ?? "")\t\(candidate?.confidence ?? 0)")
    } catch {
        fputs("OCR failed for \(file): \(error)\n", stderr)
    }
}