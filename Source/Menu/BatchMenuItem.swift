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
  
  // Tried outlets to the submenu item but they don't work. They're connected in the
  // prototype menu item when first instantiated by the app, but when that's copied
  // to make a dynamic batch item those outlet of course end up nil. 
  // Instead the menu position are hardcoded here, keep in sync with any changes to
  // the batch item prototype's submenu.
  private var replaySubmenuItem: NSMenuItem? { submenu?.itemsWithMinCount(3)?[0] }
  private var renameSubmenuItem: NSMenuItem? { submenu?.itemsWithMinCount(3)?[1] }
  private var clipItemSeparator: NSMenuItem? { submenu?.itemsWithMinCount(3)?[2] }
  
  static var itemGroupCount: Int = 1
  
  var firstClipItemIndex: Int? { (submenu?.numberOfItems ?? 0) > 3 ? 3 : nil }
  var postClipItemIndex: Int? { submenu?.numberOfItems }
  var clipCount: Int { clipItemCount / Self.itemGroupCount }
  var clipItemCount: Int {
    guard let firstIndex = firstClipItemIndex, let postIndex = postClipItemIndex else { return 0 }
    return postIndex - firstIndex 
  }
  
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
