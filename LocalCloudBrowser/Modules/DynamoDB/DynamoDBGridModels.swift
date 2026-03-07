import Foundation

// MARK: - Grid Column Model

struct GridColumn: Equatable {
    let name: String
    let isPartitionKey: Bool
    let isSortKey: Bool
}

/// Compute columns from items + table key schema.
/// PK first, SK second (if present), then remaining attributes alphabetically.
func computeGridColumns(items: [DynamoDBItem], tableDetail: DynamoDBTableDetail) -> [GridColumn] {
    let pkName = tableDetail.partitionKey?.attributeName
    let skName = tableDetail.sortKey?.attributeName

    // Collect union of all attribute names across items
    var allNames: Set<String> = []
    for item in items {
        allNames.formUnion(item.attributes.keys)
    }

    // Always include key columns even if no items
    if let pk = pkName { allNames.insert(pk) }
    if let sk = skName { allNames.insert(sk) }

    // Build ordered columns: PK, SK, then alphabetical rest
    var columns: [GridColumn] = []

    if let pk = pkName {
        columns.append(GridColumn(name: pk, isPartitionKey: true, isSortKey: false))
        allNames.remove(pk)
    }
    if let sk = skName {
        columns.append(GridColumn(name: sk, isPartitionKey: false, isSortKey: true))
        allNames.remove(sk)
    }

    let rest = allNames.sorted()
    for name in rest {
        columns.append(GridColumn(name: name, isPartitionKey: false, isSortKey: false))
    }

    return columns
}
