import Foundation

enum QuickEntryField: Hashable, CaseIterable {
    case title
    case date
    case url
    case list
}

struct QuickEntryNavigationHelper {
    static func nextField(from current: QuickEntryField?, isShift: Bool, hasLists: Bool) -> QuickEntryField {
        let fields: [QuickEntryField] = hasLists ? [.title, .date, .url, .list] : [.title, .date, .url]
        let currentField = current ?? .title
        guard let currentIndex = fields.firstIndex(of: currentField) else {
            return .title
        }
        let nextIndex: Int
        if isShift {
            nextIndex = (currentIndex - 1 + fields.count) % fields.count
        } else {
            nextIndex = (currentIndex + 1) % fields.count
        }
        return fields[nextIndex]
    }
    
    static func nextSelectionIndex(current: Int, delta: Int, total: Int) -> Int {
        guard total > 0 else { return 0 }
        return max(0, min(current + delta, total - 1))
    }
}
