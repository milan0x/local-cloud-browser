import SwiftUI

struct EventBridgePutEventView: View {
    @ObservedObject var service: EventBridgeService
    let eventBusName: String
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var source = ""
    @State private var detailType = ""
    @State private var detail = ""
    @State private var serviceError: ServiceError?
    @State private var isSaving = false
    @State private var showJsonHelper = false

    var body: some View {
        CreateFormScaffold(
            width: 520,
            isValid: isValid && !appState.isReadOnly,
            isCreating: isSaving,
            createLabel: "Send Event",
            serviceError: $serviceError,
            onCreate: save
        ) {
                LabeledContent("Event Bus") {
                    Text(eventBusName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                TextField("Source", text: $source, prompt: Text("com.myapp.service"))

                TextField("Detail Type", text: $detailType, prompt: Text("OrderPlaced"))

                JSONInputSection(text: $detail, isHelperShown: $showJsonHelper, config: .eventDetail)
        }
        .frame(minHeight: showJsonHelper ? 620 : 420)
        .animation(.easeInOut(duration: 0.2), value: showJsonHelper)
    }

    private var isValid: Bool {
        let src = source.trimmingCharacters(in: .whitespaces)
        let dt = detailType.trimmingCharacters(in: .whitespaces)
        guard !src.isEmpty && !dt.isEmpty else { return false }
        let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDetail.isEmpty {
            guard JSONInputSection.isValidJSON(trimmedDetail) else {
                return false
            }
        }
        return true
    }

    private func save() {
        isSaving = true
        serviceError = nil
        Task {
            do {
                var entry: [String: Any] = [
                    "Source": source.trimmingCharacters(in: .whitespaces),
                    "DetailType": detailType.trimmingCharacters(in: .whitespaces),
                    "EventBusName": eventBusName,
                ]
                let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedDetail.isEmpty {
                    entry["Detail"] = trimmedDetail
                }
                let result = try await service.putEvents(entries: [entry])
                if result.failedEntryCount > 0,
                   let firstError = result.entries.first(where: { $0.errorCode != nil }) {
                    serviceError = ServiceError(
                        code: firstError.errorCode ?? "PutEventsFailed",
                        message: firstError.errorMessage ?? "Failed to send event"
                    )
                    isSaving = false
                } else {
                    dismiss()
                }
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
