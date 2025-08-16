//
//  KeyboardShortcutHandlers.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-03-21.
//  Portions Copyright © 2025 Bananameter Labs. All rights reserved.
//
//  Based on GlobalHotKeys.swift from the Maccy project
//  Portions Copyright © 2024 Alexey Rodionov. All rights reserved.
//

import AppKit
import KeyboardShortcuts
import Sauce

class StartKeyboardShortcutHandler {
  typealias Handler = () -> Void

//  static public var key: Key? {
//    guard let key = KeyboardShortcuts.Shortcut(name: .queueStart)?.key else {
//      return nil
//    }
//    return Sauce.shared.key(for: key.rawValue)
//  }
//  static public var modifierFlags: NSEvent.ModifierFlags? { KeyboardShortcuts.Shortcut(name: .queueStart)?.modifiers }

  private var handler: Handler

  init(_ handler: @escaping Handler) {
    self.handler = handler
    KeyboardShortcuts.onKeyDown(for: .queueStart, action: handler)
  }
}

class CopyKeyboardShortcutHandler {
  typealias Handler = () -> Void

//  static public var key: Key? {
//    guard let key = KeyboardShortcuts.Shortcut(name: .queuedCopy)?.key else {
//      return nil
//    }
//    return Sauce.shared.key(for: key.rawValue)
//  }
//  static public var modifierFlags: NSEvent.ModifierFlags? { KeyboardShortcuts.Shortcut(name: .queuedCopy)?.modifiers }

  private var handler: Handler

  init(_ handler: @escaping Handler) {
    self.handler = handler
    KeyboardShortcuts.onKeyDown(for: .queuedCopy, action: handler)
  }
}

class PasteKeyboardShortcutHandler {
  typealias Handler = () -> Void

//  static public var key: Key? {
//    guard let key = KeyboardShortcuts.Shortcut(name: .queuedPaste)?.key else {
//      return nil
//    }
//    return Sauce.shared.key(for: key.rawValue)
//  }
//  static public var modifierFlags: NSEvent.ModifierFlags? { KeyboardShortcuts.Shortcut(name: .queuedPaste)?.modifiers }

  private var handler: Handler

  init(_ handler: @escaping Handler) {
    self.handler = handler
    KeyboardShortcuts.onKeyDown(for: .queuedPaste, action: handler)
  }
}

class ReplayLastKeyboardShortcutHandler {
  typealias Handler = () -> Void
  
//  static public var key: Key? {
//    guard let key = KeyboardShortcuts.Shortcut(name: .queueReplay)?.key else {
//      return nil
//    }
//    return Sauce.shared.key(for: key.rawValue)
//  }
//  static public var modifierFlags: NSEvent.ModifierFlags? { KeyboardShortcuts.Shortcut(name: .queueReplay)?.modifiers }
  
  private var handler: Handler
  
  init(_ handler: @escaping Handler) {
    self.handler = handler
    KeyboardShortcuts.onKeyDown(for: .queueReplay, action: handler)
  }
}

class ReplaySavedKeyboardShortcutHandler: Hashable {
  typealias Handler = (Batch) -> Void
  
  var name: KeyboardShortcuts.Name
  var batch: Batch
  private var handler: Handler
  
  //var hotKey: KeyboardShortcuts.Name { name } // other code calls it this, or hotKey definition  
  var nameString: String { name.rawValue }
  
  init(for name: KeyboardShortcuts.Name, batch: Batch, _ handler: @escaping Handler) {
    self.name = name
    self.batch = batch
    self.handler = handler
    installHandler()
  }
  
  func installHandler() {
    KeyboardShortcuts.onKeyDown(for: name, action: { [weak self] in
      guard let self = self else { return }
      handler(batch)
    })
  }
  
  static func == (lhs: ReplaySavedKeyboardShortcutHandler, rhs: ReplaySavedKeyboardShortcutHandler) -> Bool {
    return lhs.name.rawValue == rhs.name.rawValue
  }
  
  func hash(into hasher: inout Hasher) {
      hasher.combine(name.rawValue)
  }
}
