//
//  TestMigration.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2025-08-10.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//

import Testing
import AppKit

@Suite("Database migrations", .serialized, .disabled("test this on demand, not regularly or automaically"))
class CoreDataMigrations {
  
  @Test("sanity check migration 1.0 to 1.1")
  func migrationTo1point1() throws {
    try migrateStore(fromVersionNumber: "1.0", toVersionNumber: "1.1")
  }
  
  @Test("migration 1.0 to 1.2")
  func migrationFrom1point0() throws {
    try migrateStore(fromVersionNumber: "1.0", toVersionNumber: "1.2")
  }
  
  @Test("migration 1.1 to 1.2")
  func migrationFrom1point1() throws {
    try migrateStore(fromVersionNumber: "1.1", toVersionNumber: "1.2")
  }
  
  // technique taken from https://stackoverflow.com/a/42591816/592739
  // and https://ifcaselet.com/writing-unit-tests-for-core-data-migrations/
  
  private let modelName = "Storage"
  private let modelVersionFormatString = "Storage %@"
  private let storeType = NSSQLiteStoreType
  private var rootBundle: Bundle { Bundle(for: Self.self) }
  
  enum StackErr: Error {
    case creatingModel(String)
    case creatingStore(String, Error?)
    case migratingStore(String, Error?)
  }
  
  private func migrateStore(fromVersionNumber srcVersionNum: String, toVersionNumber dstVersionNum: String) throws {
    let srcStore = try createStore(forVersionNumber: srcVersionNum)
    let dstModel = try createObjectModel(forVersionNumber: dstVersionNum)
    
    let srcStoreURL = srcStore.persistentStores.first?.url
    guard let srcStoreURL = srcStoreURL else {
      throw StackErr.migratingStore("url for store \(srcStore.name ?? srcVersionNum)", nil)
    }
    guard srcStoreURL == storeURL(forVersionNumber: srcVersionNum) else {
      throw StackErr.migratingStore("unexpected src url \(srcStoreURL) vs \(storeURL(forVersionNumber: srcVersionNum))", nil)
    }
    let dstStoreURL = storeURL(forVersionNumber: dstVersionNum)
    
    let mappingModel: NSMappingModel
    let explicitMappingModel = NSMappingModel(from: [rootBundle], forSourceModel: srcStore.managedObjectModel, destinationModel: dstModel)
    if let explicitMappingModel = explicitMappingModel {
      mappingModel = explicitMappingModel
    } else {
      mappingModel = try NSMappingModel.inferredMappingModel(forSourceModel: srcStore.managedObjectModel, destinationModel: dstModel)
    }
    
    let migrationManager = NSMigrationManager(sourceModel: srcStore.managedObjectModel, destinationModel: dstModel)
    do {
        try migrationManager.migrateStore(from: srcStoreURL, sourceType: storeType, options: nil, with: mappingModel,
                                          toDestinationURL: dstStoreURL, destinationType: storeType, destinationOptions: nil)
    } catch {
      throw StackErr.migratingStore("migrateStore call \(srcStoreURL.path) to \(dstStoreURL.path)", error)
    }
    
    try! FileManager.default.removeItem(at: srcStoreURL)
    try! FileManager.default.removeItem(at: dstStoreURL)
  }
  
  private func createObjectModel(forVersionNumber versionNum: String) throws -> NSManagedObjectModel {
    let modelURL = rootBundle.url(forResource: modelName, withExtension: "momd")
    guard let modelURL = modelURL else {
      throw StackErr.creatingModel("resource: \(modelName).momd in process bundle")
    }
    let modelURLBundle = Bundle(url: modelURL)
    guard let modelURLBundle = modelURLBundle else {
      throw StackErr.creatingModel("model bundle \(modelURL.path)")
    }
    let versionName = versionName(forVersionNumber: versionNum)
    let modelVersionURL = modelURLBundle.url(forResource: versionName, withExtension: "mom")
    guard let modelVersionURL = modelVersionURL else {
      throw StackErr.creatingModel("resource \(versionName).mom in model bundle \(modelURL.path)")
    }
    let model = NSManagedObjectModel(contentsOf: modelVersionURL)
    guard let model = model else {
      throw StackErr.creatingModel("model at \(modelVersionURL.path)")
    }
    return model
  }
  
  private func createStore(forVersionNumber versionNum: String) throws -> NSPersistentStoreCoordinator {
    let model = try createObjectModel(forVersionNumber: versionNum)
    let storeCoordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
    let storeURL = storeURL(forVersionNumber: versionNum)
    do {
      try storeCoordinator.addPersistentStore(ofType: storeType, configurationName: nil, at: storeURL, options: nil)
    } catch {
      throw StackErr.creatingStore("add persistent store \(storeURL) to coordinator \(storeCoordinator.name ?? versionNum)", error)
    }
    return storeCoordinator
  }
  
  private func versionName(forVersionNumber versionNum: String) -> String {
    String(format: modelVersionFormatString, versionNum)
  }
  
  private func storeURL(forVersionNumber versionNum: String) -> URL {
    URL.temporaryDirectory
      .appending(path: versionName(forVersionNumber: versionNum), directoryHint: .notDirectory)
      .appendingPathExtension("sqlite")
  }
  
}
