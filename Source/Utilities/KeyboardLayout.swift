//
//  KeyboardLayout.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-07-10.
//  Portions Copyright © 2025 Bananameter Labs. All rights reserved.
//
//  Based on KeyboardLayout.swift from the Maccy project
//  Portions Copyright © 2024 Alexey Rodionov. All rights reserved.
//

import Carbon
import Sauce

class KeyboardLayout {
  static var current: KeyboardLayout { KeyboardLayout() }

  // Dvorak - QWERTY ⌘ (https://github.com/p0deje/Maccy/issues/482)
  // bépo 1.1 - Azerty ⌘ (https://github.com/p0deje/Maccy/issues/520)
  var commandSwitchesToQWERTY: Bool { localizedName.hasSuffix("⌘") }

  var localizedName: String {
    if let value = TISGetInputSourceProperty(inputSource, kTISPropertyLocalizedName) {
      return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
    } else {
      return ""
    }
  }

  private var inputSource: TISInputSource!

  init() {
    inputSource = TISCopyCurrentKeyboardLayoutInputSource().takeUnretainedValue()
  }
}
