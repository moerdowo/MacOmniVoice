import Foundation

/// Splits long text into chunks that fit the OmniVoice diffusion budget.
/// Uses NSLinguisticTagger sentence enumeration as primary, then greedily
/// packs sentences up to a soft character budget (default ≈ 350 chars).
enum TextSplitter {
    static func split(_ text: String, softLimit: Int = 350) -> [String] {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return [] }
        if raw.count <= softLimit {
            return [raw]
        }

        var sentences: [String] = []
        let tagger = NSLinguisticTagger(tagSchemes: [.tokenType], options: 0)
        tagger.string = raw
        let range = NSRange(location: 0, length: raw.utf16.count)
        tagger.enumerateTags(in: range, unit: .sentence, scheme: .tokenType, options: []) { _, r, _ in
            if let swiftRange = Range(r, in: raw) {
                let s = raw[swiftRange].trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { sentences.append(String(s)) }
            }
        }

        // If the linguistic tagger couldn't find anything (rare), fall
        // back to a naive period/CJK-stop split.
        if sentences.isEmpty {
            sentences = raw
                .components(separatedBy: CharacterSet(charactersIn: ".!?。！？\n"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        // Pack into chunks under softLimit.
        var chunks: [String] = []
        var current = ""
        for s in sentences {
            if current.isEmpty {
                current = s
            } else if current.count + 1 + s.count <= softLimit {
                current += " " + s
            } else {
                chunks.append(current)
                current = s
            }
            // Sentence itself longer than the limit? Hard-split on
            // word/character boundary as a last resort.
            if current.count > softLimit {
                chunks.append(contentsOf: hardSplit(current, limit: softLimit))
                current = ""
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    private static func hardSplit(_ text: String, limit: Int) -> [String] {
        var result: [String] = []
        var idx = text.startIndex
        while idx < text.endIndex {
            let end = text.index(idx, offsetBy: limit, limitedBy: text.endIndex) ?? text.endIndex
            // Try to back up to the nearest whitespace to keep words intact.
            var cut = end
            if end < text.endIndex {
                while cut > idx && !text[cut].isWhitespace { cut = text.index(before: cut) }
                if cut == idx { cut = end }
            }
            let piece = String(text[idx..<cut]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { result.append(piece) }
            idx = cut == text.endIndex ? text.endIndex : text.index(after: cut)
        }
        return result
    }
}
