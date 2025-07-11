//
//  GetIntentHandler.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-07-10.
//  Portions Copyright © 2024 Bananameter Labs. All rights reserved.
//
//  Based on GetIntentHandler.swift.swift from the Maccy project
//  Portions are copyright © 2024 Alexey Rodionov. All rights reserved.
//

import AppKit
import Intents

@available(macOS 11.0, *)
class GetIntentHandler: NSObject, GetIntentHandling {
  private let positionOffset = 0
  private var model: AppModel!

  init(_ model: AppModel) {
    self.model = model
  }

  func handle(intent: GetIntent, completion: @escaping (GetIntentResponse) -> Void) {
    guard let number = intent.number as? Int else {
      return completion(GetIntentResponse(code: .failure, userActivity: nil))
    }

    let index = number - positionOffset

    guard let item = model.item(at: index), let title = item.title else {
      return completion(GetIntentResponse(code: .failure, userActivity: nil))
    }

    let intentItem = IntentHistoryItem(identifier: item.title, display: title)
    intentItem.text = item.text

    if let html = item.htmlData {
      intentItem.html = String(data: html, encoding: .utf8)
    }

    if let fileURL = item.fileURLs.first {
      intentItem.file = INFile(
        fileURL: fileURL,
        filename: "",
        typeIdentifier: nil
      )
    }

    if let image = item.image?.tiffRepresentation {
      intentItem.image = INFile(data: image, filename: "", typeIdentifier: nil)
    }

    if let rtf = item.rtfData {
      intentItem.richText = String(data: rtf, encoding: .utf8)
    }

    let response = GetIntentResponse(code: .success, userActivity: nil)
    response.item = intentItem
    return completion(response)
  }

  func resolveNumber(for intent: GetIntent, with completion: @escaping (GetNumberResolutionResult) -> Void) {
    guard let number = intent.number as? Int else {
      return completion(.needsValue())
    }

    return completion(.success(with: number))
  }
}
