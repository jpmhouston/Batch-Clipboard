import AppKit

// swiftlint:disable identifier_name
class Sorter {
  private var by: String

  init(by: String) {
    self.by = by
  }

  public func sort(_ items: [ClipItem]) -> [ClipItem] {
    return items.sorted(by: bySortingAlgorithm(_:_:)).sorted(by: byPinned(_:_:))
  }

  public func first(_ items: [ClipItem]) -> ClipItem? {
    return items.min(by: bySortingAlgorithm(_:_:))
  }

  private func bySortingAlgorithm(_ lhs: ClipItem, _ rhs: ClipItem) -> Bool {
    switch by {
    case "firstCopiedAt":
      return lhs.firstCopiedAt > rhs.firstCopiedAt
    case "numberOfCopies":
      return lhs.numberOfCopies > rhs.numberOfCopies
    default:
      return lhs.lastCopiedAt > rhs.lastCopiedAt
    }
  }

  private func byPinned(_ lhs: ClipItem, _ rhs: ClipItem) -> Bool {
    if UserDefaults.standard.pinTo == "bottom" {
      return (lhs.pin == nil) && (rhs.pin != nil)
    } else {
      return (lhs.pin != nil) && (rhs.pin == nil)
    }
  }
}
// swiftlint:enable identifier_name
