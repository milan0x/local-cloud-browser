import Foundation

extension String {
    /// Shell-escape for use inside single quotes: replace `'` with `'\''`
    func shellEscaped() -> String {
        replacingOccurrences(of: "'", with: "'\\''")
    }
}
