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
  
  @IBOutlet weak var clearOnQuitCheckbox: NSButton!
  @IBOutlet weak var clearSystemClipboardCheckbox: NSButton!
  @IBOutlet weak var advancedPasteCheckbox: NSButton!
  @IBOutlet weak var menuHidingCheckbox: NSButton!
  @IBOutlet weak var menuHidingLabel: NSTextField!
  @IBOutlet weak var turnOffMonitoringCheckbox: NSButton!
  @IBOutlet weak var avoidTakingFocusCheckbox: NSButton!
  @IBOutlet weak var legacyFocusCheckbox: NSButton!
  @IBOutlet weak var initialHistoryOffDescriptionField: NSTextField!
  @IBOutlet weak var subsequentHistoryOnDescriptionField: NSTextField!
  @IBOutlet var showHistoryOffDescriptionConstraint: NSLayoutConstraint! // these constraint
  @IBOutlet var hideHistoryOffDescriptionConstraint: NSLayoutConstraint! // outlets must not be weak
  @IBOutlet var showMenuHidingControlsConstraint: NSLayoutConstraint! // "
  @IBOutlet var hideMenuHidingControlsConstraint: NSLayoutConstraint!
  
  private var menuHidingObserver: NSKeyValueObservation?
  
  override func viewWillAppear() {
    super.viewWillAppear()
    
    populateClearOnQuit()
    populateClearSystemClipboard()
    populateAdvancedPaste()
    updateMenuHidingControls()
    populateMenuHiding()
    startObservingMenuHiding()
    populateTurnOffMonitoring()
    updateMonitoringDescription()
    populateAvoidTakingFocus()
    populateLegacyFocus()
  }
  
  override func viewWillDisappear() {
    stopObservingMenuHiding()
  }
  
  private func startObservingMenuHiding() {
    guard AppModel.allowMenuHiding else {
      return
    }
    menuHidingObserver = UserDefaults.standard.observe(\.menuHiddenWhenInactive, options: .new) { [weak self] _, change in
      guard let self = self, let newHideValue = change.newValue else { return }
      if newHideValue != (menuHidingCheckbox.state == .on) {
        menuHidingCheckbox.state = newHideValue ? .on : .off
      }
    }
  }
  
  private func stopObservingMenuHiding() {
    menuHidingObserver?.invalidate()
    menuHidingObserver = nil
  }
  
  // MARK: -
  
  private func populateClearOnQuit() {
    clearOnQuitCheckbox.state = UserDefaults.standard.clearOnQuit ? .on : .off
  }
  
  private func populateClearSystemClipboard() {
    clearSystemClipboardCheckbox.state = UserDefaults.standard.clearSystemClipboard ? .on : .off
  }
  
  private func populateAdvancedPaste() {
    advancedPasteCheckbox.state = UserDefaults.standard.showAdvancedPasteMenuItems ? .on : .off
  }
  
  private func populateMenuHiding() {
    let hideMenu = UserDefaults.standard.menuHiddenWhenInactive
    menuHidingCheckbox.state = hideMenu ? .on : .off
  }
  
  private func updateMenuHidingControls() {
    // show the menu hiding checbox & field when feature allowed
    if AppModel.allowMenuHiding {
      showMenuHidingControlsConstraint.isActive = true
      hideMenuHidingControlsConstraint.isActive = false
      menuHidingCheckbox.isHidden = false
      menuHidingLabel.isHidden = false
    } else {
      showMenuHidingControlsConstraint.isActive = false
      hideMenuHidingControlsConstraint.isActive = true
      // this constraint priority is initially too low to make editing in xcode nicer, fix 
      hideMenuHidingControlsConstraint.priority =
        max(showMenuHidingControlsConstraint.priority, hideMenuHidingControlsConstraint.priority)
      menuHidingCheckbox.isHidden = true
      menuHidingLabel.isHidden = true
    }
  }
  
  private func populateTurnOffMonitoring() {
    turnOffMonitoringCheckbox.state = UserDefaults.standard.ignoreEvents ? .on : .off
  }
  
  private func updateMonitoringDescription() {
    // there's an extra description label regarding history and continuous clipboard
    // monitoring being off, hide it when using history, show it otherwise
    if UserDefaults.standard.keepHistory {
      showHistoryOffDescriptionConstraint.isActive = false
      hideHistoryOffDescriptionConstraint.isActive = true
      // this constraint priority is initially too low to make editing in xcode nicer, fix 
      hideHistoryOffDescriptionConstraint.priority =
        max(showHistoryOffDescriptionConstraint.priority, hideHistoryOffDescriptionConstraint.priority)
      initialHistoryOffDescriptionField.isHidden = true
      view.layer?.setNeedsLayout()
    } else {
      showHistoryOffDescriptionConstraint.isActive = true
      hideHistoryOffDescriptionConstraint.isActive = false
      initialHistoryOffDescriptionField.isHidden = false
      view.layer?.setNeedsLayout()
    }
  }
  
  private func populateAvoidTakingFocus() {
    avoidTakingFocusCheckbox.state = UserDefaults.standard.avoidTakingFocus ? .on : .off
  }
  
  private func populateLegacyFocus() {
    legacyFocusCheckbox.state = UserDefaults.standard.legacyFocusTechnique ? .on : .off
  }
  
  // MARK: -
  
  @IBAction func clearOnQuitChanged(_ sender: NSButton) {
    UserDefaults.standard.clearOnQuit = (sender.state == .on)
  }
  
  @IBAction func clearSystemClipboardChanged(_ sender: NSButton) {
    UserDefaults.standard.clearSystemClipboard = (sender.state == .on)
  }
  
  @IBAction func advancedPasteChanged(_ sender: NSButton) {
    UserDefaults.standard.showAdvancedPasteMenuItems = (sender.state == .on)
  }
  
  @IBAction func menuHidingChanged(_ sender: NSButton) {
    UserDefaults.standard.menuHiddenWhenInactive = (sender.state == .on)
  }
  
  @IBAction func turnOffMonitoringChanged(_ sender: NSButton) {
    UserDefaults.standard.ignoreEvents = (sender.state == .on)
  }
  
  @IBAction func avoidTakingFocusChanged(_ sender: NSButton) {
    UserDefaults.standard.avoidTakingFocus = (sender.state == .on)
  }
  
  @IBAction func legacyFocusChanged(_ sender: NSButton) {
    UserDefaults.standard.legacyFocusTechnique = (sender.state == .on)
  }
  
}
