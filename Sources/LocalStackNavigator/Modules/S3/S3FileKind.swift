import Foundation
import UniformTypeIdentifiers

enum S3FileKind {
    static func kind(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        if ext.isEmpty { return "Document" }
        if let utType = UTType(filenameExtension: ext) {
            return utType.localizedDescription ?? utType.identifier
        }
        return ext.uppercased() + " File"
    }

    static func icon(for filename: String, isFolder: Bool) -> String {
        if isFolder { return "folder.fill" }
        let ext = (filename as NSString).pathExtension.lowercased()
        guard !ext.isEmpty, let utType = UTType(filenameExtension: ext) else {
            return "doc"
        }
        if utType.conforms(to: .image) { return "photo" }
        if utType.conforms(to: .movie) || utType.conforms(to: .video) { return "film" }
        if utType.conforms(to: .audio) { return "music.note" }
        if utType.conforms(to: .archive) { return "doc.zipper" }
        if utType.conforms(to: .pdf) { return "doc.richtext" }
        if utType.conforms(to: .json) || utType.conforms(to: .xml) { return "doc.text" }
        if utType.conforms(to: .sourceCode) || utType.conforms(to: .plainText) { return "doc.text" }
        return "doc"
    }
}
