struct S3Clipboard {
    let sourceBucket: String
    let objectKeys: [String]
    let folderPrefixes: [String]

    var totalCount: Int { objectKeys.count + folderPrefixes.count }
    var isEmpty: Bool { totalCount == 0 }
}
