//
//  StartIntentHandler.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-06-14.
//  Copyright © 2024 Bananameter Labs. All rights reserved.
//

import Intents

@available(macOS 11.0, *)
class StartIntentHandler: NSObject, StartIntentHandling {
  private var model: AppModel!
  
  init(_ model: AppModel) {
    self.model = model
  }

  func handle(intent: StartIntent, completion: @escaping (StartIntentResponse) -> Void) {
    guard model.startQueueMode(interactive: false) else {
      completion(StartIntentResponse(code: .failure, userActivity: nil))
      return
    }
    completion(StartIntentResponse(code: .success, userActivity: nil))
  }
  
}
