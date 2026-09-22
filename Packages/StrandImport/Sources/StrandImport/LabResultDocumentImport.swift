import Foundation

// MARK: - Lab Book document scan (source "lab-document")
//
// LabResultDocumentImport.swift — a best-effort reader for an actual lab-result document
// (a PDF or a photo of a printed report), so a Lab Book entry doesn't always require typing
// every marker by hand or making a CSV first. The app layer extracts plain text from the
// document (PDFKit for a text-layer PDF, on-device Vision OCR as a fallback for a scanned
// PDF or a photo — see LabDocumentTextExtractor) and hands that text here.
//
// This is deliberately more conservative than LabMarkerCsvImport: a CSV has explicit
// (date, marker, value, unit) COLUMNS, so its rows are trustworthy. A lab report's TEXT
// layout varies wildly between providers and is never guaranteed to line up — so this
// parser:
//   1. Only accepts a line whose marker NAME resolves to a KNOWN MarkerCatalog entry
//      (reusing LabMarkerCsvImport's own alias table). An unrecognised name is silently
//      SKIPPED here rather than minted as a custom marker — a scanned line of running
//      prose or a header/footer would otherwise pollute the store with junk "markers".
//      Anything genuinely new still has manual entry / the CSV path as its way in.
//   2. Is NEVER auto-saved. The app layer always shows every detected row in a review
///     screen (value, unit, reference text as printed) so the user can edit or discard
//      before anything is written to the Lab Book (spec's own "never guessed" ethos,
//      extended to a much noisier input than a CSV cell).
//
// Pure and deterministic — no DB, no I/O, no OCR/PDF code (that lives in the app layer,
// which owns PDFKit/Vision). Mirrors LabMarkerCsvImport's parse/model split.

public enum LabResultDocumentImport {

    /// Provenance id stored on every reading saved from a reviewed document scan.
    public static let sourceId = "lab-document"

    /// A single line's plain-text extraction. Both text layers hand over plain UTF-8 text,
    /// so one bound covers either source: a multi-page report is still only a few thousand
    /// short lines of text.
    public static let maxChars = 500_000
    public static let maxLines = 5_000

    /// One marker (or a blood-pressure pair) detected on one line of the document.
    public struct DetectedRow: Sendable, Equatable {
        public enum Kind: Sendable, Equatable {
            case marker(key: String, category: LabMarkerCategory, value: Double)
            case bloodPressure(systolic: Double, diastolic: Double)
        }
        public var kind: Kind
        /// The name exactly as it appeared before the value on the line (for display —
        /// "is this really your LDL?" — never used to resolve a SECOND time).
        public var rawName: String
        /// Unit token found right after the value, or the catalog's canonical unit.
        public var unit: String
        /// Whatever trailed the unit on the line (often a reference range), shown back
        /// VERBATIM if the user keeps it — never computed, never a NOOP-asserted range.
        public var referenceText: String?
        /// The full original line, so the review screen can show "as printed" for a sanity
        /// check against the parsed guess.
        public var rawLine: String

        public init(kind: Kind, rawName: String, unit: String, referenceText: String?, rawLine: String) {
            self.kind = kind; self.rawName = rawName; self.unit = unit
            self.referenceText = referenceText; self.rawLine = rawLine
        }

        /// De-duplication key: a report sometimes repeats a summary table, so the LAST
        /// occurrence of a given marker (or the BP pair) wins, matching the CSV importer's
        /// "last row wins" rule.
        var dedupeKey: String {
            switch kind {
            case .marker(let key, _, _): return key
            case .bloodPressure: return LabMarkerCsvImport.bpSystolicKey + "\u{1}" + LabMarkerCsvImport.bpDiastolicKey
            }
        }
    }

    public struct Result: Sendable, Equatable {
        /// Detected rows, de-duplicated (last occurrence wins), in document order.
        public var rows: [DetectedRow]
        /// A single collection/report date found in the document text, if any pattern
        /// matched ("Collected: 2026-05-01", "Date of Service 05/01/2026", …). A lab report
        /// carries ONE date for the whole panel, not one per row, so this applies to every
        /// detected row; the review screen lets the user set/correct it when this is nil.
        public var detectedDay: String?
        /// Lines that looked like they might be a result row (had a name + a number) but
        /// didn't resolve to a known marker — reported so the user knows the scan wasn't
        /// silently perfect, never counted as an error.
        public var unrecognizedLineCount: Int
        /// The FIRST `unrecognizedSampleCap` of those lines, verbatim — so the review screen can
        /// show exactly what didn't match instead of just a count, letting the user (or a future
        /// catalog/alias update) see precisely which report lines to add coverage for.
        public var unrecognizedSamples: [String]
        /// True when the input text was cut by `maxChars`/`maxLines` (an absurdly large
        /// document) — the tail was not read.
        public var truncated: Bool

        public init(rows: [DetectedRow], detectedDay: String?, unrecognizedLineCount: Int,
                    unrecognizedSamples: [String] = [], truncated: Bool) {
            self.rows = rows; self.detectedDay = detectedDay
            self.unrecognizedLineCount = unrecognizedLineCount
            self.unrecognizedSamples = unrecognizedSamples
            self.truncated = truncated
        }
    }

    /// Cap on how many verbatim unrecognized lines `Result.unrecognizedSamples` keeps — enough to
    /// diagnose a real gap without holding a large chunk of the document in memory.
    public static let unrecognizedSampleCap = 40

    /// Parse plain text already extracted from a document (PDF text layer or OCR).
    public static func parse(text: String) -> Result {
        var truncated = false
        var capped = text
        if capped.count > maxChars { capped = String(capped.prefix(maxChars)); truncated = true }
        var lines = capped.components(separatedBy: .newlines)
        if lines.count > maxLines { lines = Array(lines.prefix(maxLines)); truncated = true }
        lines = stitchWrappedTestNames(lines)

        var found: [DetectedRow] = []
        var unrecognized = 0
        var samples: [String] = []
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            switch parseLine(line) {
            case .some(let row): found.append(row)
            case .none:
                // Only count lines that at least LOOK like a result row (name + a number)
                // as "unrecognized" — plain prose/headers are just not results at all.
                if looksLikeResultRow(line) {
                    unrecognized += 1
                    if samples.count < unrecognizedSampleCap { samples.append(line) }
                }
            }
        }

        var byKey: [String: DetectedRow] = [:]
        var order: [String] = []
        for r in found {
            if byKey[r.dedupeKey] == nil { order.append(r.dedupeKey) }
            byKey[r.dedupeKey] = r   // last occurrence wins
        }
        let deduped = order.compactMap { byKey[$0] }

        return Result(rows: deduped, detectedDay: detectReportDay(in: capped),
                      unrecognizedLineCount: unrecognized, unrecognizedSamples: samples, truncated: truncated)
    }

    // MARK: - Multi-line test names

    /// A wrapped-header-then-value layout ("SEX HORMONE BINDING" on its own line, "GLOBULIN  30  10-50
    /// nmol/L" on the next) reads, line-by-line, as a bare "GLOBULIN" result — which collides with the
    /// unrelated liver-panel Globulin marker and would silently mislabel an SHBG reading. Only a couple
    /// of report names wrap like this; rather than resolve one line at a time, stitch a known header-only
    /// line onto the row that follows it before parsing, so the full name resolves as a whole.
    private static let wrappedNameHeads: [(header: String, continuation: String)] = [
        ("SEX HORMONE BINDING", "GLOBULIN"),
    ]

    static func stitchWrappedTestNames(_ lines: [String]) -> [String] {
        guard !lines.isEmpty else { return lines }
        var out: [String] = []
        var i = 0
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if let match = wrappedNameHeads.first(where: { trimmed.caseInsensitiveCompare($0.header) == .orderedSame }),
               i + 1 < lines.count {
                let next = lines[i + 1].trimmingCharacters(in: .whitespaces)
                if next.uppercased().hasPrefix(match.continuation) {
                    out.append("\(match.header) \(next)")
                    i += 2
                    continue
                }
            }
            out.append(lines[i])
            i += 1
        }
        return out
    }

    // MARK: - Per-line parsing

    /// A very loose "might be a result row" check, used only to decide whether a line that
    /// failed catalog-matching counts toward `unrecognizedLineCount` (so a page number or a
    /// sentence of prose doesn't inflate that count).
    private static func looksLikeResultRow(_ line: String) -> Bool {
        guard line.count <= 240 else { return false }
        let tokens = line.split(separator: " ")
        guard tokens.count >= 2 else { return false }
        return tokens.dropFirst().contains { numericValue(String($0)) != nil || LabMarkerCsvImport.bloodPressurePair(String($0)) != nil }
    }

    /// Try to read one line as "<marker name> <value> [unit] [reference text…]". The name
    /// must resolve to a BUILT-IN catalog marker (see file header) — an unrecognised name,
    /// or a line that carries no number at all, returns nil.
    static func parseLine(_ rawLine: String) -> DetectedRow? {
        let line = rawLine.replacingOccurrences(of: "\t", with: "  ")
        guard line.count <= 240 else { return nil }
        let tokens = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard tokens.count >= 2 else { return nil }

        var valueIndex: Int?
        var bp: (Double, Double)?
        var value: Double?
        var impliedUnit: String?
        for i in 1..<tokens.count {
            if let pair = LabMarkerCsvImport.bloodPressurePair(tokens[i]) { bp = pair; valueIndex = i; break }
            if let (v, u) = numericValue(tokens[i]) { value = v; impliedUnit = u; valueIndex = i; break }
        }
        guard let vIdx = valueIndex else { return nil }

        let name = tokens[0..<vIdx].joined(separator: " ")
        guard name.count >= 2 else { return nil }

        var unit = impliedUnit
        var remainderStart = vIdx + 1
        if unit == nil, remainderStart < tokens.count, isUnitLike(tokens[remainderStart]) {
            unit = tokens[remainderStart]
            remainderStart += 1
        } else if unit == nil {
            // Quest (and other providers) often print "VALUE  LOW-HIGH  UNIT" on one line — the
            // unit trails the reference range, not the value. A reference range itself never
            // looks like a real unit (no letters/%/^ — see isUnitLike), so the loose check above
            // correctly skips it; this widened pass only fires when that happened, and only
            // trusts a STRONG unit token (contains "/", "%", "^", or a known bare-unit word) so it
            // can't misfire on ordinary reference-range prose ("OR", "TO", "SEE", "NOTE").
            for i in (vIdx + 1)..<min(tokens.count, vIdx + 1 + unitSearchWindow) where isStrongUnitLike(tokens[i]) {
                unit = tokens[i]
                break
            }
        }
        let remainder = tokens[remainderStart...].joined(separator: " ").trimmingCharacters(in: .whitespaces)
        let referenceText = remainder.isEmpty ? nil : String(remainder.prefix(80))

        let resolved = LabMarkerCsvImport.resolveMarker(name)
        if let pair = bp, resolved.isBloodPressureFamily {
            return DetectedRow(kind: .bloodPressure(systolic: pair.0, diastolic: pair.1),
                                rawName: name, unit: unit ?? "mmHg", referenceText: referenceText, rawLine: line)
        }
        guard bp == nil, let v = value, let key = resolved.key,
              let def = MarkerCatalog.definition(for: key) else { return nil }
        return DetectedRow(kind: .marker(key: key, category: def.category, value: v),
                            rawName: name, unit: unit ?? def.canonicalUnit, referenceText: referenceText, rawLine: line)
    }

    /// A token as a lab value: strips a leading qualifier (`<`/`>`/`≤`/`≥`, common on a
    /// report's "below detection limit" rows) and a trailing `%`, then parses via the SAME
    /// number rules as the CSV importer (decimal comma etc.) so the two paths never disagree
    /// on what a number means.
    private static func numericValue(_ raw: String) -> (value: Double, impliedUnit: String?)? {
        var t = raw
        var impliedUnit: String?
        if t.hasSuffix("%") { impliedUnit = "%"; t.removeLast() }
        while let f = t.first, "<>≤≥".contains(f) { t.removeFirst() }
        guard !t.isEmpty, let v = LabMarkerCsvImport.parseValue(t) else { return nil }
        return (v, impliedUnit)
    }

    /// A bare single-letter flag ("H", "L") is never a unit; a second number (a reference
    /// range's lower bound) is never a unit either — only an actual unit token qualifies.
    private static func isUnitLike(_ tok: String) -> Bool {
        guard tok.count > 1 else { return false }
        let upper = tok.uppercased()
        if ["H", "L", "HIGH", "LOW", "NORMAL", "ABNORMAL", "A", "N"].contains(upper) { return false }
        if LabMarkerCsvImport.parseValue(tok) != nil { return false }
        return tok.contains { $0.isLetter || "%µ/^".contains($0) }
    }

    /// How many tokens past the value to look for a unit that trails a reference range
    /// ("VALUE  7-25  mg/dL") before giving up — a Quest report's range + flag + lab-site
    /// code rarely runs longer than this.
    private static let unitSearchWindow = 6

    /// A STRICTER unit check for the widened post-range search: `isUnitLike` accepts any token
    /// with a letter in it, which is safe when it only ever looks at the ONE token right after
    /// the value, but would happily misread reference-range prose ("OR", "TO", "SEE", "NOTE")
    /// as a unit once the search widens. Real lab units overwhelmingly carry a "/", "%", or "^"
    /// (mg/dL, mmol/L, 10^9/L, %) or are one of a handful of bare words — nothing else qualifies.
    private static let bareUnitWords: Set<String> = ["mmhg", "fl", "score", "ratio", "index", "titer"]

    private static func isStrongUnitLike(_ tok: String) -> Bool {
        guard tok.count > 1 else { return false }
        if tok.contains("/") || tok.contains("%") || tok.contains("^") { return true }
        return bareUnitWords.contains(tok.lowercased())
    }

    // MARK: - Whole-document report date

    private static let dateHintPatterns = [
        #"(?:collection date|collected|specimen collected|date of service|date collected|test date|report date|date reported|reported on)\s*[:\-]?\s*([0-9]{1,4}[-/][0-9]{1,2}[-/][0-9]{1,4})"#
    ]

    private static func detectReportDay(in text: String) -> String? {
        for pattern in dateHintPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            if let m = regex.firstMatch(in: text, range: range), m.numberOfRanges > 1,
               let r = Range(m.range(at: 1), in: text),
               let day = LabMarkerCsvImport.canonicalDay(String(text[r])) {
                return day
            }
        }
        return nil
    }
}
