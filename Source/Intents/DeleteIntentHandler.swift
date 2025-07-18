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

import AppKit
import Intents

@available(macOS 11.0, *)
class DeleteIntentHandler: NSObject, DeleteIntentHandling {
  private let positionOffset = 0
  private var model: AppModel!

  init(_ model: AppModel) {
    self.model = model
  }

  func handle(intent: DeleteIntent, completion: @escaping (DeleteIntentResponse) -> Void) {
    guard let index = intent.number as? Int,
          let clip = model.delete(position: index - positionOffset) else {
      return completion(DeleteIntentResponse(code: .failure, userActivity: nil))
    }

    // this code duplicated here and in CopyIntentHandler :( d.r.y.
    let title = clip.title ?? "clipboard item"
    let intentItem = IntentHistoryItem(identifier: clip.title, display: title)
    intentItem.text = clip.text

    if let html = clip.htmlData {
      intentItem.html = String(data: html, encoding: .utf8)
    }

    if let fileURL = clip.fileURLs.first {
      intentItem.file = INFile(
        fileURL: fileURL,
        filename: "",
        typeIdentifier: nil
      )
    }

    if let image = clip.image?.tiffRepresentation {
      intentItem.image = INFile(data: image, filename: "", typeIdentifier: nil)
    }

    if let rtf = clip.rtfData {
      intentItem.richText = String(data: rtf, encoding: .utf8)
    }

    let response = DeleteIntentResponse(code: .success, userActivity: nil)
    response.item = intentItem
    return completion(response)
  }

  func resolveNumber(for intent: DeleteIntent, with completion: @escaping (DeleteNumberResolutionResult) -> Void) {
    guard let number = intent.number as? Int else {
      return completion(.needsValue())
    }

    return completion(.success(with: number))
  }
}
