//
//  DeleteSavedBatchItemIntentHandler.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2025-08-23.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//

import AppKit
import Intents
import os.log

@available(macOS 11.0, *)
class DeleteSavedBatchItemIntentHandler: NSObject, DeleteSavedBatchItemIntentHandling {
  
  private var model: AppModel!
  
  init(_ model: AppModel) {
    self.model = model
  }
  
  func handle(intent: DeleteSavedBatchItemIntent, completion: @escaping (DeleteSavedBatchItemIntentResponse) -> Void) {
    guard let batchNumber = intent.batchNumber as? Int, batchNumber >= 1,
          let itemNumber = intent.itemNumber as? Int, itemNumber >= 1,
          let clip = model.deleteFromBatch(at: batchNumber, clipItemAt: itemNumber) else {
      completion(DeleteSavedBatchItemIntentResponse(code: .success, userActivity: nil))
      return
    }
    let response = DeleteSavedBatchItemIntentResponse(code: .success, userActivity: nil)
    response.item = IntentHistoryItem(withClip: clip)
    completion(response)
  }
  
  func resolveBatchNumber(for intent: DeleteSavedBatchItemIntent,
                          with completion: @escaping (DeleteSavedBatchItemBatchNumberResolutionResult) -> Void) {
    guard let batchNumber = intent.batchNumber as? Int else {
      completion(.needsValue())
      return
    }
    completion(.success(with: batchNumber))
  }
  
  func resolveItemNumber(for intent: DeleteSavedBatchItemIntent,
                         with completion: @escaping (DeleteSavedBatchItemItemNumberResolutionResult) -> Void) {
    guard let itemNumber = intent.itemNumber as? Int else {
      completion(.needsValue())
      return
    }
    completion(.success(with: itemNumber))
  }
  
}
