import Foundation
import NaturalLanguage

enum LanguageDetector {
    /// Returns a (bcp47, friendlyName) tuple, or nil for very short / mixed text.
    static func detect(_ text: String) -> (code: String, name: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 12 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        guard let lang = recognizer.dominantLanguage else { return nil }
        let code = lang.rawValue
        let name = Locale.current.localizedString(forLanguageCode: code) ?? code
        return (code, name)
    }
}
