//
//  SelectNamedBatchIntentHandler.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2025-08-25.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//

import AppKit
import Intents
import os.log

@available(macOS 11.0, *)
class SelectNamedBatchIntentHandler: NSObject, SelectNamedBatchIntentHandling {
  
  private var model: AppModel!
  
  init(_ model: AppModel) {
    self.model = model
  }
  
  func handle(intent: SelectNamedBatchIntent, completion: @escaping (SelectNamedBatchIntentResponse) -> Void) {
    guard let batchName = intent.batchName, !batchName.isEmpty,
          model.replayBatch(named: batchName) else {
      completion(SelectNamedBatchIntentResponse(code: .failure, userActivity: nil))
      return
    }
    completion(SelectNamedBatchIntentResponse(code: .success, userActivity: nil))
  }
  
  func resolveBatchName(for intent: SelectNamedBatchIntent,
                          with completion: @escaping (INStringResolutionResult) -> Void) {
    guard let batchName = intent.batchName else {
      completion(.needsValue())
      return
    }
    completion(.success(with: batchName))
  }
  
}
