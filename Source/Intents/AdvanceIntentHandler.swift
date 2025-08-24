//
//  AdvanceIntentHandler.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2025-08-24.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//

import AppKit
import Intents
import os.log

@available(macOS 11.0, *)
class AdvanceIntentHandler: NSObject, AdvanceIntentHandling {
  
  private var model: AppModel!
  
  init(_ model: AppModel) {
    self.model = model
  }
  
  func handle(intent: AdvanceIntent, completion: @escaping (AdvanceIntentResponse) -> Void) {
    guard model.advanceQueue() else {
      completion(AdvanceIntentResponse(code: .failure, userActivity: nil))
      return
    }
    completion(AdvanceIntentResponse(code: .success, userActivity: nil))
  }
  
}
