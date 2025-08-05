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
    let fetchRequest = NSFetchRequest<Clip>(entityName: "HistoryItem")
    fetchRequest.sortDescriptors = [Clip.sortByFirstCopiedAt]
    // fetchRequest.predicate = Batch.clipsInNoSavedBatchesPredicate -- wanted this, but predicates suck, also commented-out code below
    do {
      return try CoreDataManager.shared.context.fetch(fetchRequest).filter { 
        // documentation says deleted entities not fetched but saw it happen in unit tests, leave this in until that's solved
        !$0.isDeleted && !$0.getBatches().contains(where: { $0.title != nil })
      }
    } catch {
      return []
    }
  }
  
  var first: Clip? {
    let fetchRequest = NSFetchRequest<Clip>(entityName: "HistoryItem")
    fetchRequest.sortDescriptors = [Clip.sortByFirstCopiedAt]
    //fetchRequest.predicate = Batch.clipsInNoSavedBatchesPredicate
    fetchRequest.fetchBatchSize = 1
    do {
      return try CoreDataManager.shared.context.fetch(fetchRequest).first {
        !$0.isDeleted && !$0.getBatches().contains(where: { $0.title != nil })
      }
    } catch {
      return nil
    }
  }
  
  var count: Int {
    all.count
    //let fetchRequest = NSFetchRequest<Clip>(entityName: "HistoryItem")
    //fetchRequest.sortDescriptors = [Clip.sortByFirstCopiedAt]
    //fetchRequest.predicate = Batch.clipsInNoSavedBatchesPredicate
    //do {
    //  return try CoreDataManager.shared.context.count(for: fetchRequest)
    //} catch {
    //  return 0
    //}
  }
  
  var batches: [Batch] {
    return Batch.saved
  }
  
  var lastBatch = Batch.last
  
  private var sessionLog: [Int: Clip] = [:]
  
  init() {
    if ProcessInfo.processInfo.arguments.contains("ui-testing") {
      clear()
    }
  }
  
  func add(_ clip: Clip) {
    if let existingHistoryItem = findSimilarItem(clip) {
      if isModified(clip) == nil {
        clip.contents = existingHistoryItem.contents
      }
      clip.firstCopiedAt = existingHistoryItem.firstCopiedAt
      clip.numberOfCopies += existingHistoryItem.numberOfCopies
      clip.pin = existingHistoryItem.pin
      clip.title = existingHistoryItem.title
      if !clip.fromSelf {
        clip.application = existingHistoryItem.application
      }
      remove(existingHistoryItem)
    }
    
    sessionLog[Clipboard.shared.changeCount] = clip
    CoreDataManager.shared.saveContext()
  }
  
  func update(_ clip: Clip?) {
    CoreDataManager.shared.saveContext()
  }
  
  func remove(_ clip: Clip) {
    clip.getContents().forEach(CoreDataManager.shared.context.delete(_:))
    CoreDataManager.shared.context.delete(clip)
    CoreDataManager.shared.saveContext() // added this, was it really missing or is it redundant here?
  }
  
  func remove(atIndex index: Int) {
    guard index < count else {
      return
    }
    remove(all[index])
    CoreDataManager.shared.saveContext() // added this, was it really missing or is it redundant here?
  }
  
  func trim(to maxItems: Int) {
    // trim results and the database based on size setting
    guard maxItems < count else {
      return
    }
    
    let overflowItems = all.suffix(from: maxItems)
    overflowItems.forEach(remove(_:))
    CoreDataManager.shared.saveContext() // added this, was it really missing or is it redundant here?
  }
  
  func clear() {
    all.forEach(remove(_:))
    CoreDataManager.shared.saveContext() // added this, was it really missing or is it redundant here?
  }
  
  private func findSimilarItem(_ clip: Clip) -> Clip? {
    let duplicates = all.filter({ $0 == clip || $0.supersedes(clip) })
    if duplicates.count > 1 {
      return duplicates.first(where: { $0.objectID != clip.objectID })
    } else {
      return isModified(clip)
    }
  }
  
  private func isModified(_ clip: Clip) -> Clip? {
    if let modified = clip.modified, sessionLog.keys.contains(modified) {
      return sessionLog[modified]
    }
    
    return nil
  }
  
  func setupSavingLastBatch() {
    if lastBatch == nil {
      lastBatch = Batch.createImplicitBatch()
    }
  }
  
  func resetLastBatch() {
    lastBatch = Batch.createImplicitBatch()
  }
  
  func stopSavingLastBatch() {
    Batch.deleteImplicitBatch()
    lastBatch = nil
  }
  
  // MARK: -
  
  var summary: String { "\(count) clips" }
  var desc: String { all.map { $0.value }.joined(separator: ", ") }
  var ptrs: String { all.map { "0x\(String(unsafeBitCast($0, to: Int.self), radix: 16))" }.joined(separator: ", ") }
  
  //var log: String { debugHistoryLog(ofLength: 0) }
  //func debugHistoryLog(ofLength length: Int = 0) { ... }
  
}
