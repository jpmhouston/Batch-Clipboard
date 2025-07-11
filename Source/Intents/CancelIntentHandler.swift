//
//  CancelIntentHandler.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-06-15.
//  Copyright © 2024 Bananameter Labs. All rights reserved.
//

import Intents

@available(macOS 11.0, *)
class CancelIntentHandler: NSObject, CancelIntentHandling {
  private var model: AppModel!
  
  init(_ model: AppModel) {
    self.model = model
  }
  
  func handle(intent: CancelIntent, completion: @escaping (CancelIntentResponse) -> Void) {
    guard model.cancelQueueMode() else {
      completion(CancelIntentResponse(code: .failure, userActivity: nil))
      return
    }
    completion(CancelIntentResponse(code: .success, userActivity: nil))
  }
  
}
