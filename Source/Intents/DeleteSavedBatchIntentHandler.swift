//
//  DeleteSavedBatchIntentHandler.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2025-08-23.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//

import AppKit
import Intents
import os.log

@available(macOS 11.0, *)
class DeleteSavedBatchIntentHandler: NSObject, DeleteSavedBatchIntentHandling {
  
  private var model: AppModel!

  init(_ model: AppModel) {
    self.model = model
  }
  
  func handle(intent: DeleteSavedBatchIntent, completion: @escaping (DeleteSavedBatchIntentResponse) -> Void) {
    guard let batchNumber = intent.batchNumber as? Int, batchNumber >= 1,
          let title = model.deleteBatch(at: batchNumber) else {
      completion(DeleteSavedBatchIntentResponse(code: .failure, userActivity: nil))
      return
    }
    let response = DeleteSavedBatchIntentResponse(code: .success, userActivity: nil)
    response.title = title
    completion(response)
  }
  
  func resolveBatchNumber(for intent: DeleteSavedBatchIntent,
                          with completion: @escaping (DeleteSavedBatchBatchNumberResolutionResult) -> Void) {
    guard let batchNumber = intent.batchNumber as? Int else {
      completion(.needsValue())
      return
    }
    completion(.success(with: batchNumber))
  }
  
}
