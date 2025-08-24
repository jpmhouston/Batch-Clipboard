//
//  StartPastingIntentHandler.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2025-08-24.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//

import AppKit
import Intents
import os.log

@available(macOS 11.0, *)
class StartPastingIntentHandler: NSObject, StartPastingIntentHandling {
  
  private var model: AppModel!
  
  init(_ model: AppModel) {
    self.model = model
  }
  
  func handle(intent: StartPastingIntent, completion: @escaping (StartPastingIntentResponse) -> Void) {
    guard model.startReplay() else {
      completion(StartPastingIntentResponse(code: .failure, userActivity: nil))
      return
    }
    completion(StartPastingIntentResponse(code: .success, userActivity: nil))
  }
  
}
