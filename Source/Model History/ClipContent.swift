//
//  ClipContent.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-07-10.
//  Portions Copyright © 2024 Bananameter Labs. All rights reserved.
//
//  Based on HistoryItemContent.swift from the Maccy project
//  Portions are copyright © 2024 Alexey Rodionov. All rights reserved.
//

import CoreData

@objc(HistoryItemContent)
class ClipContent: NSManagedObject {
  @NSManaged public var type: String!
  @NSManaged public var value: Data?
  @NSManaged public var item: ClipItem?

  // swiftlint:disable nsobject_prefer_isequal
  // Class 'HistoryItemContent' for entity 'HistoryItemContent' has an illegal override of NSManagedObject -isEqual
  static func == (lhs: ClipContent, rhs: ClipContent) -> Bool {
    return (lhs.type == rhs.type) && (lhs.value == rhs.value)
  }
  // swiftlint:enable nsobject_prefer_isequal

  convenience init(type: String, value: Data?) {
    let entity = NSEntityDescription.entity(forEntityName: "HistoryItemContent",
                                            in: CoreDataManager.shared.viewContext)!
    self.init(entity: entity, insertInto: CoreDataManager.shared.viewContext)

    self.type = type
    self.value = value
  }
}
