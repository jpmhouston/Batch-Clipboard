//
//  AdvancedSettingsViewController.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2025-07-10.
//  Portions Copyright © 2025 Bananameter Labs. All rights reserved.
//
//  Based on AdvancedSettingsViewController.swift from the Maccy project
//  Portions Copyright © 2024 Alexey Rodionov. All rights reserved.
//

import AppKit
import Settings

class AdvancedSettingsViewController: NSViewController, SettingsPane {
  public let paneIdentifier = Settings.PaneIdentifier.advanced
  public let paneTitle = NSLocalizedString("preferences_advanced", comment: "")
  public let toolbarItemIcon = NSImage(named: .doubleGear)!
  
  override var nibName: NSNib.Name? { "AdvancedSettingsViewController" }
  
  @IBOutlet weak var advancedPasteButton: NSButton!
  @IBOutlet weak var turnOffMonitoringButton: NSButton!
  @IBOutlet weak var avoidTakingFocusButton: NSButton!
  @IBOutlet weak var legacyFocusButton: NSButton!
  @IBOutlet weak var clearOnQuitButton: NSButton!
  @IBOutlet weak var clearSystemClipboardButton: NSButton!
  @IBOutlet weak var initialHistoryOffDescriptionField: NSTextField!
  @IBOutlet weak var subsequentHistoryOnDescriptionField: NSTextField!
  @IBOutlet weak var historyOffDescriptionConstraintAbove: NSLayoutConstraint!
  @IBOutlet var historyOffDescriptionConstraintBelow: NSLayoutConstraint! // muat not be weak
  
  private var replacementHistoryOnDescriptionConstraintAbove: NSLayoutConstraint?
  
  private let exampleIgnoredType = "zzz.yyy.xxx"
  
  override func viewWillAppear() {
    super.viewWillAppear()
    populateAdvancedPaste()
    populateAvoidTakingFocus()
    populateLegacyFocus()
    populateClearOnQuit()
    populateClearSystemClipboard()
    populateTurnOffMonitoring()
    updateMonitoringDescription()
  }
  
  @IBAction func advancedPasteChanged(_ sender: NSButton) {
    UserDefaults.standard.showAdvancedPasteMenuItems = (sender.state == .on)
  }
  
  @IBAction func avoidTakingFocusChanged(_ sender: NSButton) {
    UserDefaults.standard.avoidTakingFocus = (sender.state == .on)
  }
  
  @IBAction func clearOnQuitChanged(_ sender: NSButton) {
    UserDefaults.standard.clearOnQuit = (sender.state == .on)
  }
  
  @IBAction func clearSystemClipboardChanged(_ sender: NSButton) {
    UserDefaults.standard.clearSystemClipboard = (sender.state == .on)
  }
  
  @IBAction func legacyFocusChanged(_ sender: NSButton) {
    UserDefaults.standard.legacyFocusTechnique = (sender.state == .on)
  }
  
  @IBAction func turnOffMonitoringChanged(_ sender: NSButton) {
    UserDefaults.standard.ignoreEvents = (sender.state == .on)
  }
  
  private func populateAdvancedPaste() {
    advancedPasteButton.state = UserDefaults.standard.showAdvancedPasteMenuItems ? .on : .off
  }
  
  private func populateAvoidTakingFocus() {
    avoidTakingFocusButton.state = UserDefaults.standard.avoidTakingFocus ? .on : .off
  }
  
  private func populateLegacyFocus() {
    legacyFocusButton.state = UserDefaults.standard.legacyFocusTechnique ? .on : .off
  }
  
  private func populateClearOnQuit() {
    clearOnQuitButton.state = UserDefaults.standard.clearOnQuit ? .on : .off
  }
  
  private func populateClearSystemClipboard() {
    clearSystemClipboardButton.state = UserDefaults.standard.clearSystemClipboard ? .on : .off
  }
  
  private func populateTurnOffMonitoring() {
    turnOffMonitoringButton.state = UserDefaults.standard.ignoreEvents ? .on : .off
  }
  
  private func updateMonitoringDescription() {
    if UserDefaults.standard.keepHistory {
      // hide the extra description label that's regarding history and continuous
      // clipboard monitoring being off
      if let replacementConstraint = replacementHistoryOnDescriptionConstraintAbove {
        replacementConstraint.isActive = true
      } else {
        // make duplcate of historyOffDescriptionConstraintAbove but for subsequentHistoryOnDescriptionField
        let originalConstraint: NSLayoutConstraint = historyOffDescriptionConstraintAbove
        guard var from = originalConstraint.firstItem, var to = originalConstraint.secondItem else {
          return
        }
        if originalConstraint.firstItem as? NSTextField == initialHistoryOffDescriptionField {
          from = subsequentHistoryOnDescriptionField
        } else if originalConstraint.secondItem as? NSTextField == initialHistoryOffDescriptionField {
          to = subsequentHistoryOnDescriptionField
        } else {
          return
        }
        let replacementConstraint = NSLayoutConstraint(
          item: from, attribute: originalConstraint.firstAttribute, relatedBy: originalConstraint.relation,
          toItem: to, attribute: originalConstraint.secondAttribute, multiplier: originalConstraint.multiplier, constant: originalConstraint.constant)
        replacementHistoryOnDescriptionConstraintAbove = replacementConstraint 
        replacementConstraint.isActive = true
      }
      historyOffDescriptionConstraintBelow.isActive = false
      initialHistoryOffDescriptionField.isHidden = true
      view.layer?.setNeedsLayout()
    } else {
      // ensure the extra description label is shown that's regarding history and
      // continuous clipboard monitoring being off
      replacementHistoryOnDescriptionConstraintAbove?.isActive = false
      historyOffDescriptionConstraintBelow.isActive = true
      initialHistoryOffDescriptionField.isHidden = false
      view.layer?.setNeedsLayout()
    }
  }
  
}
