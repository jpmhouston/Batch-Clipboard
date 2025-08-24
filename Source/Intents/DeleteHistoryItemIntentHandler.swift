//
//  DeleteHistoryItemIntentHandler.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-07-10.
//  Portions Copyright © 2025 Bananameter Labs. All rights reserved.
//
//  Based on DeleteIntentHandler.swift.swift from the Maccy project
//  Portions Copyright © 2024 Alexey Rodionov. All rights reserved.
//

import AppKit
import Intents
import os.log

@available(macOS 11.0, *)
class DeleteHistoryItemIntentHandler: NSObject, DeleteHistoryItemIntentHandling {
  
  private var model: AppModel!
  
  init(_ model: AppModel) {
    self.model = model
  }
  
  func handle(intent: DeleteHistoryItemIntent, completion: @escaping (DeleteHistoryItemIntentResponse) -> Void) {
    guard let number = intent.number as? Int, number >= 1, let clip = model.deleteHistoryItem(at: number) else {
      completion(DeleteHistoryItemIntentResponse(code: .failure, userActivity: nil))
      return
    }
    let response = DeleteHistoryItemIntentResponse(code: .success, userActivity: nil)
    response.item = IntentHistoryItem(withClip: clip)
    completion(response)
  }
  
  func resolveNumber(for intent: DeleteHistoryItemIntent,
                     with completion: @escaping (DeleteHistoryItemNumberResolutionResult) -> Void) {
    guard let number = intent.number as? Int else {
      completion(.needsValue())
      return
    }
    completion(.success(with: number))
  }
  
}
