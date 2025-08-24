//
//  GetHistoryItemIntentHandler.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-07-10.
//  Portions Copyright © 2025 Bananameter Labs. All rights reserved.
//
//  Based on GetIntentHandler.swift.swift from the Maccy project
//  Portions Copyright © 2024 Alexey Rodionov. All rights reserved.
//

import AppKit
import Intents
import os.log

@available(macOS 11.0, *)
class GetHistoryItemIntentHandler: NSObject, GetHistoryItemIntentHandling {
  
  private var model: AppModel!

  init(_ model: AppModel) {
    self.model = model
  }

  func handle(intent: GetHistoryItemIntent, completion: @escaping (GetHistoryItemIntentResponse) -> Void) {
    guard let number = intent.number as? Int, number >= 1, let clip = model.historyItem(at: number) else {
      completion(GetHistoryItemIntentResponse(code: .failure, userActivity: nil))
      return
    }
    let response = GetHistoryItemIntentResponse(code: .success, userActivity: nil)
    response.item = IntentHistoryItem(withClip: clip)
    completion(response)
  }
  
  func resolveNumber(for intent: GetHistoryItemIntent,
                     with completion: @escaping (GetHistoryItemNumberResolutionResult) -> Void) {
    guard let number = intent.number as? Int else {
      completion(.needsValue())
      return
    }
    completion(.success(with: number))
  }
  
}
