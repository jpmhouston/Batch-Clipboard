//
//  BatchCopyIntentHandler.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-06-15.
//  Copyright © 2024 Bananameter Labs. All rights reserved.
//

import Intents

@available(macOS 11.0, *)
class BatchCopyIntentHandler: NSObject, BatchCopyIntentHandling {
  private var model: AppModel!
  
  init(_ model: AppModel) {
    self.model = model
  }
  
  func handle(intent: BatchCopyIntent, completion: @escaping (BatchCopyIntentResponse) -> Void) {
    guard model.queuedCopy(interactive: false) else {
      completion(BatchCopyIntentResponse(code: .failure, userActivity: nil))
      return
    }
    completion(BatchCopyIntentResponse(code: .success, userActivity: nil))
  }
  
}
