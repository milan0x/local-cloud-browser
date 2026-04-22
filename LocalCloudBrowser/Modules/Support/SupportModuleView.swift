import SwiftUI

struct SupportModuleView: View {
    @EnvironmentObject private var client: CloudClient
    @EnvironmentObject private var appState: AppState
    @StateObject private var service: SupportService
    @StateObject private var toolbarState = SupportToolbarState()

    @State private var selectedCaseIDs: Set<SupportCase.ID> = []
    @State private var activeCase: SupportCase?

    // Session restore: captured once when the view is created
    @State private var restoreCaseId: String?

    init() {
        _service = StateObject(wrappedValue: SupportService())
        if let saved = LastSessionStore.load() {
            _restoreCaseId = State(initialValue: saved.supportCaseId)
        }
    }

    var body: some View {
        HSplitView {
            SupportCaseListView(
                service: service,
                toolbarState: toolbarState,
                selectedCaseIDs: $selectedCaseIDs,
                activeCase: $activeCase,
                restoreCaseId: restoreCaseId
            )
            .frame(minWidth: 260, idealWidth: 290, maxWidth: 350)

            Group {
                if let supportCase = activeCase {
                    SupportCaseDetailView(
                        service: service,
                        supportCase: supportCase
                    )
                } else {
                    EmptyDetailView(icon: "lifepreserver", message: "Select a case")
                }
            }
            .frame(minWidth: 140)
            .layoutPriority(1)
        }
        .toolbar {
            SupportToolbar(
                state: toolbarState,
                isReadOnly: appState.isReadOnly,
                hasCase: activeCase != nil
            )
        }
        .onChange(of: activeCase) {
            toolbarState.reset()
            LastSessionStore.saveSupportCase(activeCase?.caseId)
        }
        .onAppear {
            service.updateClient(client)
        }
    }
}

struct SupportModule: ServiceModule {
    let serviceName = "Support"
    let serviceIcon = "lifepreserver"
    let serviceEndpoint = "/support"

    func makeMainView() -> AnyView {
        AnyView(SupportModuleView())
    }
}
