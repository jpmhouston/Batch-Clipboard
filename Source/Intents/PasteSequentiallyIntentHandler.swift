//
//  PasteSequentiallyIntentHandler.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2025-08-24.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//

import AppKit
import Intents
import os.log

@available(macOS 11.0, *)
class PasteSequentiallyIntentHandler: NSObject, PasteSequentiallyIntentHandling {
  
  private var model: AppModel!
  
  init(_ model: AppModel) {
    self.model = model
  }
  
  func handle(intent: PasteSequentiallyIntent, completion: @escaping (PasteSequentiallyIntentResponse) -> Void) {
    guard let count: Int = (intent.count == nil) ? 0 : intent.count as? Int,
          model.pasteSequentialItems(count: count, separator: intent.separator ?? "", completion: pasteCompletion) else {
      completion(PasteSequentiallyIntentResponse(code: .failure, userActivity: nil))
      return
    }
    func pasteCompletion(_ ok: Bool) {
      completion(PasteSequentiallyIntentResponse(code: ok ? .success : .failure, userActivity: nil))
    }
  }
  
  func resolveCount(for intent: PasteSequentiallyIntent,
                    with completion: @escaping (PasteSequentiallyCountResolutionResult) -> Void) {
    if intent.count == nil {
      completion(.success(with: 0))
      return
    }
    guard let count = intent.count as? Int else {
      completion(.needsValue())
      return
    }
    completion(.success(with: count))
  }
  
  func resolveSeparator(for intent: PasteSequentiallyIntent,
                        with completion: @escaping (INStringResolutionResult) -> Void) {
    completion(.success(with: intent.separator ?? ""))
  }
  
}
