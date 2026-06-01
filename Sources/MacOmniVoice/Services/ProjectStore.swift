import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
enum ProjectStore {

    /// Convert current MainView state into a saveable document.
    static func capture(text: String,
                        refClipID: UUID?,
                        refClipName: String?,
                        refAudioPath: String?,
                        refText: String?,
                        settings: AppSettings) -> ProjectDocument {
        ProjectDocument(
            text: text,
            refClipID: refClipID,
            refClipName: refClipName,
            refAudioPath: refAudioPath,
            refText: refText,
            modelId: settings.modelId,
            language: settings.language,
            instruct: settings.instruct,
            speed: settings.speed,
            duration: settings.duration,
            numStep: settings.numStep,
            guidanceScale: settings.guidanceScale,
            denoise: settings.denoise,
            postprocessOutput: settings.postprocessOutput,
            preprocessPrompt: settings.preprocessPrompt,
            tShift: settings.tShift,
            layerPenaltyFactor: settings.layerPenaltyFactor,
            positionTemperature: settings.positionTemperature,
            classTemperature: settings.classTemperature,
            deviceOverride: settings.deviceOverride
        )
    }

    static func saveWithPanel(_ doc: ProjectDocument, defaultName: String = "Untitled") {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: ProjectDocument.pathExtension) ?? .json]
        panel.nameFieldStringValue = "\(defaultName).\(ProjectDocument.pathExtension)"
        if panel.runModal() == .OK, let url = panel.url {
            _ = save(doc, to: url)
        }
    }

    @discardableResult
    static func save(_ doc: ProjectDocument, to url: URL) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(doc)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func openWithPanel() -> ProjectDocument? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: ProjectDocument.pathExtension) ?? .json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            return load(from: url)
        }
        return nil
    }

    static func load(from url: URL) -> ProjectDocument? {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(ProjectDocument.self, from: data)
        } catch {
            return nil
        }
    }
}
