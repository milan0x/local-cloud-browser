import SwiftUI

/// Adds Cmd+F search cycling between list and detail panes.
/// Replaces duplicated `SearchTarget` enum, `cycleCmdF()`, and hidden Button in S3/SQS/SNS module views.
private struct CmdFSearchCyclingModifier<ID: Equatable>: ViewModifier {
    let hasDetail: Bool
    let activeItemID: ID?
    @Binding var listSearchFocusTrigger: Int
    @Binding var detailSearchFocusTrigger: Int

    @State private var lastSearchTarget = SearchTarget.detail

    private enum SearchTarget {
        case detail, list
    }

    func body(content: Content) -> some View {
        content
            .background {
                Button("") { cycleCmdF() }
                    .keyboardShortcut("f", modifiers: .command)
                    .frame(width: 0, height: 0)
            }
            .onChange(of: activeItemID) {
                lastSearchTarget = .detail
            }
    }

    private func cycleCmdF() {
        if hasDetail, lastSearchTarget != .detail {
            detailSearchFocusTrigger += 1
            lastSearchTarget = .detail
        } else if hasDetail {
            listSearchFocusTrigger += 1
            lastSearchTarget = .list
        } else {
            listSearchFocusTrigger += 1
            lastSearchTarget = .list
        }
    }
}

extension View {
    /// Adds Cmd+F cycling between list and detail search bars.
    func cmdFSearchCycling<ID: Equatable>(
        hasDetail: Bool,
        activeItemID: ID?,
        listSearchFocusTrigger: Binding<Int>,
        detailSearchFocusTrigger: Binding<Int>
    ) -> some View {
        modifier(CmdFSearchCyclingModifier(
            hasDetail: hasDetail,
            activeItemID: activeItemID,
            listSearchFocusTrigger: listSearchFocusTrigger,
            detailSearchFocusTrigger: detailSearchFocusTrigger
        ))
    }
}
