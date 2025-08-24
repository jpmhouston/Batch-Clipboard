//
//  IntentHistoryItemFactory.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2025-08-23.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//

import AppKit
import Intents
import os.log

@available(macOS 11.0, *)
extension IntentHistoryItem {
  
  convenience init(withClip clip: Clip) {
    let title = clip.title ?? "clipboard item"
    self.init(identifier: clip.title, display: title)
    
    text = clip.text
    
    if let htmlData = clip.htmlData {
      html = String(data: htmlData, encoding: .utf8)
    }
    
    if let fileURL = clip.fileURLs.first {
      file = INFile(
        fileURL: fileURL,
        filename: "",
        typeIdentifier: nil
      )
    }
    
    if let imageData = clip.image?.tiffRepresentation {
      image = INFile(data: imageData, filename: "", typeIdentifier: nil)
    }
    
    if let rtf = clip.rtfData {
      richText = String(data: rtf, encoding: .utf8)
    }
  }
  
}
