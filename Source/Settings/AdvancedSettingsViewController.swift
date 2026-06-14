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
  @IBOutlet weak var clearDataVsBatchesLabel: NSTextField!
  @IBOutlet weak var advancedPasteCheckbox: NSButton!
  @IBOutlet weak var repeatBatchCheckbox: NSButton!
  @IBOutlet weak var repeatBatchSection: NSStackView!
  @IBOutlet weak var menuHidingCheckbox: NSButton!
  @IBOutlet weak var menuHidingSection: NSStackView!
  @IBOutlet weak var turnOffMonitoringCheckbox: NSButton!
  @IBOutlet weak var avoidTakingFocusCheckbox: NSButton!
  @IBOutlet weak var legacyFocusCheckbox: NSButton!
  @IBOutlet weak var initialHistoryOffDescriptionField: NSTextField!
  @IBOutlet weak var subsequentHistoryOnDescriptionField: NSTextField!
  @IBOutlet weak var pasteboardLoggingCheckbox: NSButton!
  
  #if MENU_HIDING_IN_ADVANCED_PANEL
  private var showMenuHiding: Bool { AppModel.allowMenuHiding }
  #else
  private var showMenuHiding: Bool { false }
  #endif
  private var menuHidingObserver: NSKeyValueObservation?
  
  override func viewWillAppear() {
    super.viewWillAppear()
    
    populateClearOnQuit()
    populateClearSystemClipboard()
    updateClearDataDescriptionVisibility()
    populateAdvancedPaste()
    updateRepeatBatchVisibility()
    populateRepeatBatch()
    updateMenuHidingVisibility()
    populateMenuHiding()
    startObservingMenuHiding()
    populateTurnOffMonitoring()
    updateMonitoringDescription()
    populateAvoidTakingFocus()
    populateLegacyFocus()
    populateLogging()
  }
  
  override func viewWillDisappear() {
    super.viewWillDisappear()
    stopObservingMenuHiding()
  }
  
  private func startObservingMenuHiding() {
    guard showMenuHiding else {
      return
    }
    menuHidingObserver = UserDefaults.standard.observe(\.menuHiddenWhenInactive, options: .new) { [weak self] _, _ in
      guard let self = self else { return }
      self.populateMenuHiding()
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
  
  private func updateClearDataDescriptionVisibility() {
    clearDataVsBatchesLabel.isHidden = !AppModel.allowSavedBatches
  }
  
  private func populateAdvancedPaste() {
    advancedPasteCheckbox.state = UserDefaults.standard.showAdvancedPasteMenuItems ? .on : .off
  }
  
  private func populateRepeatBatch() {
    repeatBatchCheckbox.state = UserDefaults.standard.showRepeatBatchDefaultOption ? .on : .off
  }
  
  private func updateRepeatBatchVisibility() {
    repeatBatchCheckbox.isHidden = !AppModel.allowSavedBatches 
  }
  
  private func populateMenuHiding() {
    let hideMenu = UserDefaults.standard.menuHiddenWhenInactive
    menuHidingCheckbox.state = hideMenu ? .on : .off
  }
  
  private func updateMenuHidingVisibility() {
    // show the menu hiding checbox & field when feature allowed
    menuHidingSection.isHidden = !showMenuHiding
  }
  
  private func populateTurnOffMonitoring() {
    turnOffMonitoringCheckbox.state = UserDefaults.standard.ignoreEvents ? .on : .off
  }
  
  private func updateMonitoringDescription() {
    // there's an extra description label regarding history and continuous clipboard
    // monitoring being off, hide it when using history, show it otherwise
    initialHistoryOffDescriptionField.isHidden = UserDefaults.standard.keepHistory
  }
  
  private func populateAvoidTakingFocus() {
    avoidTakingFocusCheckbox.state = UserDefaults.standard.avoidTakingFocus ? .on : .off
  }
  
  private func populateLegacyFocus() {
    legacyFocusCheckbox.state = UserDefaults.standard.legacyFocusTechnique ? .on : .off
  }
  
  private func populateLogging() {
    pasteboardLoggingCheckbox.state = UserDefaults.standard.pasteboardLoggingOn ? .on : .off
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
  
  @IBAction func repeatBatchChanged(_ sender: NSButton) {
    UserDefaults.standard.showRepeatBatchDefaultOption = (sender.state == .on)
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
  
  @IBAction func pasteboardLoggingChanged(_ sender: NSButton) {
    UserDefaults.standard.pasteboardLoggingOn = (sender.state == .on)
  }
  
  @IBAction func resetAlertSuppresionPressed(_ sender: NSButton) {
    UserDefaults.standard.suppressClearAlert = false
    UserDefaults.standard.suppressDeleteBatchAlert = false
    UserDefaults.standard.suppressSaveClipsAlert = false
    UserDefaults.standard.suppressUseHistoryAlert = false
  }
}
