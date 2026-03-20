import SwiftUI

struct DynamoDBModuleView: View {
    @EnvironmentObject private var client: CloudClient
    @EnvironmentObject private var appState: AppState
    @StateObject private var service = DynamoDBService()
    @StateObject private var toolbarState = DynamoDBToolbarState()

    @State private var selectedTableIDs: Set<DynamoDBTable.ID> = []
    @State private var activeTable: DynamoDBTable?
    @State private var tableDetail: DynamoDBTableDetail?

    // Session restore: captured once when the view is created
    @State private var restoreTableName: String?

    init() {
        if let saved = LastSessionStore.load() {
            _restoreTableName = State(initialValue: saved.dynamodbTableName)
        }
    }

    var body: some View {
        HSplitView {
            DynamoDBTableListView(
                service: service,
                toolbarState: toolbarState,
                selectedTableIDs: $selectedTableIDs,
                activeTable: $activeTable,
                tableDetail: $tableDetail,
                restoreTableName: restoreTableName
            )
            .frame(minWidth: 200, idealWidth: 280, maxWidth: 450)

            Group {
                if let table = activeTable, let detail = tableDetail {
                    DynamoDBBrowserView(
                        service: service,
                        toolbarState: toolbarState,
                        table: table,
                        tableDetail: detail
                    )
                } else {
                    EmptyDetailView(icon: "tablecells", message: "Select a table")
                }
            }
            .frame(minWidth: 400)
        }
        .toolbar {
            DynamoDBToolbar(
                state: toolbarState,
                isReadOnly: appState.isReadOnly,
                hasTable: activeTable != nil
            )
        }
        .onChange(of: activeTable) {
            toolbarState.reset()
            LastSessionStore.saveDynamoDBTable(activeTable?.tableName)
            if let table = activeTable {
                loadTableDetail(table.tableName)
            } else {
                tableDetail = nil
            }
        }
        .onAppear {
            service.updateClient(client)
        }
    }

    private func loadTableDetail(_ tableName: String) {
        Task {
            do {
                let detail = try await service.describeTable(tableName: tableName)
                if activeTable?.tableName == tableName {
                    tableDetail = detail
                }
            } catch {
                Log.warn("Failed to load table detail: \(error.localizedDescription)", category: "DynamoDB")
            }
        }
    }
}

struct DynamoDBModule: ServiceModule {
    let serviceName = "DynamoDB"
    let serviceIcon = "tablecells"
    let serviceEndpoint = "/dynamodb"

    func makeMainView() -> AnyView {
        AnyView(DynamoDBModuleView())
    }
}
