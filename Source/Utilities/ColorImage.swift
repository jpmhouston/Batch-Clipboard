//
//  ColorImage.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-07-10.
//  Portions Copyright © 2024 Bananameter Labs. All rights reserved.
//
//  Based on ColorImage.swift from the Maccy project
//  Portions are copyright © 2024 Alexey Rodionov. All rights reserved.
//

import AppKit
import SwiftHEXColors

class ColorImage {
  static func from(_ colorHex: String) -> NSImage? {
    guard let color = NSColor(hexString: colorHex) else {
      return nil
    }

    let image = NSImage(size: NSSize(width: 10, height: 10))
    image.lockFocus()
    color.drawSwatch(in: NSRect(x: 0, y: 0, width: 10, height: 10))
    image.unlockFocus()

    return image
  }
}
