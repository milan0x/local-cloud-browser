import Foundation

struct TranscriptionJob: Identifiable, Hashable {
    let jobName: String
    let jobStatus: String
    let languageCode: String
    let mediaFormat: String
    let mediaSampleRateHertz: Int?
    let mediaFileUri: String
    let outputBucketName: String
    let transcriptFileUri: String
    let failureReason: String
    let creationTime: Date?
    let completionTime: Date?
    let startTime: Date?

    var id: String { jobName }

    var statusBadgeColor: String {
        switch jobStatus {
        case "COMPLETED": return "green"
        case "IN_PROGRESS": return "blue"
        case "QUEUED": return "orange"
        case "FAILED": return "red"
        default: return "gray"
        }
    }

    var displayFormat: String {
        mediaFormat.uppercased()
    }

    var displayLanguage: String {
        Self.languageNames[languageCode] ?? languageCode
    }

    init(jobName: String = "", jobStatus: String = "", languageCode: String = "",
         mediaFormat: String = "", mediaSampleRateHertz: Int? = nil,
         mediaFileUri: String = "", outputBucketName: String = "",
         transcriptFileUri: String = "", failureReason: String = "",
         creationTime: Date? = nil, completionTime: Date? = nil, startTime: Date? = nil) {
        self.jobName = jobName
        self.jobStatus = jobStatus
        self.languageCode = languageCode
        self.mediaFormat = mediaFormat
        self.mediaSampleRateHertz = mediaSampleRateHertz
        self.mediaFileUri = mediaFileUri
        self.outputBucketName = outputBucketName
        self.transcriptFileUri = transcriptFileUri
        self.failureReason = failureReason
        self.creationTime = creationTime
        self.completionTime = completionTime
        self.startTime = startTime
    }

    init(from dict: [String: Any]) {
        jobName = dict["TranscriptionJobName"] as? String ?? ""
        jobStatus = dict["TranscriptionJobStatus"] as? String ?? ""
        languageCode = dict["LanguageCode"] as? String ?? ""
        mediaFormat = dict["MediaFormat"] as? String ?? ""
        mediaSampleRateHertz = dict["MediaSampleRateHertz"] as? Int
        outputBucketName = dict["OutputBucketName"] as? String ?? ""
        failureReason = dict["FailureReason"] as? String ?? ""

        if let media = dict["Media"] as? [String: Any] {
            mediaFileUri = media["MediaFileUri"] as? String ?? ""
        } else {
            mediaFileUri = ""
        }

        if let transcript = dict["Transcript"] as? [String: Any] {
            transcriptFileUri = transcript["TranscriptFileUri"] as? String ?? ""
        } else {
            transcriptFileUri = ""
        }

        if let ts = dict["CreationTime"] as? Double {
            creationTime = Date(timeIntervalSince1970: ts)
        } else {
            creationTime = nil
        }

        if let ts = dict["CompletionTime"] as? Double {
            completionTime = Date(timeIntervalSince1970: ts)
        } else {
            completionTime = nil
        }

        if let ts = dict["StartTime"] as? Double {
            startTime = Date(timeIntervalSince1970: ts)
        } else {
            startTime = nil
        }
    }

    // MARK: - CLI Helpers

    private static func shellEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "'\\''")
    }

    func getJobCLI(endpointUrl: String, region: String) -> String {
        [
            "aws transcribe get-transcription-job \\",
            "  --transcription-job-name '\(Self.shellEscape(jobName))' \\",
            "  --endpoint-url \(endpointUrl) \\",
            "  --region \(region)",
        ].joined(separator: "\n")
    }

    static func listJobsCLI(endpointUrl: String, region: String) -> String {
        [
            "aws transcribe list-transcription-jobs \\",
            "  --endpoint-url \(endpointUrl) \\",
            "  --region \(region)",
        ].joined(separator: "\n")
    }

    func deleteJobCLI(endpointUrl: String, region: String) -> String {
        [
            "aws transcribe delete-transcription-job \\",
            "  --transcription-job-name '\(Self.shellEscape(jobName))' \\",
            "  --endpoint-url \(endpointUrl) \\",
            "  --region \(region)",
        ].joined(separator: "\n")
    }

    // MARK: - Language Codes

    static let supportedLanguages: [(code: String, name: String)] = [
        ("af-ZA", "Afrikaans"),
        ("ar-AE", "Arabic (Gulf)"),
        ("ar-SA", "Arabic (Modern Standard)"),
        ("zh-CN", "Chinese (Simplified)"),
        ("zh-TW", "Chinese (Traditional)"),
        ("da-DK", "Danish"),
        ("nl-NL", "Dutch"),
        ("en-AU", "English (Australian)"),
        ("en-GB", "English (British)"),
        ("en-IN", "English (Indian)"),
        ("en-US", "English (US)"),
        ("fr-FR", "French"),
        ("fr-CA", "French (Canadian)"),
        ("de-DE", "German"),
        ("de-CH", "German (Swiss)"),
        ("he-IL", "Hebrew"),
        ("hi-IN", "Hindi"),
        ("id-ID", "Indonesian"),
        ("it-IT", "Italian"),
        ("ja-JP", "Japanese"),
        ("ko-KR", "Korean"),
        ("ms-MY", "Malay"),
        ("pt-BR", "Portuguese (Brazilian)"),
        ("pt-PT", "Portuguese"),
        ("ru-RU", "Russian"),
        ("es-ES", "Spanish"),
        ("es-US", "Spanish (US)"),
        ("sv-SE", "Swedish"),
        ("ta-IN", "Tamil"),
        ("te-IN", "Telugu"),
        ("th-TH", "Thai"),
        ("tr-TR", "Turkish"),
        ("vi-VN", "Vietnamese"),
    ]

    static let languageNames: [String: String] = {
        Dictionary(uniqueKeysWithValues: supportedLanguages.map { ($0.code, $0.name) })
    }()

    static let supportedMediaFormats = ["wav", "mp3", "flac", "ogg", "amr", "webm", "mp4"]
}
