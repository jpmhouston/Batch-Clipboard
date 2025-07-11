//
//  IgnoreSettingsViewController.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-07-10.
//  Portions Copyright © 2024 Bananameter Labs. All rights reserved.
//
//  Based on IgnoreSettingsViewController.swift from the Maccy project
//  Portions are copyright © 2024 Alexey Rodionov. All rights reserved.
//

import Cocoa
import Settings

class IgnoreSettingsViewController: NSViewController, SettingsPane {
  public let paneIdentifier = Settings.PaneIdentifier.ignore
  public let paneTitle = NSLocalizedString("preferences_ignore", comment: "")
  public let toolbarItemIcon = NSImage(named: .negationSign)!

  override var nibName: NSNib.Name? { "IgnoreSettingsViewController" }
}
