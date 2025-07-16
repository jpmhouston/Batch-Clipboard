//
//  KeyboardShortcuts.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2025-07-10.
//  Portions Copyright © 2025 Bananameter Labs. All rights reserved.
//
//  Based on KeyboardShortcuts.Name+Shortcuts.swift from the Maccy project
//  Portions Copyright © 2024 Alexey Rodionov. All rights reserved.
//

import KeyboardShortcuts

extension KeyboardShortcuts.Name {
  // start queue mode
  static let queueStart = Self("queueStart", default: nil)
  // special copy that starts queue mode first if not yet in queue mode
  static let queuedCopy = Self("queuedCopy", default: Shortcut(.c, modifiers: [.command, .control]))
  // special paste that advances to next in the queue if in queue mode
  static let queuedPaste = Self("queuedPaste", default: Shortcut(.v, modifiers: [.command, .control]))
}
