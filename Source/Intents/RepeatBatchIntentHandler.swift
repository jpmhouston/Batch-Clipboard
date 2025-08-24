//
//  RepeatBatchIntentHandler.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2025-08-24.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//

import AppKit
import Intents
import os.log

@available(macOS 11.0, *)
class RepeatBatchIntentHandler: NSObject, RepeatBatchIntentHandling {
  
  private var model: AppModel!
  
  init(_ model: AppModel) {
    self.model = model
  }
  
  func handle(intent: RepeatBatchIntent, completion: @escaping (RepeatBatchIntentResponse) -> Void) {
    guard model.replayQueue() else {
      completion(RepeatBatchIntentResponse(code: .failure, userActivity: nil))
      return
    }
    completion(RepeatBatchIntentResponse(code: .success, userActivity: nil))
  }
  
}
