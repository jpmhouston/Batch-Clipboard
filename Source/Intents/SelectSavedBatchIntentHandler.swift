//
//  SelectSavedBatchIntentHandler.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2025-08-23.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//

import AppKit
import Intents
import os.log

@available(macOS 11.0, *)
class SelectSavedBatchIntentHandler: NSObject, SelectSavedBatchIntentHandling {
  
  private var model: AppModel!
  
  init(_ model: AppModel) {
    self.model = model
  }
  
  func handle(intent: SelectSavedBatchIntent, completion: @escaping (SelectSavedBatchIntentResponse) -> Void) {
    guard let batchNumber = intent.batchNumber as? Int, batchNumber >= 1, model.replayBatch(at: batchNumber) else {
      completion(SelectSavedBatchIntentResponse(code: .failure, userActivity: nil))
      return
    }
    completion(SelectSavedBatchIntentResponse(code: .success, userActivity: nil))
  }
  
  func resolveBatchNumber(for intent: SelectSavedBatchIntent,
                          with completion: @escaping (SelectSavedBatchBatchNumberResolutionResult) -> Void) {
    guard let batchNumber = intent.batchNumber as? Int else {
      completion(.needsValue())
      return
    }
    completion(.success(with: batchNumber))
  }
  
}
