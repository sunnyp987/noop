import Foundation
import PDFKit
import Vision
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Turns a picked lab-result document (a PDF or a photo of a printed report) into plain
/// text, entirely on-device — no network call, no cloud OCR service. Feeds
/// `LabResultDocumentImport.parse(text:)` (StrandImport), which is the part that actually
/// looks for markers; this file's only job is "get me the words on the page".
///
/// A PDF exported by a lab portal almost always carries a real text layer (PDFKit reads it
/// directly, fast and exact). A SCANNED PDF (a photographed page saved as PDF) or a photo
/// taken of a printed report has no text layer, so this falls back to Vision's on-device
/// text recognition (`VNRecognizeTextRequest`), rendering each PDF page to an image first
/// when needed. Both paths run locally; nothing here ever leaves the device.
enum LabDocumentTextExtractor {

    /// Extract plain text from a picked file. Returns nil if the file can't be opened or
    /// carries no readable text at all (never throws — the caller shows an honest "couldn't
    /// read that file" message rather than a crash).
    static func extractText(from url: URL) async -> String? {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            return await extractPDFText(url: url)
        }
        return await Task.detached(priority: .userInitiated) {
            extractImageText(url: url)
        }.value
    }

    // MARK: - PDF

    private static func extractPDFText(url: URL) async -> String? {
        await Task.detached(priority: .userInitiated) {
            guard let doc = PDFDocument(url: url) else { return nil }
            var full = ""
            for i in 0..<doc.pageCount {
                if let page = doc.page(at: i), let t = page.string, !t.isEmpty {
                    full += t + "\n"
                }
            }
            // A real text-layer PDF yields far more than a few stray characters (fonts/
            // metadata sometimes leak a handful even on a fully scanned page). Below that,
            // treat it as scanned and fall back to on-device OCR of the rendered pages.
            if full.trimmingCharacters(in: .whitespacesAndNewlines).count > 40 {
                return full
            }
            return ocrPDF(doc)
        }.value
    }

    private static func ocrPDF(_ doc: PDFDocument) -> String? {
        var full = ""
        let scale: CGFloat = 2.0   // sharper than 1x for small report print, without ballooning memory
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            guard bounds.width > 0, bounds.height > 0 else { continue }
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            guard let cg = renderPage(page, size: size, scale: scale) else { continue }
            if let text = recognizeText(cgImage: cg) { full += text + "\n" }
        }
        return full.isEmpty ? nil : full
    }

    private static func renderPage(_ page: PDFPage, size: CGSize, scale: CGFloat) -> CGImage? {
        #if canImport(UIKit)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.white.set()
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.cgContext.translateBy(x: 0, y: size.height)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
        return image.cgImage
        #else
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }
        NSColor.white.set()
        NSRect(origin: .zero, size: size).fill()
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.translateBy(x: 0, y: size.height)
            ctx.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: ctx)
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #endif
    }

    // MARK: - Photo of a report

    private static func extractImageText(url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        #if canImport(UIKit)
        guard let image = UIImage(data: data), let cg = image.cgImage else { return nil }
        #else
        guard let image = NSImage(data: data), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        #endif
        return recognizeText(cgImage: cg)
    }

    // MARK: - Vision OCR (on-device, no network)

    private static func recognizeText(cgImage: CGImage) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let observations = request.results, !observations.isEmpty else { return nil }
        return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}
