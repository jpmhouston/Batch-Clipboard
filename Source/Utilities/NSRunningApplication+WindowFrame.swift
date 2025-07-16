//
//  NSRunningApplication+WindowFrame.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-07-10.
//  Portions Copyright © 2025 Bananameter Labs. All rights reserved.
//
//  Based on NSRunningApplication+WindowFrame.swift from the Maccy project
//  Portions Copyright © 2024 Alexey Rodionov. All rights reserved.
//

import AppKit
import Carbon

extension NSRunningApplication {
  var windowFrame: NSRect? {
    let options = CGWindowListOption(arrayLiteral: [.excludeDesktopElements, .optionOnScreenOnly])
    let windowListInfo = CGWindowListCopyWindowInfo(options, CGWindowID(0))
    if let windowInfoList = windowListInfo as NSArray? as? [[String: AnyObject]] {
      for info in windowInfoList {
        if let windowPID = info["kCGWindowOwnerPID"] as? UInt32, windowPID == processIdentifier {
          if let screen = NSScreen.screens.first,
             let topLeftX = info["kCGWindowBounds"]?["X"] as? Double,
             let topLeftY = info["kCGWindowBounds"]?["Y"] as? Double,
             let width = info["kCGWindowBounds"]?["Width"] as? Double,
             let height = info["kCGWindowBounds"]?["Height"] as? Double {
            var rect = NSRect(x: topLeftX, y: topLeftY, width: width, height: height)
            // Convert CGWindowBounds to NSScreen coordinates
            // http://www.krizka.net/2010/04/20/converting-between-kcgwindowbounds-and-nswindowframe
            rect.origin.y = screen.frame.size.height - rect.origin.y - rect.size.height
            return rect
          }
        }
      }
    }

    return nil
  }
}
