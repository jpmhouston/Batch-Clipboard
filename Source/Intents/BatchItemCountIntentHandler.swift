//
//  BatchItemCountIntentHandler.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2025-08-23.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//

import AppKit
import Intents
import os.log

@available(macOS 11.0, *)
class BatchItemCountIntentHandler: NSObject, BatchItemCountIntentHandling {
  
  private var model: AppModel!
  
  init(_ model: AppModel) {
    self.model = model
  }
  
  func handle(intent: BatchItemCountIntent, completion: @escaping (BatchItemCountIntentResponse) -> Void) {
    let count = model.queueItemCount()
    let response = BatchItemCountIntentResponse(code: .success, userActivity: nil)
    response.itemCount = NSNumber(integerLiteral: count)
    completion(response)
  }
  
}
