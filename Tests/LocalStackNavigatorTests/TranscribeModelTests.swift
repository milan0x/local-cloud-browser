import Testing
import Foundation
@testable import LocalStackNavigator

@Suite("Transcribe Models")
struct TranscribeModelTests {

    // MARK: - statusBadgeColor

    @Test("statusBadgeColor maps statuses correctly")
    func statusBadgeColor() {
        #expect(TranscriptionJob(jobStatus: "COMPLETED").statusBadgeColor == "green")
        #expect(TranscriptionJob(jobStatus: "IN_PROGRESS").statusBadgeColor == "blue")
        #expect(TranscriptionJob(jobStatus: "QUEUED").statusBadgeColor == "orange")
        #expect(TranscriptionJob(jobStatus: "FAILED").statusBadgeColor == "red")
        #expect(TranscriptionJob(jobStatus: "UNKNOWN").statusBadgeColor == "gray")
    }

    // MARK: - displayFormat

    @Test("displayFormat uppercases media format")
    func displayFormat() {
        #expect(TranscriptionJob(mediaFormat: "mp3").displayFormat == "MP3")
        #expect(TranscriptionJob(mediaFormat: "wav").displayFormat == "WAV")
        #expect(TranscriptionJob(mediaFormat: "flac").displayFormat == "FLAC")
    }

    // MARK: - displayLanguage

    @Test("displayLanguage maps known language codes")
    func displayLanguageKnown() {
        #expect(TranscriptionJob(languageCode: "en-US").displayLanguage == "English (US)")
        #expect(TranscriptionJob(languageCode: "de-DE").displayLanguage == "German")
        #expect(TranscriptionJob(languageCode: "ja-JP").displayLanguage == "Japanese")
        #expect(TranscriptionJob(languageCode: "fr-FR").displayLanguage == "French")
    }

    @Test("displayLanguage returns code for unknown languages")
    func displayLanguageUnknown() {
        #expect(TranscriptionJob(languageCode: "xx-YY").displayLanguage == "xx-YY")
    }

    // MARK: - init(from:)

    @Test("parses from dict with nested fields")
    func initFromDict() {
        let job = TranscriptionJob(from: [
            "TranscriptionJobName": "my-job",
            "TranscriptionJobStatus": "COMPLETED",
            "LanguageCode": "en-US",
            "MediaFormat": "mp3",
            "Media": ["MediaFileUri": "s3://bucket/audio.mp3"],
            "Transcript": ["TranscriptFileUri": "s3://bucket/transcript.json"],
            "OutputBucketName": "my-bucket",
            "CreationTime": 1700000000.0,
            "CompletionTime": 1700001000.0,
        ])
        #expect(job.jobName == "my-job")
        #expect(job.jobStatus == "COMPLETED")
        #expect(job.mediaFileUri == "s3://bucket/audio.mp3")
        #expect(job.transcriptFileUri == "s3://bucket/transcript.json")
        #expect(job.creationTime != nil)
        #expect(job.completionTime != nil)
    }

    @Test("defaults for missing fields")
    func initDefaults() {
        let job = TranscriptionJob(from: [:])
        #expect(job.jobName == "")
        #expect(job.mediaFileUri == "")
        #expect(job.transcriptFileUri == "")
    }

    // MARK: - Static properties

    @Test("supportedLanguages is not empty")
    func supportedLanguages() {
        #expect(TranscriptionJob.supportedLanguages.count > 30)
    }

    @Test("supportedMediaFormats contains expected formats")
    func supportedMediaFormats() {
        #expect(TranscriptionJob.supportedMediaFormats.contains("mp3"))
        #expect(TranscriptionJob.supportedMediaFormats.contains("wav"))
        #expect(TranscriptionJob.supportedMediaFormats.contains("flac"))
    }

    // MARK: - CLI

    @Test("getJobCLI generates valid command")
    func getJobCLI() {
        let job = TranscriptionJob(jobName: "my-job")
        let cli = job.getJobCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws transcribe get-transcription-job"))
        #expect(cli.contains("my-job"))
    }

    @Test("listJobsCLI generates valid command")
    func listJobsCLI() {
        let cli = TranscriptionJob.listJobsCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws transcribe list-transcription-jobs"))
    }

    @Test("deleteJobCLI generates valid command")
    func deleteJobCLI() {
        let job = TranscriptionJob(jobName: "my-job")
        let cli = job.deleteJobCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws transcribe delete-transcription-job"))
    }
}
