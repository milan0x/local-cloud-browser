import AppKit
import SwiftUI

// MARK: - EditableTableView

/// NSTableView subclass that allows double-click to reach text fields for inline editing.
final class EditableTableView: NSTableView {
    override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool {
        if responder is EditableTextField { return true }
        return super.validateProposedFirstResponder(responder, for: event)
    }
}

// MARK: - EditableTextField

/// NSTextField subclass for inline cell editing. Read-only by default; double-click activates editing.
final class EditableTextField: NSTextField {
    var originalValue: String = ""
    var columnIdentifier: String = ""
    var rowIndex: Int = -1
    var isKeyColumn: Bool = false
    var isInlineEditable: Bool = true
    var isDraftCell: Bool = false
    var normalAttributedString: NSAttributedString?

    /// Recolor text for selection state
    func updateForSelection(_ isSelected: Bool) {
        guard !isEditable, let normal = normalAttributedString else { return }
        if isSelected {
            // Replace all foreground colors with white
            let white = NSMutableAttributedString(attributedString: normal)
            white.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: white.length)) { _, range, _ in
                white.addAttribute(.foregroundColor, value: NSColor.white, range: range)
            }
            super.attributedStringValue = white
        } else {
            super.attributedStringValue = normal
        }
    }

    override func mouseDown(with event: NSEvent) {
        // Draft cells: single click activates editing
        if isDraftCell && isEnabled {
            beginEditing()
            return
        }
        if event.clickCount == 2 && !isKeyColumn && isInlineEditable && isEnabled {
            beginEditing()
            return
        }
        super.mouseDown(with: event)
    }

    func beginEditing() {
        originalValue = stringValue
        isEditable = true
        isSelectable = true
        isBezeled = true
        bezelStyle = .roundedBezel
        drawsBackground = true
        backgroundColor = .textBackgroundColor
        selectText(nil)
    }

    func endEditing(revert: Bool) {
        if revert {
            stringValue = originalValue
        }
        isEditable = false
        isSelectable = false
        isBezeled = false
        drawsBackground = false
        backgroundColor = .clear
        window?.makeFirstResponder(superview?.superview) // return focus to table
    }
}

// MARK: - SelectionAwareCellView

/// Cell view that updates text color when row is selected/deselected.
private final class SelectionAwareCellView: NSTableCellView {
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            if let tf = textField as? EditableTextField {
                tf.updateForSelection(backgroundStyle == .emphasized)
            }
        }
    }
}

// MARK: - DraftRowView

/// Custom row view with a subtle accent tint to distinguish the draft row.
private final class DraftRowView: NSTableRowView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlAccentColor.withAlphaComponent(0.06).setFill()
        bounds.fill()
        super.draw(dirtyRect)
    }
}

// MARK: - DynamoDBItemGrid

struct DynamoDBItemGrid: NSViewRepresentable {
    let columns: [GridColumn]
    let items: [DynamoDBItem]
    let tableDetail: DynamoDBTableDetail
    let isReadOnly: Bool
    @Binding var selectedItemIDs: Set<String>

    // Sorting
    var sortColumn: String?
    var sortAscending: Bool = true
    var onSort: (String) -> Void = { _ in }

    // Inline draft row
    var isDraftRowActive: Bool = false
    var saveDraftCounter: Int = 0
    var onSaveDraft: ([String: String]) -> Void = { _ in }
    var onCancelDraft: () -> Void = {}

    // Callbacks
    var onCellEdit: (_ rowID: String, _ column: String, _ newValue: String) -> Void = { _, _, _ in }
    var onViewDetail: (DynamoDBItem) -> Void = { _ in }
    var onDeleteItems: ([DynamoDBItem]) -> Void = { _ in }
    var onEditComplex: (DynamoDBItem) -> Void = { _ in }
    var onCopyJSON: (DynamoDBItem) -> Void = { _ in }
    var onCopyItemKey: (DynamoDBItem) -> Void = { _ in }
    var onCopyGetItemCLI: (DynamoDBItem) -> Void = { _ in }
    var onCopyPutItemCLI: (DynamoDBItem) -> Void = { _ in }
    var onPutItem: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = EditableTableView()
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.style = .plain
        tableView.rowHeight = 32
        tableView.intercellSpacing = NSSize(width: 12, height: 2)
        tableView.gridStyleMask = [.solidHorizontalGridLineMask, .solidVerticalGridLineMask]
        tableView.gridColor = .separatorColor.withAlphaComponent(0.4)
        tableView.headerView = NSTableHeaderView()
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true

        // Build the initial menu for right-click
        let menu = NSMenu()
        menu.delegate = context.coordinator
        tableView.menu = menu

        context.coordinator.tableView = tableView
        context.coordinator.syncColumns(tableView: tableView, columns: columns)
        context.coordinator.syncSortIndicator()

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = tableView
        scrollView.drawsBackground = false

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        guard let tableView = coordinator.tableView else { return }

        // Process save draft trigger (must run even during editing)
        if saveDraftCounter != coordinator.lastSaveDraftCounter {
            coordinator.lastSaveDraftCounter = saveDraftCounter
            if isDraftRowActive {
                tableView.window?.endEditing(for: nil)
                coordinator.saveDraft()
            }
        }

        guard !coordinator.isUpdating else { return }

        // Handle draft state changes
        let draftChanged = isDraftRowActive != coordinator.wasDraftActive
        if draftChanged {
            coordinator.wasDraftActive = isDraftRowActive
            if isDraftRowActive {
                coordinator.draftValues = [:]
                coordinator.cachedItems = items
                coordinator.isUpdating = true
                tableView.reloadData()
                coordinator.isUpdating = false
                let draftRow = items.count
                tableView.scrollRowToVisible(draftRow)
                // Auto-focus PK cell
                DispatchQueue.main.async {
                    self.focusDraftPKCell(tableView: tableView, draftRow: draftRow)
                }
            } else {
                coordinator.draftValues = [:]
                coordinator.cachedItems = items
                coordinator.isUpdating = true
                tableView.reloadData()
                coordinator.isUpdating = false
                syncSelectionToTableView(tableView: tableView, coordinator: coordinator)
            }
            coordinator.isReadOnly = isReadOnly
            return
        }

        // Skip reload if actively editing a cell
        if tableView.currentEditor() != nil { return }

        // Diff columns
        let oldColumnNames = coordinator.cachedColumnNames
        let newColumnNames = columns.map(\.name)
        if oldColumnNames != newColumnNames {
            coordinator.syncColumns(tableView: tableView, columns: columns)
        }

        // Diff items
        let oldIDs = coordinator.cachedItems.map { $0.id(keySchema: tableDetail.keySchema) }
        let newIDs = items.map { $0.id(keySchema: tableDetail.keySchema) }
        if oldIDs != newIDs || coordinator.cachedItems != items {
            // Flush any pending field editor
            tableView.window?.endEditing(for: nil)

            coordinator.cachedItems = items
            coordinator.isUpdating = true
            tableView.reloadData()
            coordinator.isUpdating = false

            // Restore selection
            syncSelectionToTableView(tableView: tableView, coordinator: coordinator)
        }

        // Sync read-only
        coordinator.isReadOnly = isReadOnly

        // Sync sort indicator
        coordinator.syncSortIndicator()
    }

    private func focusDraftPKCell(tableView: EditableTableView, draftRow: Int) {
        let pkName = tableDetail.partitionKey?.attributeName ?? ""
        let pkColIdx = tableView.column(withIdentifier: NSUserInterfaceItemIdentifier(pkName))
        if pkColIdx >= 0,
           let cellView = tableView.view(atColumn: pkColIdx, row: draftRow, makeIfNecessary: true) as? NSTableCellView,
           let tf = cellView.textField as? EditableTextField {
            tf.beginEditing()
        }
    }

    private func syncSelectionToTableView(tableView: EditableTableView, coordinator: Coordinator) {
        coordinator.isUpdating = true
        let indexes = NSMutableIndexSet()
        for (idx, item) in items.enumerated() {
            if selectedItemIDs.contains(item.id(keySchema: tableDetail.keySchema)) {
                indexes.add(idx)
            }
        }
        tableView.selectRowIndexes(indexes as IndexSet, byExtendingSelection: false)
        coordinator.isUpdating = false
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource, NSTextFieldDelegate, NSMenuDelegate {
        var parent: DynamoDBItemGrid
        weak var tableView: EditableTableView?
        var cachedItems: [DynamoDBItem] = []
        var cachedColumnNames: [String] = []
        var isUpdating = false
        var isReadOnly = false
        private var committedEdit = false

        // Draft row state
        var draftValues: [String: String] = [:]
        var wasDraftActive = false
        var lastSaveDraftCounter: Int = 0

        init(parent: DynamoDBItemGrid) {
            self.parent = parent
            self.cachedItems = parent.items
            self.isReadOnly = parent.isReadOnly
        }

        // MARK: Sort Support

        func syncSortIndicator() {
            guard let tableView else { return }
            // Clear all indicators
            for col in tableView.tableColumns {
                tableView.setIndicatorImage(nil, in: col)
            }
            // Set current sort indicator
            if let sortCol = parent.sortColumn {
                let id = NSUserInterfaceItemIdentifier(sortCol)
                if let col = tableView.tableColumns.first(where: { $0.identifier == id }) {
                    let img = parent.sortAscending
                        ? NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "Ascending")
                        : NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Descending")
                    tableView.setIndicatorImage(img, in: col)
                }
            }
        }

        @objc func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
            parent.onSort(tableColumn.identifier.rawValue)
            // Indicator will update on next updateNSView cycle
        }

        // MARK: Column Management

        func syncColumns(tableView: EditableTableView, columns: [GridColumn]) {
            // Remove existing columns
            for col in tableView.tableColumns.reversed() {
                tableView.removeTableColumn(col)
            }

            for gridCol in columns {
                let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(gridCol.name))
                col.title = gridCol.name
                col.isEditable = false
                col.resizingMask = .userResizingMask

                if gridCol.isPartitionKey || gridCol.isSortKey {
                    col.width = 180
                    col.minWidth = 100
                    let keyType = gridCol.isPartitionKey ? "PK" : "SK"
                    col.title = "\(gridCol.name) (\(keyType))"
                } else {
                    col.width = 160
                    col.minWidth = 80
                }

                tableView.addTableColumn(col)
            }

            cachedColumnNames = columns.map(\.name)
            tableView.reloadData()
        }

        // MARK: NSTableViewDataSource

        @objc func numberOfRows(in tableView: NSTableView) -> Int {
            parent.items.count + (parent.isDraftRowActive ? 1 : 0)
        }

        @objc func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn else { return nil }

            let columnName = tableColumn.identifier.rawValue
            let isDraftRow = parent.isDraftRowActive && row == parent.items.count

            guard isDraftRow || row < parent.items.count else { return nil }

            let cellID = NSUserInterfaceItemIdentifier("DynamoDBCell")
            let cellView: SelectionAwareCellView
            let textField: EditableTextField

            if let reused = tableView.makeView(withIdentifier: cellID, owner: nil) as? SelectionAwareCellView,
               let existingTF = reused.textField as? EditableTextField {
                cellView = reused
                textField = existingTF
            } else {
                let tf = EditableTextField()
                tf.isBordered = false
                tf.isBezeled = false
                tf.drawsBackground = false
                tf.isEditable = false
                tf.isSelectable = false
                tf.lineBreakMode = .byTruncatingTail
                tf.cell?.truncatesLastVisibleLine = true
                tf.translatesAutoresizingMaskIntoConstraints = false

                let cv = SelectionAwareCellView()
                cv.identifier = cellID
                cv.textField = tf
                cv.addSubview(tf)

                NSLayoutConstraint.activate([
                    tf.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 8),
                    tf.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -8),
                    tf.centerYAnchor.constraint(equalTo: cv.centerYAnchor),
                ])

                cellView = cv
                textField = tf
            }

            // Configure common properties
            textField.delegate = self
            textField.columnIdentifier = columnName
            textField.rowIndex = row
            textField.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

            if isDraftRow {
                // Draft row: all cells editable, no type badge, placeholder text
                textField.isDraftCell = true
                textField.isKeyColumn = false
                textField.isInlineEditable = true
                textField.isEnabled = true
                textField.placeholderString = columnName

                if let draftVal = draftValues[columnName], !draftVal.isEmpty {
                    let attrStr = NSAttributedString(
                        string: draftVal,
                        attributes: [
                            .foregroundColor: NSColor.labelColor,
                            .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
                        ]
                    )
                    textField.normalAttributedString = attrStr
                    textField.attributedStringValue = attrStr
                } else {
                    textField.normalAttributedString = nil
                    textField.stringValue = ""
                }
                textField.toolTip = nil
            } else {
                // Normal item row
                textField.isDraftCell = false
                textField.placeholderString = nil
                guard row < parent.items.count else { return nil }
                let item = parent.items[row]
                let value = item.attributes[columnName]

                let isKey = parent.columns.first(where: { $0.name == columnName })
                    .map { $0.isPartitionKey || $0.isSortKey } ?? false
                textField.isKeyColumn = isKey

                if let value {
                    textField.isInlineEditable = value.isInlineEditable && !isKey
                    let attrStr = attributedString(for: value, isKey: isKey)
                    textField.normalAttributedString = attrStr
                    textField.attributedStringValue = attrStr
                    textField.toolTip = value.displayString
                    textField.isEnabled = !isReadOnly
                } else {
                    textField.isInlineEditable = false
                    let attrStr = NSAttributedString(
                        string: "\u{2014}",
                        attributes: [
                            .foregroundColor: NSColor.quaternaryLabelColor,
                            .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .light),
                        ]
                    )
                    textField.normalAttributedString = attrStr
                    textField.attributedStringValue = attrStr
                    textField.toolTip = nil
                    textField.isEnabled = false
                }
            }

            // Ensure clean state (no leftover editing state from reuse)
            textField.isEditable = false
            textField.isSelectable = false
            textField.isBezeled = false
            textField.drawsBackground = false
            textField.backgroundColor = .clear

            return cellView
        }

        // MARK: Cell Display

        private func attributedString(for value: AttributeValue, isKey: Bool = false) -> NSAttributedString {
            let result = NSMutableAttributedString()
            let fontSize = NSFont.systemFontSize
            let monoFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: isKey ? .medium : .regular)
            let badgeFont = NSFont.monospacedSystemFont(ofSize: fontSize - 2, weight: .semibold)

            let badgeColor: NSColor
            switch value {
            case .string: badgeColor = .systemBlue
            case .number: badgeColor = .systemGreen
            case .bool: badgeColor = .systemPurple
            case .null: badgeColor = .systemGray
            case .list, .map: badgeColor = .systemOrange
            case .stringSet, .numberSet, .binarySet: badgeColor = .systemTeal
            case .binary: badgeColor = .systemOrange
            }

            // Type badge
            let badge = NSAttributedString(
                string: value.typeBadge + " ",
                attributes: [
                    .foregroundColor: badgeColor.withAlphaComponent(0.8),
                    .font: badgeFont,
                ]
            )
            result.append(badge)

            // Value text
            let displayText: String
            switch value {
            case .map, .list, .stringSet, .numberSet, .binarySet:
                let full = value.displayString
                displayText = full.count > 40 ? String(full.prefix(40)) + "..." : full
            default:
                displayText = value.displayString
            }

            let valueAttr = NSAttributedString(
                string: displayText,
                attributes: [
                    .foregroundColor: NSColor.labelColor,
                    .font: monoFont,
                ]
            )
            result.append(valueAttr)

            return result
        }

        // MARK: NSTableViewDelegate

        @objc func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isUpdating, let tableView else { return }
            isUpdating = true
            var newSelection: Set<String> = []
            for idx in tableView.selectedRowIndexes {
                if idx < parent.items.count {
                    newSelection.insert(parent.items[idx].id(keySchema: parent.tableDetail.keySchema))
                }
            }
            parent.selectedItemIDs = newSelection
            isUpdating = false
        }

        // MARK: NSTextFieldDelegate (inline editing)

        @objc func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard let textField = control as? EditableTextField else { return false }
            let isDraft = textField.isDraftCell

            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                // Enter → commit edit
                committedEdit = true
                let newValue = textField.stringValue
                let currentCol = textField.columnIdentifier
                textField.endEditing(revert: false)
                if isDraft {
                    draftValues[currentCol] = newValue
                    moveToNextDraftCell(from: currentCol, forward: true)
                } else {
                    let rowID = itemIDForRow(textField.rowIndex)
                    if let rowID, newValue != textField.originalValue {
                        parent.onCellEdit(rowID, currentCol, newValue)
                    }
                }
                return true
            }

            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                // Escape → revert
                committedEdit = true
                textField.endEditing(revert: true)
                return true
            }

            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                // Tab → commit and move to next editable cell
                committedEdit = true
                let newValue = textField.stringValue
                let currentCol = textField.columnIdentifier
                textField.endEditing(revert: false)
                if isDraft {
                    draftValues[currentCol] = newValue
                    moveToNextDraftCell(from: currentCol, forward: true)
                } else {
                    let rowID = itemIDForRow(textField.rowIndex)
                    if let rowID, newValue != textField.originalValue {
                        parent.onCellEdit(rowID, currentCol, newValue)
                    }
                    moveToNextEditableCell(from: textField.rowIndex, column: currentCol, forward: true)
                }
                return true
            }

            if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
                // Shift-Tab → commit and move to previous editable cell
                committedEdit = true
                let newValue = textField.stringValue
                let currentCol = textField.columnIdentifier
                textField.endEditing(revert: false)
                if isDraft {
                    draftValues[currentCol] = newValue
                    moveToNextDraftCell(from: currentCol, forward: false)
                } else {
                    let rowID = itemIDForRow(textField.rowIndex)
                    if let rowID, newValue != textField.originalValue {
                        parent.onCellEdit(rowID, currentCol, newValue)
                    }
                    moveToNextEditableCell(from: textField.rowIndex, column: currentCol, forward: false)
                }
                return true
            }

            return false
        }

        @objc func controlTextDidEndEditing(_ notification: Notification) {
            // Handles click-away: commit if not already committed via Enter/Escape/Tab
            guard let textField = notification.object as? EditableTextField else { return }
            if committedEdit {
                committedEdit = false
                return
            }
            let newValue = textField.stringValue
            textField.endEditing(revert: false)
            if textField.isDraftCell {
                draftValues[textField.columnIdentifier] = newValue
            } else {
                let rowID = itemIDForRow(textField.rowIndex)
                if let rowID, newValue != textField.originalValue {
                    parent.onCellEdit(rowID, textField.columnIdentifier, newValue)
                }
            }
        }

        private func itemIDForRow(_ row: Int) -> String? {
            guard row >= 0 && row < parent.items.count else { return nil }
            return parent.items[row].id(keySchema: parent.tableDetail.keySchema)
        }

        private func moveToNextEditableCell(from row: Int, column: String, forward: Bool) {
            guard tableView != nil else { return }
            let colNames = cachedColumnNames
            guard let colIdx = colNames.firstIndex(of: column) else { return }

            var r = row
            var c = colIdx

            while true {
                if forward {
                    c += 1
                    if c >= colNames.count { c = 0; r += 1 }
                    if r >= parent.items.count { return } // past end
                } else {
                    c -= 1
                    if c < 0 { c = colNames.count - 1; r -= 1 }
                    if r < 0 { return } // past beginning
                }

                // Check if this cell is editable
                let colName = colNames[c]
                let gridCol = parent.columns.first(where: { $0.name == colName })
                let isKey = gridCol.map { $0.isPartitionKey || $0.isSortKey } ?? false
                if isKey { continue }

                let item = parent.items[r]
                if let value = item.attributes[colName], value.isInlineEditable {
                    // Found next editable cell — activate it
                    DispatchQueue.main.async { [weak self] in
                        guard let tableView = self?.tableView else { return }
                        let nsColIdx = tableView.column(withIdentifier: NSUserInterfaceItemIdentifier(colName))
                        guard nsColIdx >= 0 else { return }
                        if let cellView = tableView.view(atColumn: nsColIdx, row: r, makeIfNecessary: true) as? NSTableCellView,
                           let tf = cellView.textField as? EditableTextField {
                            tf.beginEditing()
                        }
                    }
                    return
                }

                // If we've wrapped around fully, stop
                if r == row && c == colIdx { return }
            }
        }

        // MARK: Draft Row Helpers

        private func moveToNextDraftCell(from column: String, forward: Bool) {
            guard tableView != nil else { return }
            let colNames = cachedColumnNames
            guard let colIdx = colNames.firstIndex(of: column) else { return }
            let draftRow = parent.items.count

            var c = colIdx
            if forward {
                c += 1
                if c >= colNames.count { return }
            } else {
                c -= 1
                if c < 0 { return }
            }

            let colName = colNames[c]
            DispatchQueue.main.async { [weak self] in
                guard let tableView = self?.tableView else { return }
                let nsColIdx = tableView.column(withIdentifier: NSUserInterfaceItemIdentifier(colName))
                guard nsColIdx >= 0 else { return }
                if let cellView = tableView.view(atColumn: nsColIdx, row: draftRow, makeIfNecessary: true) as? NSTableCellView,
                   let tf = cellView.textField as? EditableTextField {
                    tf.beginEditing()
                }
            }
        }

        func saveDraft() {
            guard parent.isDraftRowActive else { return }
            parent.onSaveDraft(draftValues)
        }

        // MARK: Row View (draft row background)

        @objc func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            if parent.isDraftRowActive && row == parent.items.count {
                return DraftRowView()
            }
            return nil
        }

        // MARK: NSMenuDelegate (context menu)

        @objc func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let tableView else { return }

            let clickedRow = tableView.clickedRow
            let selectedRows = tableView.selectedRowIndexes

            // Right-click on draft row
            if parent.isDraftRowActive && clickedRow == parent.items.count {
                let save = NSMenuItem(title: "Save New Item", action: #selector(menuSaveDraft(_:)), keyEquivalent: "")
                save.target = self
                save.isEnabled = !isReadOnly
                menu.addItem(save)

                let cancel = NSMenuItem(title: "Cancel New Item", action: #selector(menuCancelDraft(_:)), keyEquivalent: "")
                cancel.target = self
                menu.addItem(cancel)
                return
            }

            if clickedRow < 0 {
                // Right-click on empty area
                let putItem = NSMenuItem(title: "Put Item", action: #selector(menuPutItem(_:)), keyEquivalent: "")
                putItem.target = self
                putItem.isEnabled = !isReadOnly
                menu.addItem(putItem)
                return
            }

            // If clicked row is not in selection, select just that row
            let effectiveRows: IndexSet
            if selectedRows.contains(clickedRow) {
                effectiveRows = selectedRows
            } else {
                effectiveRows = IndexSet(integer: clickedRow)
            }

            if effectiveRows.count == 1, let row = effectiveRows.first, row < parent.items.count {
                let item = parent.items[row]

                let viewDetail = NSMenuItem(title: "View Details", action: #selector(menuViewDetail(_:)), keyEquivalent: "")
                viewDetail.target = self
                viewDetail.representedObject = item
                menu.addItem(viewDetail)

                menu.addItem(NSMenuItem.separator())

                let copyJSON = NSMenuItem(title: "Copy as JSON", action: #selector(menuCopyJSON(_:)), keyEquivalent: "")
                copyJSON.target = self
                copyJSON.representedObject = item
                menu.addItem(copyJSON)

                let copyKey = NSMenuItem(title: "Copy Item Key", action: #selector(menuCopyItemKey(_:)), keyEquivalent: "")
                copyKey.target = self
                copyKey.representedObject = item
                menu.addItem(copyKey)

                let cliMenu = NSMenu()
                let getItem = NSMenuItem(title: "Get Item", action: #selector(menuCopyGetItemCLI(_:)), keyEquivalent: "")
                getItem.target = self
                getItem.representedObject = item
                cliMenu.addItem(getItem)

                let putItemCLI = NSMenuItem(title: "Put Item", action: #selector(menuCopyPutItemCLI(_:)), keyEquivalent: "")
                putItemCLI.target = self
                putItemCLI.representedObject = item
                cliMenu.addItem(putItemCLI)

                let cliParent = NSMenuItem(title: "Copy as AWS CLI", action: nil, keyEquivalent: "")
                cliParent.submenu = cliMenu
                menu.addItem(cliParent)

                menu.addItem(NSMenuItem.separator())

                let edit = NSMenuItem(title: "Edit", action: #selector(menuEdit(_:)), keyEquivalent: "")
                edit.target = self
                edit.representedObject = item
                edit.isEnabled = !isReadOnly
                menu.addItem(edit)

                let delete = NSMenuItem(title: "Delete", action: #selector(menuDelete(_:)), keyEquivalent: "")
                delete.target = self
                delete.representedObject = [item]
                delete.isEnabled = !isReadOnly
                menu.addItem(delete)
            } else if effectiveRows.count > 1 {
                let selected = effectiveRows.compactMap { idx -> DynamoDBItem? in
                    idx < parent.items.count ? parent.items[idx] : nil
                }
                let delete = NSMenuItem(title: "Delete \(selected.count) Items", action: #selector(menuDeleteMultiple(_:)), keyEquivalent: "")
                delete.target = self
                delete.representedObject = selected
                delete.isEnabled = !isReadOnly
                menu.addItem(delete)
            }
        }

        @objc private func menuViewDetail(_ sender: NSMenuItem) {
            guard let item = sender.representedObject as? DynamoDBItem else { return }
            parent.onViewDetail(item)
        }

        @objc private func menuCopyJSON(_ sender: NSMenuItem) {
            guard let item = sender.representedObject as? DynamoDBItem else { return }
            parent.onCopyJSON(item)
        }

        @objc private func menuCopyItemKey(_ sender: NSMenuItem) {
            guard let item = sender.representedObject as? DynamoDBItem else { return }
            parent.onCopyItemKey(item)
        }

        @objc private func menuCopyGetItemCLI(_ sender: NSMenuItem) {
            guard let item = sender.representedObject as? DynamoDBItem else { return }
            parent.onCopyGetItemCLI(item)
        }

        @objc private func menuCopyPutItemCLI(_ sender: NSMenuItem) {
            guard let item = sender.representedObject as? DynamoDBItem else { return }
            parent.onCopyPutItemCLI(item)
        }

        @objc private func menuEdit(_ sender: NSMenuItem) {
            guard let item = sender.representedObject as? DynamoDBItem else { return }
            parent.onEditComplex(item)
        }

        @objc private func menuDelete(_ sender: NSMenuItem) {
            guard let items = sender.representedObject as? [DynamoDBItem] else { return }
            parent.onDeleteItems(items)
        }

        @objc private func menuDeleteMultiple(_ sender: NSMenuItem) {
            guard let items = sender.representedObject as? [DynamoDBItem] else { return }
            parent.onDeleteItems(items)
        }

        @objc private func menuPutItem(_ sender: NSMenuItem) {
            parent.onPutItem()
        }

        @objc private func menuSaveDraft(_ sender: NSMenuItem) {
            saveDraft()
        }

        @objc private func menuCancelDraft(_ sender: NSMenuItem) {
            parent.onCancelDraft()
        }
    }
}
