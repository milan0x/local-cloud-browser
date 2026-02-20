import SwiftUI

struct S3CopyActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct S3PasteActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct S3DeleteActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var s3CopyAction: (() -> Void)? {
        get { self[S3CopyActionKey.self] }
        set { self[S3CopyActionKey.self] = newValue }
    }

    var s3PasteAction: (() -> Void)? {
        get { self[S3PasteActionKey.self] }
        set { self[S3PasteActionKey.self] = newValue }
    }

    var s3DeleteAction: (() -> Void)? {
        get { self[S3DeleteActionKey.self] }
        set { self[S3DeleteActionKey.self] = newValue }
    }
}
