//
//  NSScreen+ForPopup.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-07-10.
//  Portions Copyright © 2024 Bananameter Labs. All rights reserved.
//
//  Based on NSScreen+ForPopup.swift from the Maccy project
//  Portions are copyright © 2024 Alexey Rodionov. All rights reserved.
//

import AppKit

extension NSScreen {
  static var forPopup: NSScreen? {
    let desiredScreen = UserDefaults.standard.popupScreen
    if desiredScreen == 0 || desiredScreen > NSScreen.screens.count {
      return NSScreen.main
    } else {
      return NSScreen.screens[desiredScreen - 1]
    }
  }
}
