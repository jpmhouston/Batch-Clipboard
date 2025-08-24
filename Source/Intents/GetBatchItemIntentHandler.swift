//
//  GetBatchItemIntentHandler.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2025-08-23.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//

import AppKit
import Intents
import os.log

@available(macOS 11.0, *)
class GetBatchItemIntentHandler: NSObject, GetBatchItemIntentHandling {
  
  private var model: AppModel!
  
  init(_ model: AppModel) {
    self.model = model
  }
  
  func handle(intent: GetBatchItemIntent, completion: @escaping (GetBatchItemIntentResponse) -> Void) {
    guard let number = intent.number as? Int, number >= 1, let clip = model.queueItem(at: number) else {
      completion(GetBatchItemIntentResponse(code: .failure, userActivity: nil))
      return
    }
    let response = GetBatchItemIntentResponse(code: .success, userActivity: nil)
    response.item = IntentHistoryItem(withClip: clip)
    completion(response)
  }
  
  func resolveNumber(for intent: GetBatchItemIntent,
                     with completion: @escaping (GetBatchItemNumberResolutionResult) -> Void) {
    guard let number = intent.number as? Int else {
      completion(.needsValue())
      return
    }
    completion(.success(with: number))
  }
  
}
