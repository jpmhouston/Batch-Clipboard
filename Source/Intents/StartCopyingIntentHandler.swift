//
//  StartCopyingIntentHandler.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-06-14.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//

import AppKit
import Intents
import os.log

@available(macOS 11.0, *)
class StartCopyingIntentHandler: NSObject, StartCopyingIntentHandling {
  
  private var model: AppModel!
  
  init(_ model: AppModel) {
    self.model = model
  }
  
  func handle(intent: StartCopyingIntent, completion: @escaping (StartCopyingIntentResponse) -> Void) {
    guard model.startQueueMode(interactive: false) else {
      completion(StartCopyingIntentResponse(code: .failure, userActivity: nil))
      return
    }
    completion(StartCopyingIntentResponse(code: .success, userActivity: nil))
  }
  
}
