import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Per-row action invoked from the inline Actions column buttons.
enum ObjectAction {
    case download
    case preview
    case info
    case delete
    case openFolder
    case folderInfo
    case navigateParent
}

/// NSViewRepresentable wrapping an `AppTableView` / `NSScrollView` that renders
/// the S3 object listing. Modeled on the parent S3BrowserApp implementation to
/// keep large-selection performance (Cmd+A, bulk Delete) fast.
struct ObjectBrowserTableView: NSViewRepresentable {
    typealias RowItem = S3ObjectBrowserView.RowItem

    var rows: [RowItem]
    @Binding var selectedRowIDs: Set<String>
    @Binding var sortOrder: [KeyPathComparator<RowItem>]
    var isReadOnly: Bool
    var focusTrigger: Int
    var onDoubleClick: ((RowItem) -> Void)?
    var onContextMenu: ((Set<String>) -> NSMenu?)?
    var onSpacebar: ((Set<String>) -> Void)?
    var onDelete: ((Set<String>) -> Void)?
    var onActionButton: ((RowItem, ObjectAction) -> Void)?
    var onDragDownload: ((RowItem, URL) async throws -> Void)?

    private static let parentRowID = ".."

    /// Mapping between NSSortDescriptor keys and SwiftUI KeyPathComparators.
    private static let sortKeyMap: [(key: String, keyPath: PartialKeyPath<RowItem>)] = [
        ("name", \RowItem.name),
        ("kind", \RowItem.kind),
        ("sizeBytes", \RowItem.sizeBytes),
        ("dateValue", \RowItem.dateValue),
    ]

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = AppTableView()
        tableView.style = .inset
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.rowHeight = 24
        tableView.intercellSpacing = NSSize(width: 16, height: 2)
        tableView.autosaveName = "S3ObjectColumns"
        tableView.autosaveTableColumns = true

        // Columns
        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameCol.title = "Name"
        nameCol.minWidth = 200
        nameCol.width = 300
        nameCol.resizingMask = .userResizingMask
        nameCol.sortDescriptorPrototype = NSSortDescriptor(key: "name", ascending: true)
        tableView.addTableColumn(nameCol)

        let kindCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("kind"))
        kindCol.title = "Kind"
        kindCol.minWidth = 60
        kindCol.width = 90
        kindCol.resizingMask = .userResizingMask
        kindCol.sortDescriptorPrototype = NSSortDescriptor(key: "kind", ascending: true)
        tableView.addTableColumn(kindCol)

        let sizeCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("size"))
        sizeCol.title = "Size"
        sizeCol.minWidth = 60
        sizeCol.width = 80
        sizeCol.resizingMask = .userResizingMask
        sizeCol.sortDescriptorPrototype = NSSortDescriptor(key: "sizeBytes", ascending: true)
        tableView.addTableColumn(sizeCol)

        let dateCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("date"))
        dateCol.title = "Date Modified"
        dateCol.minWidth = 120
        dateCol.width = 155
        dateCol.resizingMask = .userResizingMask
        dateCol.sortDescriptorPrototype = NSSortDescriptor(key: "dateValue", ascending: false)
        tableView.addTableColumn(dateCol)

        let actionsCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("actions"))
        actionsCol.title = "Actions"
        actionsCol.minWidth = 100
        actionsCol.width = 110
        actionsCol.resizingMask = .userResizingMask
        tableView.addTableColumn(actionsCol)

        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.doubleAction = #selector(Coordinator.handleDoubleClick(_:))
        tableView.target = context.coordinator
        context.coordinator.tableView = tableView

        let coordinator = context.coordinator

        tableView.contextMenuProvider = { selectedIndices in
            let ids = coordinator.idsFor(indices: selectedIndices)
            return coordinator.parent.onContextMenu?(ids)
        }

        tableView.spacebarHandler = { selectedIndices in
            let ids = coordinator.idsFor(indices: selectedIndices)
            coordinator.parent.onSpacebar?(ids)
        }

        tableView.deleteHandler = { selectedIndices in
            let ids = coordinator.idsFor(indices: selectedIndices)
            coordinator.parent.onDelete?(ids)
        }

        // Outbound drag (drag a row onto Finder / another app). The inbound
        // drop target is handled by the owning SwiftUI .onDrop modifier, so
        // we intentionally do NOT call registerForDraggedTypes here.
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? AppTableView else { return }
        let coordinator = context.coordinator
        coordinator.parent = self

        // Reload when rows change
        let newIDs = rows.map(\.id)
        if coordinator.cachedRowIDs != newIDs {
            coordinator.cachedRowIDs = newIDs
            tableView.reloadData()
        }

        // Sync selection from SwiftUI → AppKit
        if !coordinator.isUpdatingSelection {
            let desiredIndices = IndexSet(rows.indices.filter { selectedRowIDs.contains(rows[$0].id) })
            if tableView.selectedRowIndexes != desiredIndices {
                coordinator.isUpdatingSelection = true
                tableView.selectRowIndexes(desiredIndices, byExtendingSelection: false)
                coordinator.isUpdatingSelection = false
            }
        }

        // Sync sort indicators
        if !coordinator.isUpdatingSortOrder {
            if let first = sortOrder.first {
                for col in tableView.tableColumns {
                    guard let desc = col.sortDescriptorPrototype else {
                        tableView.setIndicatorImage(nil, in: col)
                        continue
                    }
                    let mapped = Self.sortKeyMap.first { $0.key == desc.key }?.keyPath
                    if mapped == first.keyPath {
                        let ascending = first.order == .forward
                        tableView.setIndicatorImage(
                            NSImage(systemSymbolName: ascending ? "chevron.up" : "chevron.down", accessibilityDescription: nil),
                            in: col
                        )
                        tableView.highlightedTableColumn = col
                    } else {
                        tableView.setIndicatorImage(nil, in: col)
                    }
                }
            }
        }

        // Focus trigger — increments from the owning SwiftUI view request a
        // makeFirstResponder on the table.
        if focusTrigger != coordinator.lastFocusTrigger {
            coordinator.lastFocusTrigger = focusTrigger
            DispatchQueue.main.async {
                tableView.window?.makeFirstResponder(tableView)
            }
        }
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
        var parent: ObjectBrowserTableView
        var isUpdatingSelection = false
        var isUpdatingSortOrder = false
        var cachedRowIDs: [String] = []
        var lastFocusTrigger: Int = 0
        weak var tableView: AppTableView?

        init(parent: ObjectBrowserTableView) {
            self.parent = parent
        }

        func idsFor(indices: Set<Int>) -> Set<String> {
            Set(indices.compactMap { idx -> String? in
                guard idx >= 0, idx < parent.rows.count else { return nil }
                return parent.rows[idx].id
            })
        }

        // MARK: Data source

        func numberOfRows(in tableView: NSTableView) -> Int {
            parent.rows.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row >= 0, row < parent.rows.count else { return nil }
            let item = parent.rows[row]
            let colID = tableColumn?.identifier.rawValue ?? ""

            switch colID {
            case "name":
                return makeNameCell(tableView, item: item)
            case "kind":
                return makeTextCell(tableView, string: item.kind, id: "kindCell", secondary: true)
            case "size":
                return makeTextCell(tableView, string: item.size, id: "sizeCell", secondary: false)
            case "date":
                return makeTextCell(tableView, string: item.lastModified, id: "dateCell", secondary: false)
            case "actions":
                return makeActionsCell(tableView, item: item)
            default:
                return nil
            }
        }

        // MARK: Selection

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isUpdatingSelection, let tableView = notification.object as? NSTableView else { return }
            isUpdatingSelection = true
            let ids = Set(tableView.selectedRowIndexes.compactMap { idx -> String? in
                guard idx < parent.rows.count else { return nil }
                return parent.rows[idx].id
            })
            parent.selectedRowIDs = ids
            isUpdatingSelection = false
        }

        // MARK: Sorting

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard !isUpdatingSortOrder else { return }
            isUpdatingSortOrder = true
            defer { isUpdatingSortOrder = false }

            var newOrder: [KeyPathComparator<RowItem>] = []
            for desc in tableView.sortDescriptors {
                guard let key = desc.key,
                      let mapping = ObjectBrowserTableView.sortKeyMap.first(where: { $0.key == key }) else { continue }

                let order: SortOrder = desc.ascending ? .forward : .reverse
                if mapping.keyPath == \RowItem.name {
                    newOrder.append(KeyPathComparator(\RowItem.name, order: order))
                } else if mapping.keyPath == \RowItem.kind {
                    newOrder.append(KeyPathComparator(\RowItem.kind, order: order))
                } else if mapping.keyPath == \RowItem.sizeBytes {
                    newOrder.append(KeyPathComparator(\RowItem.sizeBytes, order: order))
                } else if mapping.keyPath == \RowItem.dateValue {
                    newOrder.append(KeyPathComparator(\RowItem.dateValue, order: order))
                }
            }
            if !newOrder.isEmpty {
                parent.sortOrder = newOrder
            }
        }

        // MARK: Double-click

        @objc func handleDoubleClick(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard row >= 0, row < parent.rows.count else { return }
            parent.onDoubleClick?(parent.rows[row])
        }

        // MARK: Drag source (drag-to-Finder)

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
            guard row < parent.rows.count else { return nil }
            let item = parent.rows[row]
            // Folders and the synthetic ".." row aren't draggable.
            guard !item.isFolder, item.id != ObjectBrowserTableView.parentRowID else { return nil }
            guard parent.onDragDownload != nil else { return nil }

            let fileType = UTType(filenameExtension: (item.name as NSString).pathExtension)?.identifier
                ?? UTType.data.identifier
            let provider = S3FilePromiseProvider(fileType: fileType, delegate: self)
            provider.userInfo = ["rowItem": item]
            return provider
        }

        // MARK: Cell Builders

        private func makeNameCell(_ tableView: NSTableView, item: RowItem) -> NSView {
            let id = NSUserInterfaceItemIdentifier("nameCell")
            let cell: NSTableCellView
            if let reused = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView {
                cell = reused
            } else {
                cell = NSTableCellView()
                cell.identifier = id

                let imageView = NSImageView()
                imageView.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(imageView)
                cell.imageView = imageView

                let textField = NSTextField(labelWithString: "")
                textField.translatesAutoresizingMaskIntoConstraints = false
                textField.lineBreakMode = .byTruncatingTail
                textField.font = .systemFont(ofSize: NSFont.systemFontSize)
                cell.addSubview(textField)
                cell.textField = textField

                NSLayoutConstraint.activate([
                    imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                    imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    imageView.widthAnchor.constraint(equalToConstant: 16),
                    imageView.heightAnchor.constraint(equalToConstant: 16),
                    textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                    textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                    textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
            }

            cell.imageView?.image = NSImage(systemSymbolName: item.icon, accessibilityDescription: item.isFolder ? "Folder" : "File")
            cell.imageView?.contentTintColor = .secondaryLabelColor
            cell.textField?.stringValue = item.name
            cell.textField?.textColor = .labelColor
            return cell
        }

        private func makeTextCell(_ tableView: NSTableView, string: String, id: String, secondary: Bool) -> NSView {
            let identifier = NSUserInterfaceItemIdentifier(id)
            if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
                reused.textField?.stringValue = string
                reused.textField?.textColor = secondary ? .secondaryLabelColor : .labelColor
                return reused
            }
            let cell = NSTableCellView()
            cell.identifier = identifier
            let textField = NSTextField(labelWithString: string)
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail
            textField.font = .systemFont(ofSize: NSFont.systemFontSize)
            textField.textColor = secondary ? .secondaryLabelColor : .labelColor
            cell.addSubview(textField)
            cell.textField = textField
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }

        private func makeActionsCell(_ tableView: NSTableView, item: RowItem) -> NSView {
            let container = NSView()
            container.translatesAutoresizingMaskIntoConstraints = false

            let stack = NSStackView()
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.orientation = .horizontal
            stack.spacing = 6
            container.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
                stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])

            let itemID = item.id

            if item.id == ObjectBrowserTableView.parentRowID {
                stack.addArrangedSubview(makeActionButton("arrow.up", tooltip: "Go to Parent", itemID: itemID, action: .navigateParent))
            } else if item.isFolder {
                stack.addArrangedSubview(makeActionButton("arrow.right", tooltip: "Open", itemID: itemID, action: .openFolder))
                stack.addArrangedSubview(makeActionButton("info.circle", tooltip: "Folder Info", itemID: itemID, action: .folderInfo))
                if !parent.isReadOnly {
                    stack.addArrangedSubview(makeActionButton("trash", tooltip: "Delete Folder", itemID: itemID, action: .delete, tint: .systemRed))
                }
            } else {
                stack.addArrangedSubview(makeActionButton("square.and.arrow.down", tooltip: "Download", itemID: itemID, action: .download))
                stack.addArrangedSubview(makeActionButton("eye", tooltip: "Quick Look", itemID: itemID, action: .preview))
                stack.addArrangedSubview(makeActionButton("info.circle", tooltip: "Metadata", itemID: itemID, action: .info))
                if !parent.isReadOnly {
                    stack.addArrangedSubview(makeActionButton("trash", tooltip: "Delete", itemID: itemID, action: .delete, tint: .systemRed))
                }
            }
            return container
        }

        private func makeActionButton(_ symbolName: String, tooltip: String, itemID: String, action: ObjectAction, tint: NSColor? = nil) -> NSButton {
            let button = NSButton()
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip)
            button.isBordered = false
            button.toolTip = tooltip
            button.imageScaling = .scaleProportionallyUpOrDown
            if let tint { button.contentTintColor = tint }
            button.widthAnchor.constraint(equalToConstant: 18).isActive = true
            button.heightAnchor.constraint(equalToConstant: 18).isActive = true
            button.target = self
            button.action = #selector(actionButtonClicked(_:))
            objc_setAssociatedObject(button, &objectBrowserActionItemIDKey, itemID, .OBJC_ASSOCIATION_RETAIN)
            objc_setAssociatedObject(button, &objectBrowserActionTypeKey, action, .OBJC_ASSOCIATION_RETAIN)
            return button
        }

        @objc func actionButtonClicked(_ sender: NSButton) {
            guard let itemID = objc_getAssociatedObject(sender, &objectBrowserActionItemIDKey) as? String,
                  let action = objc_getAssociatedObject(sender, &objectBrowserActionTypeKey) as? ObjectAction,
                  let item = parent.rows.first(where: { $0.id == itemID }) else { return }
            parent.onActionButton?(item, action)
        }
    }
}

// Associated-object keys for attaching (itemID, action) to per-row action buttons.
nonisolated(unsafe) private var objectBrowserActionItemIDKey: UInt8 = 0
nonisolated(unsafe) private var objectBrowserActionTypeKey: UInt8 = 0

// MARK: - File promise provider for drag-to-Finder

final class S3FilePromiseProvider: NSFilePromiseProvider, @unchecked Sendable {}

extension ObjectBrowserTableView.Coordinator: NSFilePromiseProviderDelegate {
    nonisolated func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        guard let info = filePromiseProvider.userInfo as? [String: Any],
              let item = info["rowItem"] as? ObjectBrowserTableView.RowItem else {
            return "download"
        }
        return item.name
    }

    nonisolated func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping @Sendable (Error?) -> Void) {
        guard let info = filePromiseProvider.userInfo as? [String: Any],
              let item = info["rowItem"] as? ObjectBrowserTableView.RowItem else {
            completionHandler(NSError(
                domain: "LocalCloudBrowser.S3",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing drag item metadata"]
            ))
            return
        }

        Task { @MainActor in
            do {
                try await self.parent.onDragDownload?(item, url)
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
        }
    }

    nonisolated func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        return queue
    }
}
