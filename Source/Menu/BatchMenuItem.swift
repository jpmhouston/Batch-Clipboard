//
//  BatchMenuItem.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2025-08-11.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//

import AppKit
import KeyboardShortcuts

class BatchMenuItem: NSMenuItem {
  
  var batch: Batch?
  var name: String { batch?.fullname ?? "" }
  var hotKey: KeyboardShortcuts.Name?
  
  // outlets to the prototype submenu are connected  
  private var replaySubmenuItem: NSMenuItem? { submenu?.itemsWithMinCount(3)?[0] }
  private var renameSubmenuItem: NSMenuItem? { submenu?.itemsWithMinCount(3)?[1] }
  private var clipItemSeparator: NSMenuItem? { submenu?.itemsWithMinCount(3)?[2] }
  
  static func parentBatchMenuItem(for potentialSubmenuItem: AnyObject) -> BatchMenuItem? {
    (potentialSubmenuItem as? NSMenuItem)?.parent as? BatchMenuItem
  }
  
  // MARK: -
  
  func configured(withBatch batch: Batch, hotKey: KeyboardShortcuts.Name?) -> Self {
    self.batch = batch
    self.title = batch.makeTruncatedTitle()
    self.hotKey = hotKey
    updateShortcut()
    return self
  }
  
  func regenerateTitle() {
    guard let batch = batch else {
      return
    }
    title = batch.makeTruncatedTitle()
  }
  
  func updateShortcut() {
    guard let subitem = replaySubmenuItem else {
      return
    }
    if let hotKey = hotKey {
      MainActor.assumeIsolated {
        subitem.setShortcut(for: hotKey)
      }
    } else {
      subitem.keyEquivalent = ""
      subitem.keyEquivalentModifierMask = []
    }
  }
  
}

extension NSMenu {
  func itemsWithMinCount(_ n: Int) -> [NSMenuItem]? {
    items.count >= n ? items : nil
  }
}
