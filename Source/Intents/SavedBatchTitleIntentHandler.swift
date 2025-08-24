//
//  SavedBatchTitleIntentHandler.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2025-08-23.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//
//  ie. Saved refers to saved batches
//

import AppKit
import Intents
import os.log

@available(macOS 11.0, *)
class SavedBatchTitleIntentHandler: NSObject, SavedBatchTitleIntentHandling {
  
  private var model: AppModel!
  
  init(_ model: AppModel) {
    self.model = model
  }
  
  func handle(intent: SavedBatchTitleIntent, completion: @escaping (SavedBatchTitleIntentResponse) -> Void) {
    guard let batchNumber = intent.batchNumber as? Int, batchNumber >= 1, let title = model.batchTitle(at: batchNumber) else {
      completion(SavedBatchTitleIntentResponse(code: .failure, userActivity: nil))
      return
    }
    let response = SavedBatchTitleIntentResponse(code: .success, userActivity: nil)
    response.title = title
    completion(response)
  }
  
  func resolveBatchNumber(for intent: SavedBatchTitleIntent,
                          with completion: @escaping (SavedBatchTitleBatchNumberResolutionResult) -> Swift.Void) {
    guard let batchNumber = intent.batchNumber as? Int else {
      completion(.needsValue())
      return
    }
    completion(.success(with: batchNumber))
  }
  
}
