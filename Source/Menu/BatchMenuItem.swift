//
//  BatchMenuItem.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2025-08-11.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//

import AppKit

class BatchMenuItem: NSMenuItem {
  
  var batch: Batch?
  var name: String { batch?.fullname ?? "" }
  
  required init(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  // define this to avoid a mysterious runtime failure:
  // Fatal error: Use of unimplemented initializer 'init(title:action:keyEquivalent:)' for class 'Batch_Clipboard.ClipMenuItem'
  override init(title: String, action: Selector?, keyEquivalent: String) {
    super.init(title: title, action: action, keyEquivalent: keyEquivalent)
  }
  
  func configured(withBatch batch: Batch) -> Self {
    self.batch = batch
    self.title = batch.title ?? ""
    
    // set shortcut?
    
    return self
  }
  
  func regenerateTitle() {
    guard let batch = batch else {
      return
    }
    title = batch.makeTruncatedTitle()
  }
  
//  func updateShortcut() {
//  }
  
}
