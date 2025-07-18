//
//  ClearIntentHandler.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-07-10.
//  Portions Copyright © 2024 Bananameter Labs. All rights reserved.
//
//  Based on ClearIntentHandler.swift.swift from the Maccy project
//  Portions are copyright © 2024 Alexey Rodionov. All rights reserved.
//

import Intents

@available(macOS 11.0, *)
class ClearIntentHandler: NSObject, ClearIntentHandling {
  private var model: AppModel!

  init(_ model: AppModel) {
    self.model = model
  }

  func handle(intent: ClearIntent, completion: @escaping (ClearIntentResponse) -> Void) {
    model.clearHistory()
    return completion(ClearIntentResponse(code: .success, userActivity: nil))
  }
}
