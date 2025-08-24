//
//  SelectHistoryItemIntentHandler.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2025-08-23.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//

import AppKit
import Intents
import os.log

@available(macOS 11.0, *)
class SelectHistoryItemIntentHandler: NSObject, SelectHistoryItemIntentHandling {
  
  private var model: AppModel!

  init(_ model: AppModel) {
    self.model = model
  }

  func handle(intent: SelectHistoryItemIntent, completion: @escaping (SelectHistoryItemIntentResponse) -> Void) {
    guard let number = intent.number as? Int, number >= 1, let clip = model.historyItem(at: number) else {
      completion(SelectHistoryItemIntentResponse(code: .failure, userActivity: nil))
      return
    }
    model.putClipOnClipboard(clip)
    completion(SelectHistoryItemIntentResponse(code: .success, userActivity: nil))
  }
  
  func resolveNumber(for intent: SelectHistoryItemIntent,
                     with completion: @escaping (SelectHistoryItemNumberResolutionResult) -> Void) {
    guard let number = intent.number as? Int else {
      completion(.needsValue())
      return
    }
    completion(.success(with: number))
  }
  
}
