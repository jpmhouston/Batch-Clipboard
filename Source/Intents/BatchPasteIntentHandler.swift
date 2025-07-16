//
//  BatchPasteIntentHandler.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-06-15.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//

import Intents

@available(macOS 11.0, *)
class BatchPasteIntentHandler: NSObject, BatchPasteIntentHandling {
  private var model: AppModel!
  
  init(_ model: AppModel) {
    self.model = model
  }
  
  func handle(intent: BatchPasteIntent, completion: @escaping (BatchPasteIntentResponse) -> Void) {
    guard model.queuedPaste(interactive: false) else {
      completion(BatchPasteIntentResponse(code: .failure, userActivity: nil))
      return
    }
    completion(BatchPasteIntentResponse(code: .success, userActivity: nil))
  }
  
}
