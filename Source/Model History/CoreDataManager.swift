//
//  CoreDataManager.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-07-10.
//  Portions Copyright © 2025 Bananameter Labs. All rights reserved.
//
//  Based on CoreDataManager.swift from the Maccy project
//  Portions Copyright © 2024 Alexey Rodionov. All rights reserved.
//

import CoreData
import os.log

class CoreDataManager {
  
  #if UNITTEST
  static var shared: CoreDataManager!
  #else
  static var shared = CoreDataManager() // not `let` to allow `reset` func used by unit tests
  #endif
  
  @discardableResult
  static func reset() -> CoreDataManager {
    // replace the shared instance with a new one, completely clearing the previous persistent container
    // unit tests must call this before anything else
    shared = CoreDataManager()
    return shared
  }
  
  var context: NSManagedObjectContext {
    return persistentContainer.viewContext
  }
  
  func saveContext() {
    CoreDataManager.queuecheck()
    if context.hasChanges {
      do {
        try context.save()
      } catch {
        os_log(.error, "unresolved coredata error when saving context %@", error.localizedDescription)
      }
    }
  }
  
  func teardown() {
    saveContext() // i think should do explicity so not done automatically later and who knows where
    let coordinator = persistentContainer.persistentStoreCoordinator
    do {
      try Self.removeStore(fromCoordinator: coordinator, andDirectory: customURL != nil)
    } catch {
      os_log(.error, "unresolved coredata error when tearing down context %@", error.localizedDescription)
    }
  }
  
  // MARK: -
  // Configure the core data stack by setting following properties before first using `viewContext`
  // lots of tips for using core data from test cases in 
  // https://briancoyner.github.io/articles/2021-08-28-testing-core-data/
  // https://forums.swift.org/t/swift-testing-core-data-setup-teardown/75203/9
  
  // When running within the .app this will be true when under control of ui test. When running
  // within a unit test target itself, test setup can explicitly assign this to true.
  var inMemory = ProcessInfo.processInfo.arguments.contains("ui-testing")
  
  // Model is usually found automatcally by the NSPersistentContainer, but instead this can be
  // explicitly set a specific model prior to `persistentContainer` being first accessed.
  // Found that within unit tests this was needed:
  //   let url = Bundle(for: Self.self).url(forResource: "Storage", withExtension: ".momd"),
  //   let model = NSManagedObjectModel(contentsOf: modelURL) { CoreDataManager.shared.model = model }
  var model: NSManagedObjectModel?
  
  var customURL: URL?
  
  // Use this to set customURL to be within a unique temporary directory for unit tests
  // (note: name passed in doesn't have to be unique)
  func useUniqueTestDatabaseLocation(withName name: String) {
    do {
      let dirURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent(name, isDirectory: true)
      try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
      customURL = dirURL.appendingPathComponent(name).appendingPathExtension("sqlite")
    } catch {
      customURL = nil
    }
  }
  
  // MARK: -
  
  private init() {}
  
  lazy private var persistentContainer: NSPersistentContainer = {
    let container:NSPersistentContainer
    if let model = model {
      container = NSPersistentContainer(name: "Storage", managedObjectModel: model)
    } else {
      container = NSPersistentContainer(name: "Storage")
    }
    
    if inMemory {
      let description = NSPersistentStoreDescription()
      // some medium article https://medium.com/tiendeo-tech/ios-how-to-unit-test-core-data-eb4a754f2603
      // says apple recommended in 2018 https://developer.apple.com/videos/play/wwdc2018/224/?time=1776
      // to set the url to /dev/null instead of setting the type to NSInMemoryStoreType    
      //description.url = URL(fileURLWithPath: "/dev/null")
      description.type = NSInMemoryStoreType
      description.shouldAddStoreAsynchronously = false
      container.persistentStoreDescriptions = [description]
    } else if let customURL = customURL {
      let description = NSPersistentStoreDescription()
      description.shouldAddStoreAsynchronously = false
      description.url = customURL
      container.persistentStoreDescriptions = [description]
    }
    
    container.loadPersistentStores(completionHandler: { (_, error) in
      if let error = error as NSError? {
        // maybe fatal error instead?
        os_log(.error, "unresolved coredata error %@", error.localizedDescription)
      }
    })
    
    return container
  }()
  
  static private func removeStore(fromCoordinator coordinator: NSPersistentStoreCoordinator, andDirectory: Bool) throws {
    #if UNITTEST
    guard let callingqname = String(cString: __dispatch_queue_get_label(nil), encoding: .utf8) else { return }
    if callingqname == "com.apple.main-thread" {
      print("on the main queue, is that okay?")
    }
    #endif
    guard let persistentStore = coordinator.persistentStores.first else { return }
    try coordinator.remove(persistentStore)
    if andDirectory, let url = persistentStore.url {
      try FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
//    if #available(macOS 12.0, *) {
//      try coordinator.performAndWait {
//        
//        guard let callingqname = String(cString: __dispatch_queue_get_label(nil), encoding: .utf8) else { return }
//        if callingqname == "com.apple.main-thread" {
//          print("on the main queue, is that okay?")
//        }
//        
//        guard let persistentStore = coordinator.persistentStores.first else { return }
//        try coordinator.remove(persistentStore)
//        if andDirectory, let url = persistentStore.url {
//          try FileManager.default.removeItem(at: url.deletingLastPathComponent())
//        }
//      }
//    } else {
//      var caughtError: (any Error)?
//      coordinator.performAndWait {
//        guard let persistentStore = coordinator.persistentStores.first else { return }
//        do {
//          try coordinator.remove(persistentStore)
//          if andDirectory, let url = persistentStore.url {
//            try FileManager.default.removeItem(at: url.deletingLastPathComponent())
//          }
//        } catch {
//          caughtError = error
//        }
//      }
//      if let err = caughtError { throw err }
//    }
  }
  
  // MARK: -
  
  #if DEBUG
  func summary() {
    let countRequest = NSFetchRequest<Clip>(entityName: "HistoryItem")
    let count = try? context.count(for: countRequest)
    print("\(count ?? 0) clip items stored")
    // if breakpoint above, can do this: expr try! CoreDataManager.shared.viewContext.fetch(countRequest)
  }
  
  func logcontext() {
    let callingqname = String(cString: __dispatch_queue_get_label(nil), encoding: .utf8)
    context.performAndWait {
      let contextqname = String(cString: __dispatch_queue_get_label(nil), encoding: .utf8)
      print("context 0x\(String(unsafeBitCast(context, to: Int.self), radix: 16)), its 'perform' queue \"\(contextqname ?? "?")\", current queue \"\(callingqname ?? "?")\"")
    }
  }
  
  static func queuecheck() {
    guard let callingqname = String(cString: __dispatch_queue_get_label(nil), encoding: .utf8) else { return }
    let ismain = callingqname == "com.apple.main-thread"
    #if UNITTEST
    if ismain {
      print("unit test should use coredata on their own backgroud queue, not the main thread")
    }
    #else
    if !ismain {
      print("using coredata off the main thread, \"\(callingqname)\"")
    }
    #endif
  }
  #endif // DEBUG
  
}

//// see https://forums.swift.org/t/swift-testing-core-data-setup-teardown/75203/9
//// although not seeing the failures this claims to fix, leave ommented out for now
//extension NSManagedObject {
//    // Override default init to ensure entities are inserted into the correct context:
//    // https://stackoverflow.com/questions/51851485/multiple-nsentitydescriptions-claim-nsmanagedobject-subclass/
//    convenience init(context: NSManagedObjectContext) {
//        let name = String(describing: type(of: self))
//        let entity = NSEntityDescription.entity(forEntityName: name, in: context)!
//        self.init(entity: entity, insertInto: context)
//    }
//}
