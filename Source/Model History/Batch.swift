//
//  Batch.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2025-07-15.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//

import AppKit
import CoreData
import Sauce

@objc(Batch)
class Batch: NSManagedObject {
  @NSManaged public var index: Int
  @NSManaged public var items: NSOrderedSet?
  @NSManaged public var shortcut: Data?
  @NSManaged public var title: String?
  
  // MARK: -
  
  static var all: [Batch] {
    let fetchRequest = NSFetchRequest<Batch>(entityName: "Batch")
    fetchRequest.sortDescriptors = [Batch.sortByIndex]
    do {
      return try CoreDataManager.shared.context.fetch(fetchRequest)
    } catch {
      return []
    }
  }
  
  static let sortByIndex = NSSortDescriptor(key: #keyPath(Batch.index), ascending: true)
  
  // swiftlint:disable nsobject_prefer_isequal
  // i'm guessing we'd similarly get this error if tried having `-isEqual` instead of `==`:
  //   Class 'Batch' for entity 'Batch' has an illegal override of NSManagedObject -isEqual
  static func == (lhs: Batch, rhs: Batch) -> Bool {
    return lhs.title == rhs.title // yes, identify by title alone
  }
  // swiftlint:enable nsobject_prefer_isequal
  
  // MARK: -
  
  convenience init(index: Int, title: String, shortcut: Data?) {
    let entity = NSEntityDescription.entity(forEntityName: "Batch",
                                            in: CoreDataManager.shared.context)!
    self.init(entity: entity, insertInto: CoreDataManager.shared.context)

    self.index = index
    self.title = title
    self.shortcut = shortcut
  }
  
  // MARK: -
  
  override var debugDescription: String {
    debugDescription()
  }
  
  func debugDescription(ofLength length: Int? = nil) -> String {
    let t = title ?? "no-title"
    let clips = Self.all
    let c = clips.count
    if let len = length {
      let temp = "'' \(c): "
      let rem = temp.count - len
      let tmin = 6 // min characters for title
      let itemmin = 8 // min characters for each item
      if rem <= tmin {
        return "'\(t.prefix(max(len - 2, 4)))'" // if asked for len<6 return len 6 anyway
      } else if rem <= tmin + itemmin || c == 0 {
        return "'\(t.prefix(len - rem + 2))' \(c)" // +2 because not using the ': ' in the template str
      } else if rem < tmin + c * itemmin + c * 2 - 2 {
        let n = (rem - tmin + 2) / c * (itemmin + 2) // +2 in denom. for each ', ', but that's 1 extra so +2 in numer. to compensate    
        let cstr = clips.map({ $0.debugDescription(ofLength: itemmin) }).prefix(n).joined(separator: ", ")
        return "'\(t.prefix(rem - cstr.count))' \(c): \(cstr)"
      } else {
        let dlen = rem / (c + 1) // 1 division for each item plus another for the title
        let cstr = clips.map({ $0.debugDescription(ofLength: dlen) }).joined(separator: ", ")
        return "'\(t.prefix(rem - cstr.count))' \(c): \(cstr)"
      }
    } else if c > 0 {
      return "'\(t)' \(c): " + clips.map({ $0.debugDescription() }).joined(separator: ", ")
    } else {
      return "'\(t)' \(c)"
    }
  }
  
}
