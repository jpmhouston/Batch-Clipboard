//
//  History.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-07-10.
//  Portions Copyright © 2024 Bananameter Labs. All rights reserved.
//
//  Based on History.swift from the Maccy project
//  Portions are copyright © 2024 Alexey Rodionov. All rights reserved.
//

import AppKit

class History {
  var maxItemsOverride = 0
  private var sortBy = "lastCopiedAt"
  
  var all: [ClipItem] {
    let sorter = Sorter(by: sortBy)
    var items = sorter.sort(ClipItem.all)
    
    // trim results and the database based on size setting, but also if queueing then include all those
    let maxItems = max(UserDefaults.standard.size, UserDefaults.standard.maxMenuItems, AppMenu.minNumMenuItems, maxItemsOverride)
    while items.count > maxItems {
      remove(items.removeLast())
    }
    
    return items
  }
  
  var first: ClipItem? {
    let sorter = Sorter(by: sortBy)
    return sorter.first(ClipItem.all)
  }
  
  var count: Int {
    ClipItem.count
  }
  
  private var sessionLog: [Int: ClipItem] = [:]
  
  init() {
    UserDefaults.standard.register(defaults: [UserDefaults.Keys.size: UserDefaults.Values.size])
    if ProcessInfo.processInfo.arguments.contains("ui-testing") {
      clear()
    }
  }
  
  func add(_ item: ClipItem) {
    if let existingHistoryItem = findSimilarItem(item) {
      if isModified(item) == nil {
        item.contents = existingHistoryItem.contents
      }
      item.firstCopiedAt = existingHistoryItem.firstCopiedAt
      item.numberOfCopies += existingHistoryItem.numberOfCopies
      item.pin = existingHistoryItem.pin
      item.title = existingHistoryItem.title
      if !item.fromMaccy {
        item.application = existingHistoryItem.application
      }
      remove(existingHistoryItem)
    }
    
    sessionLog[Clipboard.shared.changeCount] = item
    CoreDataManager.shared.saveContext()
  }
  
  func update(_ item: ClipItem?) {
    CoreDataManager.shared.saveContext()
  }
  
  func remove(_ item: ClipItem?) {
    guard let item else { return }
    
    item.getContents().forEach(CoreDataManager.shared.viewContext.delete(_:))
    CoreDataManager.shared.viewContext.delete(item)
  }
  
  func clear() {
    all.forEach(remove(_:))
  }
  
  private func findSimilarItem(_ item: ClipItem) -> ClipItem? {
    let duplicates = all.filter({ $0 == item || $0.supersedes(item) })
    if duplicates.count > 1 {
      return duplicates.first(where: { $0.objectID != item.objectID })
    } else {
      return isModified(item)
    }
  }
  
  private func isModified(_ item: ClipItem) -> ClipItem? {
    if let modified = item.modified, sessionLog.keys.contains(modified) {
      return sessionLog[modified]
    }
    
    return nil
  }
}
