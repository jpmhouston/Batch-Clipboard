//
//  LoginItemIntroPageViewController.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2026-06-11.
//  Copyright © 2026 Bananameter Labs. All rights reserved.
//

import AppKit
#if canImport(ServiceManagement)
import ServiceManagement
#endif

class LoginItemIntroPageViewController: IntroPageController {
  enum OptionSelection: Int, CaseIterable {
    // must be in sync with the segmentedcontrol segments defined in the xib, including their order
    case set = 0, remind, unset
  }
  
  static var reminderCountdown = 3
  
  @IBOutlet var optionSelector: NSSegmentedControl?
  @IBOutlet var needsManualConfigurationLabel: NSTextField?
  @IBOutlet var choiceDescriptionSection: NSView?
  @IBOutlet var launchAtLoginChosenLabel: NSTextField?
  @IBOutlet var manuallyConfigureChosenLabel: NSTextField?
  @IBOutlet var remindChosenLabel: NSTextField?
  @IBOutlet var notConfiguredChosenLabel: NSTextField?
  @IBOutlet var fallbackSection: NSView?
  @IBOutlet var systemSettingsFallbackLabel: NSTextField?
  @IBOutlet var systemPreferencesFallbackLabel: NSTextField?
  
  // MARK:-
  
  override func willShow() -> NSButton? {
    setupVisibleManualConfigurationLabel()
    hideChoiceDescriptionLabels()
    setupChoiceControl() // might show one of the selected option labels, need to call last
    return nil
  }
  
  override func shouldSkip() -> Bool {
    #if DEBUG && EXERCISE_LOGINITEM_INTROPAGE // force alert to show each time
    UserDefaults.standard.loginItemChoicePending = true
    UserDefaults.standard.loginItemAskDelayCount = 0
    #endif
    return UserDefaults.standard.loginItemChoicePending == false
  }
  
  // MARK: -
  
  @IBAction func selectionChanged(_ sender: NSSegmentedControl) {
    hideChoiceDescriptionLabels()
    guard let option = OptionSelection(rawValue: sender.selectedSegment) else {
      return
    }
    
    switch option {
    case .set where canConfigProgrammatically:
      if setLaunchAtLogin() {
        showLaunchAtLoginChosenLabel()
      } else {
        sender.setSelected(false, forSegment: option.rawValue)
        showFallbackSection()
      }
      
    case .set:
      if openLoginItemsPanel() {
        showManuallyConfigureChosenLabel()
      } else {
        sender.setSelected(false, forSegment: option.rawValue)
      }
      
    case .remind:
      if setAskLater() {
        showRemindChosenLabel()
      } else {
        sender.setSelected(false, forSegment: option.rawValue)
      }
      
    case .unset:
      if dontLaunchAtLogin() {
        showNotConfiguredChosenLabel()
      } else {
        sender.setSelected(false, forSegment: option.rawValue)
        showFallbackSection()
      }
    }
  }
  
  @IBAction func openLoginItemsPanel(_ sender: AnyObject) {
    guard let url = URL(string: AppModel.openSettingsLoginItemsURL) else {
      return
    }
    NSWorkspace.shared.open(url)
  }
  
  // MARK: -
  
  private func setupChoiceControl() {
    guard let optionSelector = optionSelector else {
      return
    }
    OptionSelection.allCases.forEach {
      optionSelector.setSelected(false, forSegment: $0.rawValue)
    }
    // unnecessary really, both conditions expected to be false coming in, otherwise would have skipped this page
    if isLaunchAtLoginConfigured {
      optionSelector.setSelected(true, forSegment: OptionSelection.set.rawValue)
      showLaunchAtLoginChosenLabel()
    } else if UserDefaults.standard.loginItemAskDelayCount > 0 {
      optionSelector.setSelected(true, forSegment: OptionSelection.remind.rawValue)
      showRemindChosenLabel()
    }
  }
  
  private func setupVisibleManualConfigurationLabel() {
    needsManualConfigurationLabel?.isHidden = canConfigProgrammatically
  }
  
  private func hideChoiceDescriptionLabels() {
    choiceDescriptionSection?.isHidden = true
    launchAtLoginChosenLabel?.isHidden = true
    manuallyConfigureChosenLabel?.isHidden = true
    remindChosenLabel?.isHidden = true
    notConfiguredChosenLabel?.isHidden = true
    fallbackSection?.isHidden = true
  }
  
  private func showFallbackSection() {
    if newOSWithSystemSettingsApp {
      showSystemSettingsFallback()
    } else {
      showSystemPreferencesFallback()
    }
  }
  
  private func showLaunchAtLoginChosenLabel() {
    choiceDescriptionSection?.isHidden = false
    launchAtLoginChosenLabel?.isHidden = false
  }
  
  private func showManuallyConfigureChosenLabel() {
    choiceDescriptionSection?.isHidden = false
    manuallyConfigureChosenLabel?.isHidden = false
  }
  
  private func showRemindChosenLabel() {
    choiceDescriptionSection?.isHidden = false
    remindChosenLabel?.isHidden = false
  }
  
  private func showNotConfiguredChosenLabel() {
    choiceDescriptionSection?.isHidden = false
    notConfiguredChosenLabel?.isHidden = false
  }
  
  private func showSystemSettingsFallback() {
    choiceDescriptionSection?.isHidden = false
    fallbackSection?.isHidden = false
    systemSettingsFallbackLabel?.isHidden = false
    systemPreferencesFallbackLabel?.isHidden = true
  }
  
  private func showSystemPreferencesFallback() {
    choiceDescriptionSection?.isHidden = false
    fallbackSection?.isHidden = false
    systemSettingsFallbackLabel?.isHidden = true
    systemPreferencesFallbackLabel?.isHidden = false
  }
  
  // MARK: -
  
  private var canConfigProgrammatically: Bool {
    guard #available(macOS 13.0, *) else { return false }
    return true
  }
  
  private var isLaunchAtLoginConfigured: Bool {
    guard #available(macOS 13.0, *) else { return false }
    return SMAppService.mainApp.status == .enabled
  }
  
  private var newOSWithSystemSettingsApp: Bool {
    guard #available(macOS 13.0, *) else { return false } // a coincidence that its the same OS that introduces SMAppService?
    return true
  }
  
  private func setLaunchAtLogin() -> Bool {
    guard #available(macOS 13.0, *) else {
      return false
    }
    do {
      if SMAppService.mainApp.status == .enabled {
        try? SMAppService.mainApp.unregister()
      }
      try SMAppService.mainApp.register()
      
      UserDefaults.standard.loginItemAskDelayCount = 0
      UserDefaults.standard.loginItemChoicePending = false
      return true
    } catch {
      return false
    }
  }
  
  private func openLoginItemsPanel() -> Bool {
    if #available(macOS 13.0, *) {
      if SMAppService.mainApp.status == .enabled {
        try? SMAppService.mainApp.unregister()
      }
    }
    guard let url = URL(string: AppModel.openSettingsLoginItemsURL) else {
      return false
    }
    NSWorkspace.shared.open(url)
    
    UserDefaults.standard.loginItemAskDelayCount = 0
    UserDefaults.standard.loginItemChoicePending = false
    return true
  }
  
  private func dontLaunchAtLogin() -> Bool {
    if #available(macOS 13.0, *) {
      if SMAppService.mainApp.status == .enabled {
        do {
          try SMAppService.mainApp.unregister()
        } catch {
          return false
        }
      }
    }
    UserDefaults.standard.loginItemAskDelayCount = 0
    UserDefaults.standard.loginItemChoicePending = false
    return true
  }
  
  private func setAskLater() -> Bool {
    if #available(macOS 13.0, *) {
      if SMAppService.mainApp.status == .enabled {
        do {
          try SMAppService.mainApp.unregister()
        } catch {
          return false
        }
      }
    }
    UserDefaults.standard.loginItemAskDelayCount = Self.reminderCountdown
    UserDefaults.standard.loginItemChoicePending = false
    return true
  }
}
