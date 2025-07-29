//
//  History.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-07-10.
//  Portions Copyright © 2025 Bananameter Labs. All rights reserved.
//
//  Based on History.swift from the Maccy project
//  Portions Copyright © 2024 Alexey Rodionov. All rights reserved.
//

import AppKit

class History {
  var maxItemsOverride = 0
  
  var all: [Clip] {
    // currently merely all clips, perhaps will soon be filtering out ones within saved batches 
    return Clip.all
  }
  
  var first: Clip? {
    return Clip.first
  }
  
  var count: Int {
    return Clip.count
  }
  
  var batches: [Batch] {
    return Batch.all
  }
  
  private var sessionLog: [Int: Clip] = [:]
  
  init() {
    if ProcessInfo.processInfo.arguments.contains("ui-testing") {
      clear()
    }
  }
  
  func add(_ item: Clip) {
    if let existingHistoryItem = findSimilarItem(item) {
      if isModified(item) == nil {
        item.contents = existingHistoryItem.contents
      }
      item.firstCopiedAt = existingHistoryItem.firstCopiedAt
      item.numberOfCopies += existingHistoryItem.numberOfCopies
      item.pin = existingHistoryItem.pin
      item.title = existingHistoryItem.title
      if !item.fromSelf {
        item.application = existingHistoryItem.application
      }
      remove(existingHistoryItem)
    }
    
    sessionLog[Clipboard.shared.changeCount] = item
    CoreDataManager.shared.saveContext()
  }
  
  func update(_ item: Clip?) {
    CoreDataManager.shared.saveContext()
  }
  
  func remove(_ item: Clip?) {
    guard let item else {
      return
    }
    
    item.getContents().forEach(CoreDataManager.shared.context.delete(_:))
    CoreDataManager.shared.context.delete(item)
  }
  
  func remove(atIndex index: Int) {
    guard index < count else {
      return
    }
    remove(all[index])
  }
  
  func trim(to maxItems: Int) {
    // trim results and the database based on size setting
    guard maxItems < count else {
      return
    }
    
    let overflowItems = all.suffix(from: maxItems)
    overflowItems.forEach(remove(_:))
  }
  
  func clear() {
    all.forEach(remove(_:))
  }
  
  private func findSimilarItem(_ item: Clip) -> Clip? {
    let duplicates = all.filter({ $0 == item || $0.supersedes(item) })
    if duplicates.count > 1 {
      return duplicates.first(where: { $0.objectID != item.objectID })
    } else {
      return isModified(item)
    }
  }
  
  private func isModified(_ item: Clip) -> Clip? {
    if let modified = item.modified, sessionLog.keys.contains(modified) {
      return sessionLog[modified]
    }
    
    return nil
  }
  
  // MARK: -
  
  var summary: String { "\(count) clips" }
  var desc: String { all.map { $0.value }.joined(separator: ", ") }
  var ptrs: String { all.map { "0x\(String(unsafeBitCast($0, to: Int.self), radix: 16))" }.joined(separator: ", ") }
  
  //var log: String { debugHistoryLog(ofLength: 0) }
  //func debugHistoryLog(ofLength length: Int = 0) { ... }
  
}
