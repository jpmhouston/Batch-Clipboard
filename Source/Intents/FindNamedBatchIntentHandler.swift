//
//  FindNamedBatchIntentHandler.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2025-08-25.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//

import AppKit
import Intents
import os.log

@available(macOS 11.0, *)
class FindNamedBatchIntentHandler: NSObject, FindNamedBatchIntentHandling {
  
  private var model: AppModel!
  
  init(_ model: AppModel) {
    self.model = model
  }
  
  func handle(intent: FindNamedBatchIntent, completion: @escaping (FindNamedBatchIntentResponse) -> Void) {
    guard let batchName = intent.batchName, !batchName.isEmpty,
          let index = model.indexOfBatch(named: batchName) else {
      completion(FindNamedBatchIntentResponse(code: .failure, userActivity: nil))
      return
    }
    let response = FindNamedBatchIntentResponse(code: .success, userActivity: nil)
    response.index = NSNumber(integerLiteral: index)
    completion(response)
  }
  
  func resolveBatchName(for intent: FindNamedBatchIntent,
                        with completion: @escaping (INStringResolutionResult) -> Void) {
    guard let batchName = intent.batchName else {
      completion(.needsValue())
      return
    }
    completion(.success(with: batchName))
  }
  
}
