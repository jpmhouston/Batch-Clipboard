//
//  SavedBatchItemCountIntentHandler.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2025-08-23.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//

import AppKit
import Intents
import os.log

@available(macOS 11.0, *)
class SavedBatchItemCountIntentHandler: NSObject, SavedBatchItemCountIntentHandling {
  
  private var model: AppModel!
  
  init(_ model: AppModel) {
    self.model = model
  }
  
  func handle(intent: SavedBatchItemCountIntent, completion: @escaping (SavedBatchItemCountIntentResponse) -> Void) {
    guard let batchNumber = intent.batchNumber as? Int, batchNumber >= 1 else {
      completion(SavedBatchItemCountIntentResponse(code: .failure, userActivity: nil))
      return
    }
    let count = model.savedBatchItemCount(at: batchNumber)
    let response = SavedBatchItemCountIntentResponse(code: .success, userActivity: nil)
    response.itemCount = NSNumber(integerLiteral: count)
    completion(response)
  }
  
  func resolveBatchNumber(for intent: SavedBatchItemCountIntent,
                          with completion: @escaping (SavedBatchItemCountBatchNumberResolutionResult) -> Swift.Void) {
    guard let batchNumber = intent.batchNumber as? Int else {
      completion(.needsValue())
      return
    }
    completion(.success(with: batchNumber))
  }
  
}
