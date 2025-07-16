//
//  DeleteIntentHandler.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-07-10.
//  Portions Copyright © 2025 Bananameter Labs. All rights reserved.
//
//  Based on DeleteIntentHandler.swift.swift from the Maccy project
//  Portions Copyright © 2024 Alexey Rodionov. All rights reserved.
//

import Intents

@available(macOS 11.0, *)
class DeleteIntentHandler: NSObject, DeleteIntentHandling {
  private let positionOffset = 0
  private var model: AppModel!

  init(_ model: AppModel) {
    self.model = model
  }

  func handle(intent: DeleteIntent, completion: @escaping (DeleteIntentResponse) -> Void) {
    guard let number = intent.number as? Int,
          let value = model.delete(position: number - positionOffset) else {
      return completion(DeleteIntentResponse(code: .failure, userActivity: nil))
    }

    let response = DeleteIntentResponse(code: .success, userActivity: nil)
    response.value = value
    return completion(response)
  }

  func resolveNumber(for intent: DeleteIntent, with completion: @escaping (DeleteNumberResolutionResult) -> Void) {
    guard let number = intent.number as? Int else {
      return completion(.needsValue())
    }

    return completion(.success(with: number))
  }
}
