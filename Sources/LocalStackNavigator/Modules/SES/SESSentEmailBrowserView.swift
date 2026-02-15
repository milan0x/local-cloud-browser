import SwiftUI

struct SESSentEmailBrowserView: View {
    @ObservedObject var service: SESService
    @ObservedObject var toolbarState: SESToolbarState
    @EnvironmentObject private var appState: AppState
    let selectedIdentity: SESIdentity?

    @State private var emails: [SESSentEmail] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var serviceError: ServiceError?
    @State private var selectedEmailID: String?
    @State private var searchText = ""
    @State private var showClearConfirmation = false
    @State private var showSendSheet = false
    @State private var lastLoadTime: Date?

    var body: some View {
        VStack(spacing: 0) {
            emailListHeader
            Divider()
            emailListContent
        }
        .sheet(isPresented: $showSendSheet) {
            SESSendEmailView(
                service: service,
                prefilledFrom: selectedIdentity?.identity
            )
            .onDisappear { loadEmails(force: true) }
        }
        .confirmationDialog(
            "Clear All Sent Emails",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) { clearEmails() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will delete all \(emails.count) captured sent email\(emails.count == 1 ? "" : "s") from LocalStack. This cannot be undone.")
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadEmails() }
        .onReceive(appState.autoRefresh.triggerPublisher) {
            guard !showSendSheet && !showClearConfirmation && !isLoading else { return }
            loadEmails(force: true, silent: true)
        }
        .onChange(of: appState.connectionVersion) {
            emails = []
            selectedEmailID = nil
            loadEmails(force: true)
        }
        .onChange(of: toolbarState.pendingAction) {
            guard let action = toolbarState.pendingAction else { return }
            switch action {
            case .sendEmail:
                toolbarState.pendingAction = nil
                showSendSheet = true
            case .clearSentEmails:
                toolbarState.pendingAction = nil
                showClearConfirmation = true
            case .verifyIdentity, .deleteIdentity:
                break // handled by identity list
            }
        }
    }

    // MARK: - Header

    private var emailListHeader: some View {
        HStack {
            Text("Sent Emails")
                .font(.headline)

            Text("(\(emails.count))")
                .font(.headline)
                .foregroundStyle(.secondary)

            Spacer()

            if emails.count > 5 {
                SearchBarView(query: $searchText, placeholder: "Search emails")
                    .frame(maxWidth: 200)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var emailListContent: some View {
        if isLoading && emails.isEmpty {
            VStack(spacing: 12) {
                ProgressView("Loading sent emails...")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, emails.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                Button("Retry") { loadEmails(force: true) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if emails.isEmpty {
            EmptyStateView(icon: "tray", message: "No sent emails", secondaryMessage: "Emails sent via SES will appear here")
        } else {
            VSplitView {
                emailTable
                    .frame(minHeight: 150)

                if let email = selectedEmail {
                    emailDetailPane(email: email)
                        .frame(minHeight: 200)
                }
            }
        }
    }

    // MARK: - Email Table

    private var emailTable: some View {
        VStack(spacing: 0) {
            Table(filteredEmails, selection: $selectedEmailID) {
                TableColumn("From", value: \.source)
                    .width(min: 100, ideal: 150)
                TableColumn("To") { email in
                    Text(email.recipientSummary)
                }
                .width(min: 100, ideal: 150)
                TableColumn("Subject", value: \.subject)
                    .width(min: 150, ideal: 250)
                TableColumn("Timestamp") { email in
                    Text(email.formattedTimestamp)
                }
                .width(min: 120, ideal: 160)
            }

            Divider()
            HStack {
                Text("\(emails.count) email\(emails.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Email Detail

    private var selectedEmail: SESSentEmail? {
        guard let id = selectedEmailID else { return nil }
        return emails.first { $0.id == id }
    }

    private func emailDetailPane(email: SESSentEmail) -> some View {
        SESEmailDetailView(email: email)
    }

    private var filteredEmails: [SESSentEmail] {
        guard !searchText.isEmpty else { return emails }
        let query = searchText.lowercased()
        return emails.filter {
            $0.source.lowercased().contains(query) ||
            $0.subject.lowercased().contains(query) ||
            $0.recipientSummary.lowercased().contains(query)
        }
    }

    // MARK: - Data

    private func loadEmails(force: Bool = false, silent: Bool = false) {
        guard !isLoading else { return }
        if !force, let lastLoadTime, Date().timeIntervalSince(lastLoadTime) < 2.0 {
            return
        }
        if !silent {
            isLoading = true
            errorMessage = nil
        }
        Task {
            do {
                let loaded = try await service.listSentEmails()
                let sorted = loaded.sorted {
                    ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast)
                }
                if !silent || emails.count != sorted.count {
                    emails = sorted
                }
            } catch {
                if !silent {
                    errorMessage = error.localizedDescription
                }
            }
            if !silent {
                isLoading = false
                lastLoadTime = Date()
            }
        }
    }

    private func clearEmails() {
        Task {
            do {
                try await service.clearSentEmails()
                emails = []
                selectedEmailID = nil
            } catch {
                serviceError = error.asServiceError
            }
        }
    }
}

// MARK: - Email Detail View

struct SESEmailDetailView: View {
    let email: SESSentEmail
    @State private var bodyTab = "Text"

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    detailRow("From", value: email.source)
                    detailRow("To", value: email.destination.toAddresses.joined(separator: ", "))
                    if !email.destination.ccAddresses.isEmpty {
                        detailRow("CC", value: email.destination.ccAddresses.joined(separator: ", "))
                    }
                    if !email.destination.bccAddresses.isEmpty {
                        detailRow("BCC", value: email.destination.bccAddresses.joined(separator: ", "))
                    }
                    detailRow("Subject", value: email.subject)
                    detailRow("Timestamp", value: email.formattedTimestamp)

                    Divider()

                    // Body tab picker
                    if email.body.textData != nil && email.body.htmlData != nil {
                        Picker("Body", selection: $bodyTab) {
                            Text("Text").tag("Text")
                            Text("HTML").tag("HTML")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 150)
                    }

                    bodyContent
                }
                .padding(12)
            }
        }
    }

    @ViewBuilder
    private var bodyContent: some View {
        let content: String? = bodyTab == "Text" ? email.body.textData : email.body.htmlData
        if let content, !content.isEmpty {
            Text(content)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("No \(bodyTab.lowercased()) body")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
            Spacer()
        }
    }
}
