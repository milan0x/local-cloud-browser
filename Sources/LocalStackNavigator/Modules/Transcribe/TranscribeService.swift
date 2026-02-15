import Foundation

@MainActor
final class TranscribeService: ObservableObject {
    private var client: LocalStackClient!

    func updateClient(_ newClient: LocalStackClient) {
        self.client = newClient
    }

    // MARK: - Job Operations

    func listTranscriptionJobs(status: String? = nil) async throws -> [TranscriptionJob] {
        var payload: [String: Any] = [:]
        if let status {
            payload["Status"] = status
        }
        let data = try await client.transcribeRequest(action: "ListTranscriptionJobs", payload: payload)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let summaries = json["TranscriptionJobSummaries"] as? [[String: Any]] else {
            return []
        }
        return summaries.map { TranscriptionJob(from: $0) }
    }

    func getTranscriptionJob(name: String) async throws -> TranscriptionJob {
        let data = try await client.transcribeRequest(
            action: "GetTranscriptionJob",
            payload: ["TranscriptionJobName": name]
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let jobDict = json["TranscriptionJob"] as? [String: Any] else {
            throw LocalStackClientError.invalidURL
        }
        return TranscriptionJob(from: jobDict)
    }

    func startTranscriptionJob(
        name: String,
        mediaUri: String,
        languageCode: String,
        mediaFormat: String,
        outputBucketName: String?
    ) async throws {
        var payload: [String: Any] = [
            "TranscriptionJobName": name,
            "LanguageCode": languageCode,
            "MediaFormat": mediaFormat,
            "Media": [
                "MediaFileUri": mediaUri,
            ] as [String: Any],
        ]
        if let outputBucketName, !outputBucketName.isEmpty {
            payload["OutputBucketName"] = outputBucketName
        }
        _ = try await client.transcribeRequest(action: "StartTranscriptionJob", payload: payload)
    }

    func deleteTranscriptionJob(name: String) async throws {
        _ = try await client.transcribeRequest(
            action: "DeleteTranscriptionJob",
            payload: ["TranscriptionJobName": name]
        )
    }

    // MARK: - Transcript Fetching

    /// Fetches the transcript text from the transcript file URI.
    /// The URI points to an S3 object containing JSON with the transcript.
    func fetchTranscript(from uri: String) async throws -> String {
        // The transcript URI from LocalStack is typically an HTTP URL to the S3 object
        guard let url = URL(string: uri) else { return "" }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [String: Any],
              let transcripts = results["transcripts"] as? [[String: Any]],
              let first = transcripts.first,
              let transcript = first["transcript"] as? String else {
            // Try returning raw text if JSON parsing fails
            return String(data: data, encoding: .utf8) ?? ""
        }
        return transcript
    }
}
