import SwiftUI
import AppKit

struct ACMCertificateDetailPaneView: View {
    @ObservedObject var service: ACMService
    let certificate: ACMCertificateSummary
    @EnvironmentObject private var appState: AppState

    @State private var detail: ACMCertificateDetail?
    @State private var certificatePEM: String?
    @State private var chainPEM: String?
    @State private var isLoading = false
    @State private var serviceError: ServiceError?

    var body: some View {
        VStack(spacing: 0) {
            if isLoading && detail == nil {
                ProgressView("Loading certificate details...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        summarySection
                        if let detail, !detail.subjectAlternativeNames.isEmpty {
                            domainsSection(detail.subjectAlternativeNames)
                        }
                        validitySection
                        certificatePEMSection
                    }
                    .padding(16)
                }
            }
        }
        .task { loadDetails() }
        .onChange(of: certificate.certificateArn) {
            detail = nil
            certificatePEM = nil
            chainPEM = nil
            loadDetails()
        }
        .onReceive(appState.autoRefresh.triggerPublisher) {
            guard !isLoading else { return }
            loadDetails(silent: true)
        }
        .serviceErrorAlert(error: $serviceError)
    }

    // MARK: - Summary Section

    private var summarySection: some View {
        GroupBox("Summary") {
            VStack(alignment: .leading, spacing: 8) {
                labeledRow("Domain") {
                    CopyableValue(text: certificate.displayDomain)
                }
                labeledRow("ARN") {
                    CopyableValue(text: certificate.certificateArn, font: .caption, monospaced: true)
                }
                labeledRow("Status") {
                    statusBadge(certificate.status)
                }
                labeledRow("Type") {
                    typeBadge(certificate.type)
                }
                if !certificate.keyAlgorithm.isEmpty {
                    labeledRow("Algorithm") {
                        Text(certificate.keyAlgorithm)
                            .font(.body.monospaced())
                    }
                }
                if let detail {
                    if !detail.issuer.isEmpty {
                        labeledRow("Issuer") {
                            Text(detail.issuer)
                                .textSelection(.enabled)
                        }
                    }
                    if !detail.serial.isEmpty {
                        labeledRow("Serial") {
                            CopyableValue(text: detail.serial, font: .caption, monospaced: true)
                        }
                    }
                    if let reason = detail.failureReason, !reason.isEmpty {
                        labeledRow("Failure") {
                            Text(reason)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .padding(4)
        }
    }

    // MARK: - Domains Section

    private func domainsSection(_ sans: [String]) -> some View {
        GroupBox("Subject Alternative Names") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(sans, id: \.self) { name in
                    CopyableValue(text: name, monospaced: true)
                }
            }
            .padding(4)
        }
    }

    // MARK: - Validity Section

    private var validitySection: some View {
        GroupBox("Validity") {
            VStack(alignment: .leading, spacing: 8) {
                if let date = certificate.createdAt ?? detail?.createdAt {
                    labeledRow("Created") {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                }
                if let date = certificate.issuedAt ?? detail?.issuedAt {
                    labeledRow("Issued") {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                }
                if let date = detail?.notBefore {
                    labeledRow("Not Before") {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                }
                if let date = certificate.notAfter ?? detail?.notAfter {
                    labeledRow("Not After") {
                        HStack(spacing: 6) {
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                            if date < Date() {
                                StatusBadge(text: "EXPIRED", color: .red)
                            }
                        }
                    }
                }
                if let detail, !detail.inUseBy.isEmpty {
                    labeledRow("In Use By") {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(detail.inUseBy, id: \.self) { arn in
                                Text(arn)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .padding(4)
        }
    }

    // MARK: - Certificate PEM Section

    private var certificatePEMSection: some View {
        GroupBox {
            if let pem = certificatePEM {
                VStack(alignment: .leading, spacing: 8) {
                    ScrollView([.horizontal, .vertical]) {
                        Text(pem)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(4)
                    }
                    .frame(maxHeight: 200)

                    if let chain = chainPEM, !chain.isEmpty {
                        Divider()
                        Text("Certificate Chain")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ScrollView([.horizontal, .vertical]) {
                            Text(chain)
                                .font(.body.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(4)
                        }
                        .frame(maxHeight: 150)
                    }
                }
            } else if certificate.status == "ISSUED" || certificate.type == "IMPORTED" {
                Text("Loading certificate PEM...")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                Text("Certificate PEM not available (status: \(certificate.status))")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
        } label: {
            HStack {
                Text("Certificate PEM")
                Spacer()
                if certificatePEM != nil {
                    Button {
                        var text = certificatePEM ?? ""
                        if let chain = chainPEM, !chain.isEmpty {
                            text += "\n" + chain
                        }
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy PEM")
                }
            }
        }
    }

    // MARK: - Badges

    private func statusBadge(_ status: String) -> some View {
        let display = status.replacingOccurrences(of: "_", with: " ")
        return StatusBadge(text: display, color: statusColor(status))
    }

    private func typeBadge(_ type: String) -> some View {
        let display = type == "AMAZON_ISSUED" ? "Amazon Issued" : (type == "IMPORTED" ? "Imported" : type)
        let color: Color = type == "IMPORTED" ? .purple : .blue
        return StatusBadge(text: display, color: color)
    }

    // MARK: - Helpers

    private func labeledRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            content()
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "ISSUED": .green
        case "PENDING_VALIDATION": .orange
        case "EXPIRED", "FAILED", "REVOKED": .red
        case "INACTIVE": .gray
        default: .gray
        }
    }

    // MARK: - Data

    private func loadDetails(silent: Bool = false) {
        if !silent { isLoading = true }
        Task {
            do {
                let loaded = try await service.describeCertificate(arn: certificate.certificateArn)
                detail = loaded

                // Try loading PEM data (may fail for PENDING certs)
                if loaded.status == "ISSUED" || loaded.type == "IMPORTED" {
                    do {
                        let pem = try await service.getCertificate(arn: certificate.certificateArn)
                        certificatePEM = pem.certificate
                        chainPEM = pem.chain
                    } catch {
                        // PEM not available yet — not a fatal error
                        certificatePEM = nil
                        chainPEM = nil
                    }
                }
            } catch {
                if !silent {
                    serviceError = error.asServiceError
                }
            }
            if !silent { isLoading = false }
        }
    }
}
