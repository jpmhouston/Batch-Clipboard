//
//  KeyboardSettingsViewController.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-07-10.
//  Portions Copyright © 2025 Bananameter Labs. All rights reserved.
//
//  Based on GeneralSettingsViewController.swift from the Maccy project
//  Portions Copyright © 2024 Alexey Rodionov. All rights reserved.
//

import AppKit
import KeyboardShortcuts
import Settings

class KeyboardSettingsViewController: NSViewController, SettingsPane {
  public let paneIdentifier = Settings.PaneIdentifier.keyboard
  public let paneTitle = NSLocalizedString("preferences_keyboard", comment: "")
  public let toolbarItemIcon = NSImage(named: .keyboard)!
  
  override var nibName: NSNib.Name? { "KeyboardSettingsViewController" }
  
  private let copyHotkeyRecorder = KeyboardShortcuts.RecorderCocoa(for: .queuedCopy)
  private let pasteHotkeyRecorder = KeyboardShortcuts.RecorderCocoa(for: .queuedPaste)
  private let startHotkeyRecorder = KeyboardShortcuts.RecorderCocoa(for: .queueStart)
  private let startWithCurrentHotkeyRecorder = KeyboardShortcuts.RecorderCocoa(for: .queueStartWithCurrent)
  private let replayHotkeyRecorder = KeyboardShortcuts.RecorderCocoa(for: .queueReplay)
  
  @IBOutlet weak var copyHotkeyContainerView: NSView?
  @IBOutlet weak var pasteHotkeyContainerView: NSView?
  @IBOutlet weak var startHotkeyContainerView: NSView?
  @IBOutlet weak var startWithCurrentHotkeyContainerView: NSView?
  @IBOutlet weak var replayHotkeyContainerView: NSView?
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    func addSubviewWithManualLayout(_ par: NSView?, _ sub: NSView?) {
      guard let par = par, let sub = sub else { return }
      par.translatesAutoresizingMaskIntoConstraints = false
      sub.translatesAutoresizingMaskIntoConstraints = false
      par.addSubview(sub)
      par.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|[s]|", metrics: nil, views: ["s": sub]))
      par.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[s]|", metrics: nil, views: ["s": sub]))
    }
    // using the above func instead of addSubview fixed layout issues with the KeyboardShortcuts.RecorderCocoa views
    addSubviewWithManualLayout(copyHotkeyContainerView, copyHotkeyRecorder)
    addSubviewWithManualLayout(pasteHotkeyContainerView, pasteHotkeyRecorder)
    addSubviewWithManualLayout(startHotkeyContainerView, startHotkeyRecorder)
    addSubviewWithManualLayout(startWithCurrentHotkeyContainerView, startWithCurrentHotkeyRecorder)
    addSubviewWithManualLayout(replayHotkeyContainerView, replayHotkeyRecorder)
  }
}
