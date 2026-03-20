import SwiftUI

struct TranscribeModuleView: View {
    @EnvironmentObject private var client: CloudClient
    @EnvironmentObject private var appState: AppState
    @StateObject private var service: TranscribeService
    @StateObject private var toolbarState = TranscribeToolbarState()

    @State private var selectedJobIDs: Set<TranscriptionJob.ID> = []
    @State private var activeJob: TranscriptionJob?

    // Session restore: captured once when the view is created
    @State private var restoreJobName: String?

    init() {
        _service = StateObject(wrappedValue: TranscribeService())
        if let saved = LastSessionStore.load() {
            _restoreJobName = State(initialValue: saved.transcribeJobName)
        }
    }

    var body: some View {
        HSplitView {
            TranscribeJobListView(
                service: service,
                toolbarState: toolbarState,
                selectedJobIDs: $selectedJobIDs,
                activeJob: $activeJob,
                restoreJobName: restoreJobName
            )
            .frame(minWidth: 200, idealWidth: 280, maxWidth: 450)

            Group {
                if let job = activeJob {
                    TranscribeJobDetailPaneView(
                        service: service,
                        job: job
                    )
                } else {
                    EmptyDetailView(icon: "waveform", message: "Select a transcription job")
                }
            }
            .frame(minWidth: 400)
        }
        .toolbar {
            TranscribeToolbar(
                state: toolbarState,
                isReadOnly: appState.isReadOnly,
                hasJob: activeJob != nil
            )
        }
        .onChange(of: activeJob) {
            toolbarState.reset()
            LastSessionStore.saveTranscribeJob(activeJob?.jobName)
        }
        .onAppear {
            service.updateClient(client)
        }
    }
}

struct TranscribeModule: ServiceModule {
    let serviceName = "Transcribe"
    let serviceIcon = "waveform"
    let serviceEndpoint = "/transcribe"

    func makeMainView() -> AnyView {
        AnyView(TranscribeModuleView())
    }
}
