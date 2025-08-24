//
//  GetSavedBatchItemIntentHandler.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2025-08-23.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//

import AppKit
import Intents
import os.log

@available(macOS 11.0, *)
class GetSavedBatchItemIntentHandler: NSObject, GetSavedBatchItemIntentHandling {
  
  private var model: AppModel!

  init(_ model: AppModel) {
    self.model = model
  }
  
  func handle(intent: GetSavedBatchItemIntent, completion: @escaping (GetSavedBatchItemIntentResponse) -> Void) {
    guard let batchNumber = intent.batchNumber as? Int, batchNumber >= 1,
          let itemNumber = intent.itemNumber as? Int, itemNumber >= 1,
          let clip = model.getFromBatch(at: batchNumber, clipItemAt: itemNumber) else {
      completion(GetSavedBatchItemIntentResponse(code: .failure, userActivity: nil))
      return
    }
    let response = GetSavedBatchItemIntentResponse(code: .success, userActivity: nil)
    response.item = IntentHistoryItem(withClip: clip)
    completion(response)
  }
  
  func resolveBatchNumber(for intent: GetSavedBatchItemIntent,
                          with completion: @escaping (GetSavedBatchItemBatchNumberResolutionResult) -> Swift.Void) {
    guard let batchNumber = intent.batchNumber as? Int else {
      completion(.needsValue())
      return
    }
    completion(.success(with: batchNumber))
  }
  
  func resolveItemNumber(for intent: GetSavedBatchItemIntent,
                         with completion: @escaping (GetSavedBatchItemItemNumberResolutionResult) -> Void) {
    guard let itemNumber = intent.itemNumber as? Int else {
      completion(.needsValue())
      return
    }
    completion(.success(with: itemNumber))
  }
  
}
