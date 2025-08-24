//
//  SelectBatchItemIntentHandler.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2025-08-23.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//

import AppKit
import Intents
import os.log

@available(macOS 11.0, *)
class SelectBatchItemIntentHandler: NSObject, SelectBatchItemIntentHandling {
  
  private var model: AppModel!
  
  init(_ model: AppModel) {
    self.model = model
  }
  
  func handle(intent: SelectBatchItemIntent, completion: @escaping (SelectBatchItemIntentResponse) -> Void) {
    guard let number = intent.number as? Int, number >= 1, let clip = model.queueItem(at: number) else {
      completion(SelectBatchItemIntentResponse(code: .failure, userActivity: nil))
      return
    }
    model.putClipOnClipboard(clip)
    completion(SelectBatchItemIntentResponse(code: .success, userActivity: nil))
  }
  
  func resolveNumber(for intent: SelectBatchItemIntent,
                     with completion: @escaping (SelectBatchItemNumberResolutionResult) -> Void) {
    guard let number = intent.number as? Int else {
      completion(.needsValue())
      return
    }
    completion(.success(with: number))
  }
  
}
