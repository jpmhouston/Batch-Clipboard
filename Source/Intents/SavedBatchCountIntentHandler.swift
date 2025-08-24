//
//  SavedBatchCountIntentHandler.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2025-08-23.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//

import AppKit
import Intents
import os.log

@available(macOS 11.0, *)
class SavedBatchCountIntentHandler: NSObject, SavedBatchCountIntentHandling {
  
  private var model: AppModel!
  
  init(_ model: AppModel) {
    self.model = model
  }
  
  func handle(intent: SavedBatchCountIntent, completion: @escaping (SavedBatchCountIntentResponse) -> Void) {
    let count = model.savedBatchCount()
    let response = SavedBatchCountIntentResponse(code: .success, userActivity: nil)
    response.batchCount = NSNumber(integerLiteral: count)
    completion(response)
  }
  
}
