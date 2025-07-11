//
//  NSRect+Centered.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-07-10.
//  Portions Copyright © 2024 Bananameter Labs. All rights reserved.
//
//  Based on NSRect+Centered.swift from the Maccy project
//  Portions are copyright © 2024 Alexey Rodionov. All rights reserved.
//

import Foundation

extension NSRect {
  static func centered(ofSize size: NSSize, in frame: NSRect) -> NSRect {
    let topLeftX = (frame.width - size.width) / 2 + frame.minX
    var topLeftY = (frame.height + size.height) / 2 + frame.minY
    if frame.height < size.height {
      topLeftY = frame.maxY
    }

    return NSRect(x: topLeftX + 1.0, y: topLeftY + 1.0, width: size.width, height: size.height)
  }
}
