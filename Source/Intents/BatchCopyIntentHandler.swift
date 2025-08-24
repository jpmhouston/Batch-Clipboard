//
//  BatchCopyIntentHandler.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-06-15.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//

import Intents
import os.log

@available(macOS 11.0, *)
class BatchCopyIntentHandler: NSObject, BatchCopyIntentHandling {
  
  private var model: AppModel!
  
  init(_ model: AppModel) {
    self.model = model
  }
  
  func handle(intent: BatchCopyIntent, completion: @escaping (BatchCopyIntentResponse) -> Void) {
    if model.performQueuedCopy(completion: copyCompletion) == false {
      completion(BatchCopyIntentResponse(code: .failure, userActivity: nil))
    }
    func copyCompletion(_ ok: Bool) {
      completion(BatchCopyIntentResponse(code: ok ? .success : .failure, userActivity: nil))
    }
  }
  
}
