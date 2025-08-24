//
//  StartFromHistoryItemIntentHandler.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-06-15.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//

import AppKit
import Intents
import os.log

@available(macOS 11.0, *)
class StartFromHistoryItemIntentHandler: NSObject, StartFromHistoryItemIntentHandling {
  
  private var model: AppModel!
  
  init(_ model: AppModel) {
    self.model = model
  }
  
  func handle(intent: StartFromHistoryItemIntent, completion: @escaping (StartFromHistoryItemIntentResponse) -> Void) {
    guard let number = intent.number as? Int, number >= 1, model.replayFromHistory(at: number) else {
      completion(StartFromHistoryItemIntentResponse(code: .failure, userActivity: nil))
      return
    }
    completion(StartFromHistoryItemIntentResponse(code: .success, userActivity: nil))
  }
  
  func resolveNumber(for intent: StartFromHistoryItemIntent,
                     with completion: @escaping (StartFromHistoryItemNumberResolutionResult) -> Void) {
    guard let number = intent.number as? Int else {
      completion(.needsValue())
      return
    }
    completion(.success(with: number))
  }
  
}
