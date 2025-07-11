//
//  NSWorkspace+ApplicationName.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-07-10.
//  Portions Copyright © 2024 Bananameter Labs. All rights reserved.
//
//  Based on NSWorkspace+ApplicationName.swift from the Maccy project
//  Portions are copyright © 2024 Alexey Rodionov. All rights reserved.
//

import AppKit

extension NSWorkspace {
  func applicationName(url: URL) -> String {
    if let bundle = Bundle(url: url) {
      if let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String {
        return displayName
      } else if let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String {
        return name
      }
    }

    return url.deletingLastPathComponent().lastPathComponent
  }
}
