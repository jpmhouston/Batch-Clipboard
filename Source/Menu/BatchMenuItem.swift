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
  
  // Tried outlets to the submenu item but they don't work. They're connected in the
  // prototype menu item when first instantiated by the app, but when that's copied
  // to make a dynamic batch item those outlet of course end up nil. 
  // Instead the menu position are hardcoded here, keep in sync with any changes to
  // the batch item prototype's submenu.
  private var replaySubmenuItem: NSMenuItem? { submenu?.itemsWithMinCount(6)?[0] }
  private var replayAltLoopingSubmenuItem: NSMenuItem? { submenu?.itemsWithMinCount(6)?[1] }
  private var replayDfltLoopingSubmenuItem: NSMenuItem? { submenu?.itemsWithMinCount(6)?[2] }
  private var replayAltOnceSubmenuItem: NSMenuItem? { submenu?.itemsWithMinCount(6)?[3] }
  private var editSubmenuItem: NSMenuItem? { submenu?.itemsWithMinCount(6)?[4] }
  private var clipItemSeparator: NSMenuItem? { submenu?.itemsWithMinCount(6)?[5] }
  
  static var itemGroupCount: Int = 1
  
  var firstClipItemIndex: Int? { (submenu?.numberOfItems ?? 0) > 6 ? 6 : nil }
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
  
  func configured(withBatch batch: Batch) -> Self {
    self.batch = batch
    self.title = batch.makeTruncatedTitle()
    refreshSubmenuItems()
    return self
  }
  
  func regenerateTitle() {
    guard let batch = batch else {
      return
    }
    title = batch.makeTruncatedTitle()
  }
  
  func refreshSubmenuItems() {
    guard let batch = batch else {
      return
    }
    
    let replayItem: NSMenuItem?
    let altItem: NSMenuItem?
    if !batch.repeating {
      replayItem = replaySubmenuItem
      altItem = replayAltLoopingSubmenuItem
      replayDfltLoopingSubmenuItem?.isHidden = true
      replayAltOnceSubmenuItem?.isHidden = true
      replayAltOnceSubmenuItem?.isAlternate = false
    } else {
      replayItem = replayDfltLoopingSubmenuItem
      altItem = replayAltOnceSubmenuItem
      replaySubmenuItem?.isHidden = true
      replayAltLoopingSubmenuItem?.isHidden = true
      replayAltLoopingSubmenuItem?.isAlternate = false
    }
    
    replayItem?.isHidden = false
    altItem?.isHidden = false
    // normally no key equivalent in the top menu items, the alt items as aternates using the option key
    // but if batch has a shortcut, show it in the menu and explicitly show the alt item (not as alternate)
    if let shortcut = batch.keyShortcut {
      MainActor.assumeIsolated() {
        replayItem?.setShortcut(shortcut)
      }
      altItem?.isAlternate = false
    } else {
      replayItem?.keyEquivalent = ""
      replayItem?.keyEquivalentModifierMask = []
      altItem?.isAlternate = true
      altItem?.keyEquivalentModifierMask = .option
    }
    
//    if !batch.repeating {
//      replaySubmenuItem?.isHidden = false
//      replayAltLoopingSubmenuItem?.isHidden = false
//      // normally no key equivalent in the top menu items, the alt items as aternates using the option key
//      // but if batch has a shortcut, show it in the menu and explicitly show the alt item (not as alternate)
//      if let shortcut = batch.keyShortcut {
//        MainActor.assumeIsolated() {
//          replaySubmenuItem?.setShortcut(shortcut)
//        }
//        replayAltLoopingSubmenuItem?.isAlternate = false
//      } else {
//        replaySubmenuItem?.keyEquivalent = ""
//        replaySubmenuItem?.keyEquivalentModifierMask = []
//        replayAltLoopingSubmenuItem?.isAlternate = true
//        replayAltLoopingSubmenuItem?.keyEquivalentModifierMask = .option
//      }
//      
//      replayDfltLoopingSubmenuItem?.isHidden = true
//      replayAltOnceSubmenuItem?.isHidden = true
//      replayAltOnceSubmenuItem?.isAlternate = false
//    } else {
//      replayDfltLoopingSubmenuItem?.isHidden = false
//      replayAltOnceSubmenuItem?.isHidden = false
//      if let shortcut = batch.keyShortcut {
//        MainActor.assumeIsolated() {
//          replayDfltLoopingSubmenuItem?.setShortcut(shortcut)
//        }
//        replayAltOnceSubmenuItem?.isAlternate = false
//      } else {
//        replayDfltLoopingSubmenuItem?.keyEquivalent = ""
//        replayDfltLoopingSubmenuItem?.keyEquivalentModifierMask = []
//        replayAltOnceSubmenuItem?.isAlternate = true
//        replayAltOnceSubmenuItem?.keyEquivalentModifierMask = .option
//      }
//      
//      replaySubmenuItem?.isHidden = true
//      replayAltLoopingSubmenuItem?.isHidden = true
//      replayAltLoopingSubmenuItem?.isAlternate = false
//    }
    
//    replaySubmenuItem?.isHidden = batch.repeating
//    replayAltLoopingSubmenuItem?.isHidden = batch.repeating
//    replayDfltLoopingSubmenuItem?.isHidden = !batch.repeating
//    replayAltOnceSubmenuItem?.isHidden = !batch.repeating
//    
//    // normally no key equivalent in the top menu items, the alt items as aternates using the option key
//    // but if batch has a shortcut, show it in the menu and explicitly show the alt item (not as alternate)
//    replaySubmenuItem?.keyEquivalent = ""
//    replaySubmenuItem?.keyEquivalentModifierMask = []
//    replayAltLoopingSubmenuItem?.keyEquivalent = ""
//    replayAltLoopingSubmenuItem?.isAlternate = !batch.repeating && batch.keyShortcut == nil
//    replayAltLoopingSubmenuItem?.keyEquivalentModifierMask = .option
//    
//    replayDfltLoopingSubmenuItem?.keyEquivalent = ""
//    replayDfltLoopingSubmenuItem?.keyEquivalentModifierMask = []
//    replayAltOnceSubmenuItem?.keyEquivalent = ""
//    replayAltOnceSubmenuItem?.isAlternate = batch.repeating && batch.keyShortcut == nil
//    replayAltOnceSubmenuItem?.keyEquivalentModifierMask = .option
//    
//    if let shortcut = batch.keyShortcut {
//      let subitem = !batch.repeating ? replaySubmenuItem : replayDfltLoopingSubmenuItem
//      MainActor.assumeIsolated() {
//        subitem?.setShortcut(shortcut)
//      }
//    }
  }
  
}

extension NSMenu {
  func itemsWithMinCount(_ n: Int) -> [NSMenuItem]? {
    items.count >= n ? items : nil
  }
}
