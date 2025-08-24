//
//  DeleteBatchItemIntentHandler.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2025-08-23.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//

import AppKit
import Intents
import os.log

@available(macOS 11.0, *)
class DeleteBatchItemIntentHandler: NSObject, DeleteBatchItemIntentHandling {
  
  private var model: AppModel!

  init(_ model: AppModel) {
    self.model = model
  }
  
  func handle(intent: DeleteBatchItemIntent, completion: @escaping (DeleteBatchItemIntentResponse) -> Void) {
    guard let number = intent.number as? Int, number >= 1, let clip = model.deleteQueueItem(at: number) else {
      completion(DeleteBatchItemIntentResponse(code: .failure, userActivity: nil))
      return
    }
    let response = DeleteBatchItemIntentResponse(code: .success, userActivity: nil)
    response.item = IntentHistoryItem(withClip: clip)
    completion(response)
  }
  
  func resolveNumber(for intent: DeleteBatchItemIntent,
                     with completion: @escaping (DeleteBatchItemNumberResolutionResult) -> Void) {
    guard let number = intent.number as? Int else {
      completion(.needsValue())
      return
    }
    completion(.success(with: number))
  }
  
}
