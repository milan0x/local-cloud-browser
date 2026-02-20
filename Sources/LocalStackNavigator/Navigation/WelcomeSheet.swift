import SwiftUI

// MARK: - Docker Detector

@MainActor
private final class DockerDetector: ObservableObject {
    enum DockerStatus: Equatable {
        case checking
        case installed(String)
        case notInstalled
    }

    enum ContainerStatus: Equatable {
        case checking
        case running(String)
        case notRunning
        case unknown
    }

    @Published var dockerStatus: DockerStatus = .checking
    @Published var containerStatus: ContainerStatus = .checking

    func runChecks() async {
        dockerStatus = .checking
        containerStatus = .checking
        await checkDocker()
        if case .installed = dockerStatus {
            await checkContainer()
        } else {
            containerStatus = .unknown
        }
    }

    private func checkDocker() async {
        do {
            let output = try await runProcess(arguments: ["docker", "--version"])
            let version = output.trimmingCharacters(in: .whitespacesAndNewlines)
            dockerStatus = version.isEmpty ? .notInstalled : .installed(version)
        } catch {
            dockerStatus = .notInstalled
        }
    }

    private func checkContainer() async {
        do {
            let output = try await runProcess(arguments: [
                "docker", "ps",
                "--filter", "ancestor=localstack/localstack",
                "--format", "{{.Status}}"
            ])
            let status = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if status.isEmpty {
                containerStatus = .notRunning
            } else {
                containerStatus = .running(status)
            }
        } catch {
            containerStatus = .unknown
        }
    }

    private func runProcess(arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            if process.terminationStatus == 0 {
                continuation.resume(returning: output)
            } else {
                continuation.resume(throwing: NSError(
                    domain: "DockerDetector",
                    code: Int(process.terminationStatus)
                ))
            }
        }
    }
}

// MARK: - Welcome Sheet

struct WelcomeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var detector = DockerDetector()

    private let dockerCommand = "docker run -d -p 4566:4566 localstack/localstack"

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 32)
                .padding(.bottom, 24)

            prerequisitesSection
                .padding(.horizontal, 32)

            commandSection
                .padding(.horizontal, 32)
                .padding(.top, 16)

            Spacer()

            footerButtons
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
        }
        .frame(width: 500, height: 520)
        .task {
            await detector.runChecks()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "cloud.fill")
                .font(.system(size: 72))
                .foregroundStyle(
                    .linearGradient(
                        colors: [.blue, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Local Cloud Browser")
                .font(.title)
                .fontWeight(.bold)

            Text("Browse and manage your local cloud services")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Prerequisites

    private var prerequisitesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Prerequisites")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                dockerRow
                Divider().padding(.horizontal, 12)
                containerRow
            }
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.quaternary, lineWidth: 1)
            )
        }
    }

    private var dockerRow: some View {
        HStack {
            statusIcon(for: dockerStatusKind)
            Text("Docker")
                .fontWeight(.medium)
            Spacer()
            dockerDetail
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var containerRow: some View {
        HStack {
            statusIcon(for: containerStatusKind)
            Text("LocalStack")
                .fontWeight(.medium)
            Spacer()
            containerDetail
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var dockerDetail: some View {
        switch detector.dockerStatus {
        case .checking:
            Text("Checking…")
        case .installed(let version):
            Text(version)
                .lineLimit(1)
        case .notInstalled:
            Link("Install Docker", destination: URL(string: "https://docs.docker.com/get-docker/")!)
                .font(.caption)
        }
    }

    @ViewBuilder
    private var containerDetail: some View {
        switch detector.containerStatus {
        case .checking:
            Text("Checking…")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .running(let status):
            StatusBadge(text: status, color: .green)
        case .notRunning:
            Text("Not running")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .unknown:
            Text("—")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Command Section

    @ViewBuilder
    private var commandSection: some View {
        switch detector.containerStatus {
        case .notRunning:
            dockerCommandBox
        case .running:
            EmptyView()
        default:
            EmptyView()
        }
    }

    private var dockerCommandBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Start LocalStack with:")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text(dockerCommand)
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1)
                    .textSelection(.enabled)

                Spacer()

                CopyButton(text: dockerCommand)
            }
            .padding(12)
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.quaternary, lineWidth: 1)
            )
        }
    }

    // MARK: - Status Icons

    private enum StatusKind {
        case checking, success, failure
    }

    private var dockerStatusKind: StatusKind {
        switch detector.dockerStatus {
        case .checking: .checking
        case .installed: .success
        case .notInstalled: .failure
        }
    }

    private var containerStatusKind: StatusKind {
        switch detector.containerStatus {
        case .checking: .checking
        case .running: .success
        case .notRunning, .unknown: .failure
        }
    }

    @ViewBuilder
    private func statusIcon(for kind: StatusKind) -> some View {
        switch kind {
        case .checking:
            ProgressView()
                .controlSize(.small)
                .frame(width: 16, height: 16)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(width: 16, height: 16)
        case .failure:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .frame(width: 16, height: 16)
        }
    }

    // MARK: - Footer

    private var footerButtons: some View {
        HStack {
            Button("Refresh") {
                Task { await detector.runChecks() }
            }
            .disabled(
                detector.dockerStatus == .checking
                || detector.containerStatus == .checking
            )

            Spacer()

            Button("Continue") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}
