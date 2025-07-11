//
//  Sorter.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-07-10.
//  Portions Copyright © 2024 Bananameter Labs. All rights reserved.
//
//  Based on Sorter.swift from the Maccy project
//  Portions are copyright © 2024 Alexey Rodionov. All rights reserved.
//

import AppKit

// swiftlint:disable identifier_name
class Sorter {
  private var by: String
  
  init(by: String) {
    self.by = by
  }
  
  public func sort(_ items: [ClipItem]) -> [ClipItem] {
    return items.sorted(by: bySortingAlgorithm(_:_:))
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
  
}
// swiftlint:enable identifier_name
