import Foundation

enum S3BrowserViewMode: String, CaseIterable, Identifiable {
    case list
    case icon
    case column

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .list: "list.bullet"
        case .icon: "square.grid.2x2"
        case .column: "rectangle.split.3x1"
        }
    }

    var label: String {
        switch self {
        case .list: "List"
        case .icon: "Icons"
        case .column: "Columns"
        }
    }
}
