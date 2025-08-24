//
//  SelectSavedBatchItemIntentHandler.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2025-08-23.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//

import AppKit
import Intents
import os.log

@available(macOS 11.0, *)
class SelectSavedBatchItemIntentHandler: NSObject, SelectSavedBatchItemIntentHandling {
  
  private var model: AppModel!

  init(_ model: AppModel) {
    self.model = model
  }
  
  func handle(intent: SelectSavedBatchItemIntent, completion: @escaping (SelectSavedBatchItemIntentResponse) -> Void) {
    guard let batchNumber = intent.batchNumber as? Int, batchNumber >= 1,
          let itemNumber = intent.itemNumber as? Int, itemNumber >= 1,
          let clip = model.getFromBatch(at: batchNumber, clipItemAt: itemNumber) else {
      completion(SelectSavedBatchItemIntentResponse(code: .failure, userActivity: nil))
      return
    }
    model.putClipOnClipboard(clip)
    completion(SelectSavedBatchItemIntentResponse(code: .success, userActivity: nil))
  }
  
  func resolveBatchNumber(for intent: SelectSavedBatchItemIntent,
                          with completion: @escaping (SelectSavedBatchItemBatchNumberResolutionResult) -> Swift.Void) {
    guard let batchNumber = intent.batchNumber as? Int else {
      completion(.needsValue())
      return
    }
    completion(.success(with: batchNumber))
  }
  
  func resolveItemNumber(for intent: SelectSavedBatchItemIntent,
                         with completion: @escaping (SelectSavedBatchItemItemNumberResolutionResult) -> Void) {
    guard let itemNumber = intent.itemNumber as? Int else {
      completion(.needsValue())
      return
    }
    completion(.success(with: itemNumber))
  }
  
}
