import SwiftUI

struct DynamoDBBrowserView: View {
    @ObservedObject var service: DynamoDBService
    @ObservedObject var toolbarState: DynamoDBToolbarState
    let table: DynamoDBTable
    let tableDetail: DynamoDBTableDetail

    enum BrowserTab: String, CaseIterable {
        case items = "Items"
        case streams = "Streams"
    }

    @State private var selectedTab: BrowserTab = .items

    var body: some View {
        VStack(spacing: 0) {
            if tableDetail.streamEnabled {
                SegmentedTabPicker(selection: $selectedTab, horizontalPadding: 0, verticalPadding: 6)
                    .frame(width: 200)

                Divider()
            }

            switch selectedTab {
            case .items:
                DynamoDBItemBrowserView(
                    service: service,
                    toolbarState: toolbarState,
                    table: table,
                    tableDetail: tableDetail
                )
            case .streams:
                DynamoDBStreamBrowserView(
                    service: service,
                    table: table,
                    tableDetail: tableDetail
                )
            }
        }
    }
}
