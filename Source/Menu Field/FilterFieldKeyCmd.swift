//
//  FilterFieldKeyCmd.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-07-10.
//  Portions Copyright © 2025 Bananameter Labs. All rights reserved.
//
//  Based on KeyChords.swift from the Maccy project
//  Portions Copyright © 2024 Alexey Rodionov. All rights reserved.
//

import AppKit
import KeyboardShortcuts
import Sauce

enum FilterFieldKeyCmd: CaseIterable {
  // Fetch paste from Edit / Paste menu item.
  // Fallback to ⌘V if unavailable.
  static var pasteKey: Key {
    (NSApp.delegate as? AppDelegate)?.pasteMenuItem.key ?? .v
  }
  static var pasteKeyModifiers: NSEvent.ModifierFlags {
    (NSApp.delegate as? AppDelegate)?.pasteMenuItem.keyEquivalentModifierMask ?? [.command]
  }
  
  static var copyKey: Key {
    (NSApp.delegate as? AppDelegate)?.copyMenuItem.key ?? .c
  }
  static var copyKeyModifiers: NSEvent.ModifierFlags {
    (NSApp.delegate as? AppDelegate)?.copyMenuItem.keyEquivalentModifierMask ?? [.command]
  }
  
  static var cutKey: Key {
    (NSApp.delegate as? AppDelegate)?.cutMenuItem.key ?? .x
  }
  static var cutKeyModifiers: NSEvent.ModifierFlags {
    (NSApp.delegate as? AppDelegate)?.cutMenuItem.keyEquivalentModifierMask ?? [.command]
  }
  
  case clearSearch
  case deleteOneCharFromSearch
  case deleteLastWordFromSearch
  case moveToNext
  case moveToPrevious
  case openPreferences
  case cut
  case copy
  case paste
  case selectCurrentItem
  case ignored
  case unknown
  
  // swiftlint:disable cyclomatic_complexity
  init(_ key: Key, _ modifierFlags: NSEvent.ModifierFlags) {
    switch (key, modifierFlags) {
    case (.escape, []), (.u, [.control]):
      self = .clearSearch
    case (.delete, []), (.h, [.control]):
      self = .deleteOneCharFromSearch
    case (.w, [.control]):
      self = .deleteLastWordFromSearch
    case (.j, [.control]):
      self = .moveToNext
    case (.k, [.control]):
      self = .moveToPrevious
    case (FilterFieldKeyCmd.cutKey, FilterFieldKeyCmd.cutKeyModifiers):
      self = .cut
    case (FilterFieldKeyCmd.copyKey, FilterFieldKeyCmd.copyKeyModifiers):
      self = .copy
    case (FilterFieldKeyCmd.pasteKey, FilterFieldKeyCmd.pasteKeyModifiers):
      self = .paste
    case (.return, _), (.keypadEnter, _):
      self = .selectCurrentItem
    case (_, _) where Self.keysToSkip.contains(key) || !modifierFlags.isDisjoint(with: Self.modifiersToSkip):
      self = .ignored
    default:
      self = .unknown
    }
  }
  // swiftlint:enable cyclomatic_complexity
  
  private static let keysToSkip = [
    Key.home,
    Key.pageUp,
    Key.pageDown,
    Key.end,
    Key.downArrow,
    Key.leftArrow,
    Key.rightArrow,
    Key.upArrow,
    Key.escape,
    Key.tab,
    Key.f1,
    Key.f2,
    Key.f3,
    Key.f4,
    Key.f5,
    Key.f6,
    Key.f7,
    Key.f8,
    Key.f9,
    Key.f10,
    Key.f11,
    Key.f12,
    Key.f13,
    Key.f14,
    Key.f15,
    Key.f16,
    Key.f17,
    Key.f18,
    Key.f19,
    Key.eisu,
    Key.kana
  ]
  
  private static let modifiersToSkip = NSEvent.ModifierFlags([
    .command,
    .control,
    .option
  ])
  
}
