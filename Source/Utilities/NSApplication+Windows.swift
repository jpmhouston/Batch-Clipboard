//
//  NSApplication+Windows.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-07-10.
//  Portions Copyright © 2025 Bananameter Labs. All rights reserved.
//
//  Based on NSApplication+Windows.swift from the Maccy project
//  Portions Copyright © 2024 Alexey Rodionov. All rights reserved.
//

import AppKit

extension NSApplication {
  var characterPickerWindow: NSWindow? { windows.first { $0.className == "NSPanelViewBridge" } }
  var menuWindow: NSWindow? {
    windows.first { window in
      window.className == "NSPopupMenuWindow" // macOS 14 and later
      || window.className == "NSMenuWindowManagerWindow" // macOS 13 - 14
      || window.className == "NSCarbonMenuWindow" // macOS 12 and earlier
    }
  }
  func menuWindow(containing rect: NSRect) -> NSWindow? {
    windows.first { window in
      (window.className == "NSPopupMenuWindow" // macOS 14 and later
       || window.className == "NSMenuWindowManagerWindow" // macOS 13 - 14
       || window.className == "NSCarbonMenuWindow") // macOS 12 and earlier
      && NSContainsRect(window.frame, rect)
    }
  }
  var statusBarWindow: NSWindow? { windows.first { $0.className == "NSStatusBarWindow" } }
}
