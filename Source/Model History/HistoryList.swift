//
//  HistoryList.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2025-08-07.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//

import AppKit
import CoreData
import os.log

@objc(HistoryList)
class HistoryList: NSManagedObject {
  
  @NSManaged public var clips: NSOrderedSet?
  
  // TODO: is this computed property better as a throwing load() function?
  
  static var current: HistoryList? {
    let fetchRequest = NSFetchRequest<HistoryList>(entityName: "HistoryList")
    fetchRequest.fetchBatchSize = 1
    do {
      return try CoreDataManager.shared.context.fetch(fetchRequest).first
    } catch {
      os_log(.default, "unhandled error loading history list %@", error.localizedDescription)
      return nil
    }
  }
  
  static func create(withClips clips: any Collection<Clip> = []) -> HistoryList {
    let list = HistoryList(context: CoreDataManager.shared.context)
    
    if !clips.isEmpty {
      list.addExistingClips(clips)
    }
    
    CoreDataManager.shared.saveContext()
    return list
  }
  
  // MARK: -
  
  func clipAtIndex(_ index: Int) -> Clip? {
    guard let clips = clips else {
      return nil
    }
    guard index < clips.count else {
      return nil
    }
    return clips[index] as? Clip
  }
  
  func clipsFromIndex(_ index: Int) -> [Clip] {
    guard let clips = clips else {
      return []
    }
    let count = min(index + 1, clips.count)
    guard count > 0 else {
      return []
    }
    var result: [Clip] = []
    result.reserveCapacity(count)
    for i in 0 ..< count {
      guard let clip = clips[i] as? Clip else {
        return []
      }
      result.append(clip)
    }
    return result
  }
  
  func getClips() -> Set<Clip> {
    (clips?.set as? Set<Clip>) ?? Set()
  }
  
  func getClipsArray() -> [Clip] {
    (clips?.array as? [Clip]) ?? []
  }
  
  func addNewClip(_ clip: Clip) {
    insertIntoClips(clip, at: 0)
    CoreDataManager.shared.saveContext()
  }
  
  func addExistingClips(_ sourceClips: any Collection<Clip>) {
    if sourceClips.isEmpty {
      return
    }
    // copy in same order but into index 0 not at the end
    let indexes = NSIndexSet(indexesIn: NSRange(location: 0, length: sourceClips.count))
    if let sourceClipsArray = sourceClips as? Array<Clip> { // yes lamer than polymorphism but also d.r.y.
      insertIntoClips(sourceClipsArray, at: indexes)
    } else {
      insertIntoClips(Array(sourceClips), at: indexes)
    }
    CoreDataManager.shared.saveContext()
  }
  
  func trimClipsToNewCount(_ newCount: Int) {
    // TODO: likely will need this
    // ...
    //CoreDataManager.shared.saveContext()
  }
  
  // MARK: -
  
  @objc(insertObject:inClipsAtIndex:)
  @NSManaged public func insertIntoClips(_ value: Clip, at idx: Int)

  @objc(removeObjectFromClipsAtIndex:)
  @NSManaged public func removeFromClips(at idx: Int)

  @objc(insertClips:atIndexes:)
  @NSManaged public func insertIntoClips(_ values: [Clip], at indexes: NSIndexSet)

  @objc(removeClipsAtIndexes:)
  @NSManaged public func removeFromClips(at indexes: NSIndexSet)

  @objc(replaceObjectInClipsAtIndex:withObject:)
  @NSManaged public func replaceClips(at idx: Int, with value: Clip)

  @objc(replaceClipsAtIndexes:withClips:)
  @NSManaged public func replaceClips(at indexes: NSIndexSet, with values: [Clip])

  @objc(addClipsObject:)
  @NSManaged public func addToClips(_ value: Clip)

  @objc(removeClipsObject:)
  @NSManaged public func removeFromClips(_ value: Clip)

  @objc(addClips:)
  @NSManaged public func addToClips(_ values: NSOrderedSet)

  @objc(removeClips:)
  @NSManaged public func removeFromClips(_ values: NSOrderedSet)
  
}
