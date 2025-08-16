//
//  Alerts.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2025-07-29.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//
//  In part based on Maccy.swift from the Maccy project
//  Portions Copyright © 2024 Alexey Rodionov. All rights reserved.
//

import AppKit
import KeyboardShortcuts
import os.log

class Alerts: NSObject, NSTextFieldDelegate {
  
  @IBOutlet var pasteMultipleAccessoryView: NSView?
  @IBOutlet weak var pasteMultipleField: RangedIntegerTextField?
  @IBOutlet weak var pasteWithSeparatorPopup: NSPopUpButton? // assume items in sync with PasteMultipleSeparator
  
  @IBOutlet var saveBatchAccessoryView: NSView?
  @IBOutlet weak var batchNameField: NSTextField?
  @IBOutlet weak var batchHotkeyCheckbox: NSButton?
  @IBOutlet weak var batchHotkeyContainerView: NSView?
  
  enum PermissionResponse { case cancel, openSettings, openIntro }
  enum SeparatorChoice {
    case none, builtIn(AppModel.PasteSeparator), addOn(String)
    static var numMenuItems: Int { 1 + AppModel.PasteSeparator.allCases.count + addOnPasteMultipleSeparators.count }
    static var numBuiltInMenuItems: Int { 1 + AppModel.PasteSeparator.allCases.count }
    static var noneMenuIndex = 0
    var menuIndex: Int? {
      switch self {
      case .none: 0
      case .builtIn(let b): 1 + b.rawValue
      case .addOn(_): nil
      }
    }
    init?(withMenuIndex i: Int) {
      switch i {
      case 0: self = .none
      case 1 ..< Self.numBuiltInMenuItems where AppModel.PasteSeparator.validRawValue.contains(i - 1):
        let separator = AppModel.PasteSeparator(rawValue: i - 1)!
        self = .builtIn(separator)
      default: return nil
      }
    }
    init?(withMenuTitle t: String) {
      if let s = addOnPasteMultipleSeparators[t] {
        self = .addOn(s)
      } else {
        return nil
      }
    }
  }
  
  private static var addOnPasteMultipleSeparators: [String: String] = [:]
  
  private var hotKeyDefinition: KeyboardShortcuts.Name?
  private var hotKeyShortcut: KeyboardShortcuts.Shortcut? 
  private var hotKeyField: KeyboardShortcuts.RecorderCocoa?
  private var saveBatchConfirmButton: NSButton?
  private var saveBatchOriginalName: String?
  private var prohibitedBatchNames: Set<String> = []
  
  override init() {
    super.init()
    
    guard Bundle.main.loadNibNamed("Alerts", owner: self, topLevelObjects: nil) else {
      fatalError("alerts resources missing")
    }
    
    if let dict = UserDefaults.standard.dictionary(forKey: "pasteSeparators") as? [String: String],
       let popup = pasteWithSeparatorPopup
    {
      // pre-flight the dict, throw out empty strings and duplicates
      for (title, str) in dict {
        guard !title.isEmpty && !str.isEmpty else {
          continue
        }
        guard Self.addOnPasteMultipleSeparators[title] == nil else {
          os_log(.info, "add-on paste separator cannot be added because of duplicate title: %@", title)
          continue
        }
        guard popup.indexOfItem(withTitle: title) == -1 else {
          os_log(.info, "add-on paste separator cannot be added because of duplicate title: %@", title)
          continue
        }
        Self.addOnPasteMultipleSeparators[title] = str
      }
    }
    // add the titles to the menu as well as to our dictionary 
    for (title, _) in Self.addOnPasteMultipleSeparators {
      pasteWithSeparatorPopup?.addItem(withTitle: title)
    }
  }
  
  // MARK: -
  
  private var bonusFeaturePromotionAlert: NSAlert {
    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = NSLocalizedString("promote_extrasalert_message", comment: "")
    alert.informativeText = NSLocalizedString("promote_extrasalert_comment", comment: "")
    alert.addButton(withTitle: NSLocalizedString("promote_extrasalert_show_settings", comment: ""))
    alert.addButton(withTitle: NSLocalizedString("promote_extrasalert_cancel", comment: ""))
    return alert
  }
  
  private func numberQueuedAlert(withQueueSize size: Int) -> NSAlert {
    let alert = NSAlert()
    alert.messageText = NSLocalizedString("number_alert_message", comment: "")
    alert.informativeText = NSLocalizedString("number_alert_comment", comment: "")
      .replacingOccurrences(of: "{number}", with: String(size))
    alert.addButton(withTitle: NSLocalizedString("number_alert_confirm", comment: ""))
    alert.addButton(withTitle: NSLocalizedString("number_alert_cancel", comment: ""))
    return alert
  }
  
  private var clearAlert: NSAlert {
    let alert = NSAlert()
    alert.messageText = NSLocalizedString("clear_alert_message", comment: "")
    alert.informativeText = NSLocalizedString("clear_alert_comment", comment: "")
    alert.addButton(withTitle: NSLocalizedString("clear_alert_confirm", comment: ""))
    alert.addButton(withTitle: NSLocalizedString("clear_alert_cancel", comment: ""))
    alert.showsSuppressionButton = true
    return alert
  }
  
  private var clearWhenDisablingHistoryAlert: NSAlert {
    let alert = NSAlert()
    alert.messageText = NSLocalizedString("erase_history_alert_message", comment: "")
    alert.informativeText = NSLocalizedString("erase_history_alert_comment", comment: "")
    alert.addButton(withTitle: NSLocalizedString("erase_history_alert_confirm", comment: ""))
    alert.addButton(withTitle: NSLocalizedString("erase_history_alert_deny", comment: ""))
    alert.addButton(withTitle: NSLocalizedString("erase_history_alert_cancel", comment: ""))
    alert.showsSuppressionButton = true
    return alert
  }
  
  private var permissionNeededAlert: NSAlert {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = NSLocalizedString("accessibility_alert_message", comment: "")
    alert.addButton(withTitle: NSLocalizedString("accessibility_alert_deny", comment: ""))
    alert.addButton(withTitle: NSLocalizedString("accessibility_alert_open", comment: ""))
    alert.addButton(withTitle: NSLocalizedString("accessibility_alert_show_intro", comment: ""))
    alert.icon = NSImage(named: "NSSecurity")
    var locationName = NSLocalizedString("system_settings_name", comment: "")
    var paneName = NSLocalizedString("system_settings_pane", comment: "")
    if #unavailable(macOS 13) {
      locationName = NSLocalizedString("system_preferences_name", comment: "")
      paneName = NSLocalizedString("system_preferences_pane", comment: "")
    }
    alert.informativeText = NSLocalizedString("accessibility_alert_comment", comment: "")
      .replacingOccurrences(of: "{settings}", with: locationName)
      .replacingOccurrences(of: "{pane}", with: paneName)
    return alert
  }
  
  private func deleteBatchConfirmationAlert(withTitle title: String) -> NSAlert {
    let alert = NSAlert()
    alert.messageText = NSLocalizedString("delete_batch_message", comment: "")
    if title.isEmpty {
      alert.informativeText = NSLocalizedString("delete_batch_alt_comment", comment: "")
    } else {
      alert.informativeText = NSLocalizedString("delete_batch_comment", comment: "")
        .replacingOccurrences(of: "{title}", with: title)
    }
    alert.addButton(withTitle: NSLocalizedString("delete_batch_confirm", comment: ""))
    alert.addButton(withTitle: NSLocalizedString("delete_batch_cancel", comment: ""))
    alert.showsSuppressionButton = true
    return alert
  }
  
  private func saveBatchAlert(withCount count: Int, forCurrentBatch isCurrentBatch: Bool) -> (NSAlert, NSButton) {
    let alert = NSAlert()
    alert.messageText = NSLocalizedString(isCurrentBatch ? "save_current_batch_alert_message" : "save_last_batch_alert_message", comment: "")
    alert.informativeText = NSLocalizedString("save_batch_alert_comment", comment: "")
      .replacingOccurrences(of: "{count}", with: "\(count)")
    let button = alert.addButton(withTitle: NSLocalizedString("save_batch_alert_confirm", comment: ""))
    alert.addButton(withTitle: NSLocalizedString("save_batch_alert_cancel", comment: ""))
    return (alert, button)
  }
  
  private func renameBatchAlert() -> (NSAlert, NSButton) {
    let alert = NSAlert()
    alert.messageText = NSLocalizedString("rename_batch_alert_message", comment: "")
    alert.informativeText = NSLocalizedString("rename_batch_alert_comment", comment: "")
    let button = alert.addButton(withTitle: NSLocalizedString("rename_batch_alert_confirm", comment: ""))
    alert.addButton(withTitle: NSLocalizedString("rename_batch_alert_cancel", comment: ""))
    return (alert, button)
  }
  
  // MARK: -
  
  func withBonusFeaturePromotionAlert(_ closure: @escaping (Bool) -> Void) {
    let alert = bonusFeaturePromotionAlert
    DispatchQueue.main.async {
      if alert.runModal() == NSApplication.ModalResponse.alertFirstButtonReturn {
        closure(true)
      } else {
        closure(false)
      }
    }
  }
  
  func withDisableHistoryConfirmationAlert(_ closure: @escaping (Bool, Bool, Bool) -> Void) {
    let alert = clearWhenDisablingHistoryAlert
    DispatchQueue.main.async {
      switch alert.runModal() {
      case NSApplication.ModalResponse.alertFirstButtonReturn:
        closure(true, false, alert.suppressionButton?.state == .on)
      case NSApplication.ModalResponse.alertSecondButtonReturn:
        closure(true, true, alert.suppressionButton?.state == .on)
      default:
        closure(false, false, false)
      }
    }
  }
  
  func withClearAlert(_ closure: @escaping (Bool, Bool) -> Void) {
    let alert = clearAlert
    DispatchQueue.main.async {
      if alert.runModal() == NSApplication.ModalResponse.alertFirstButtonReturn {
        closure(true, alert.suppressionButton?.state == .on)
      } else {
        closure(false, false)
      }
    }
  }
  
  func withPermissionAlert(_ closure: @escaping (PermissionResponse) -> Void) {
    let alert = permissionNeededAlert
    DispatchQueue.main.async {
      switch alert.runModal() {
      case NSApplication.ModalResponse.alertSecondButtonReturn:
        closure(.openSettings)
      case NSApplication.ModalResponse.alertThirdButtonReturn:
        closure(.openIntro)
      default:
        closure(.cancel)
      }
    }
  }
  
  func withNumberToPasteAlert(maxValue: Int, separatorDefault: SeparatorChoice?,
                              _ closure: @escaping (Int?, SeparatorChoice) -> Void) {
    let alert = numberQueuedAlert(withQueueSize: maxValue)
    
    alert.accessoryView = pasteMultipleAccessoryView
    pasteMultipleField?.configure(acceptingRange: 1 ..< maxValue, permittingEmpty: true)
    pasteMultipleField?.placeholderString = String(maxValue)
    
    if let menuIndex = separatorDefault?.menuIndex {
      pasteWithSeparatorPopup?.selectItem(at: menuIndex)
    } else if case .addOn(let separatorName) = separatorDefault,
              let menuIndex = pasteWithSeparatorPopup?.indexOfItem(withTitle: separatorName),
              menuIndex >= 0 && Self.addOnPasteMultipleSeparators[separatorName] != nil {
      pasteWithSeparatorPopup?.selectItem(at: menuIndex)
    } else {
      pasteWithSeparatorPopup?.selectItem(at: SeparatorChoice.noneMenuIndex)
    }
    alert.window.initialFirstResponder = pasteMultipleField
    
    DispatchQueue.main.async {
      switch alert.runModal() {
      case NSApplication.ModalResponse.alertFirstButtonReturn:
        alert.window.orderOut(nil) // i think others above should call this too
        
        let number: Int =
          if let s = self.pasteMultipleField?.stringValue, let entry = Int(s) {
            entry
          } else { 
            maxValue
          } 
        let separator: SeparatorChoice =
          if let i = self.pasteWithSeparatorPopup?.indexOfSelectedItem, let indexMatch = SeparatorChoice(withMenuIndex: i) {
            indexMatch
          } else if let t = self.pasteWithSeparatorPopup?.titleOfSelectedItem, let titleMatch = SeparatorChoice(withMenuTitle: t) {
            titleMatch
          } else {
            .none
          }
        closure(number, separator)
        
      default:
        closure(nil, .none)
      }
    }
  }
  
  func withDeleteBatchAlert(withTitle title: String, _ closure: @escaping (Bool, Bool) -> Void) {
    let alert = deleteBatchConfirmationAlert(withTitle: title)
    DispatchQueue.main.async {
      if alert.runModal() == NSApplication.ModalResponse.alertFirstButtonReturn {
        closure(true, alert.suppressionButton?.state == .on)
      } else {
        closure(false, false)
      }
    }
  }
  
  func withSaveBatchAlert(forCurrentBatch isCurrentBatch: Bool, showingCount count: Int, excludingNames exclude: Set<String>,
                          _ closure: @escaping (String?, KeyboardShortcuts.Shortcut?) -> Void) {
    let (alert, button) = saveBatchAlert(withCount: count, forCurrentBatch: isCurrentBatch)
    button.isEnabled = false
    saveBatchConfirmButton = button
    batchNameField?.delegate = self
    batchHotkeyCheckbox?.target = self
    batchHotkeyCheckbox?.action = #selector(batchHotkeyCheckboxChanged(_:))
    alert.window.initialFirstResponder = batchNameField
    
    alert.accessoryView = saveBatchAccessoryView
    batchNameField?.placeholderString = NSLocalizedString("save_batch_name_placeholder", comment: "")
    batchNameField?.stringValue = ""
    batchHotkeyCheckbox?.state = .off
    batchHotkeyCheckbox?.isEnabled = false
    prohibitedBatchNames = exclude
    saveBatchOriginalName = nil
    
    DispatchQueue.main.async {
      switch alert.runModal() {
      case NSApplication.ModalResponse.alertFirstButtonReturn:
        guard let name = self.batchNameField?.stringValue, !name.isEmpty else {
          fallthrough
        }
        closure(name, self.hotKeyShortcut)
      default:
        self.clearHotKey()
        closure(nil, nil)
      }
      
      self.hotKeyField?.removeFromSuperview()
      self.hotKeyField = nil
      self.hotKeyDefinition = nil
      self.hotKeyShortcut = nil
      self.saveBatchConfirmButton = nil
    }
  }
  
  func withRenameBatchAlert(withCurrentName currentName: String, excludingNames exclude: Set<String>,
                            _ closure: @escaping (String?, KeyboardShortcuts.Shortcut?) -> Void) {
    let (alert, button) = renameBatchAlert()
    button.isEnabled = false
    saveBatchConfirmButton = button
    batchNameField?.delegate = self
    batchHotkeyCheckbox?.target = self
    batchHotkeyCheckbox?.action = #selector(batchHotkeyCheckboxChanged(_:))
    alert.window.initialFirstResponder = batchNameField
    
    alert.accessoryView = saveBatchAccessoryView
    batchNameField?.placeholderString = !currentName.isEmpty ? currentName : NSLocalizedString("save_batch_name_placeholder", comment: "") 
    batchNameField?.stringValue = ""
    prohibitedBatchNames = exclude
    saveBatchOriginalName = currentName
    
    hotKeyDefinition = currentName.isEmpty ? nil : KeyboardShortcuts.Name(currentName)
    batchHotkeyCheckbox?.isEnabled = true
    if let hotKey = hotKeyDefinition, let shortcut = KeyboardShortcuts.getShortcut(for: hotKey) {
      hotKeyShortcut = shortcut
      batchHotkeyCheckbox?.state = .on
      createHotKeyField()
    } else {
      hotKeyShortcut = nil
      batchHotkeyCheckbox?.state = .off
    }
    
    DispatchQueue.main.async {
      switch alert.runModal() {
      case NSApplication.ModalResponse.alertFirstButtonReturn:
        if let name = self.batchNameField?.stringValue, !name.isEmpty {
          closure(name, self.hotKeyShortcut)
        } else {
          closure(nil, self.hotKeyShortcut)
        }
      default:
        self.clearHotKey()
        closure(nil, nil)
      }
      
      self.hotKeyField?.removeFromSuperview()
      self.hotKeyField = nil
      self.hotKeyDefinition = nil
      self.hotKeyShortcut = nil
      self.saveBatchConfirmButton = nil
    }
  }
  
  private func createHotKey(forName name: String) {
    let hotKey = KeyboardShortcuts.Name(name)
    hotKeyDefinition = hotKey
    if let shortcut = hotKeyShortcut {
      KeyboardShortcuts.setShortcut(shortcut, for: hotKey)
    }
  }
  
  private func createHotKeyField() {
    guard let superview = batchHotkeyContainerView, let hotKey = hotKeyDefinition else { return }
    hotKeyField?.removeFromSuperview()
    let field = KeyboardShortcuts.RecorderCocoa(for: hotKey) { [weak self] in
      self?.hotKeyShortcut = $0 // this closure called when the key field changed
    }
    superview.translatesAutoresizingMaskIntoConstraints = false
    field.translatesAutoresizingMaskIntoConstraints = false
    superview.addSubview(field)
    superview.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|[f]|", metrics: nil, views: ["f": field]))
    superview.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[f]|", metrics: nil, views: ["f": field]))
    hotKeyField = field
    
    field.window?.recalculateKeyViewLoop() // doesn't seem to work on macOS 15.5
  }
  
  private func removeHotKeyField() {
    hotKeyField?.removeFromSuperview()
    hotKeyField = nil
    
    batchNameField?.window?.recalculateKeyViewLoop() // doesn't seem to work on macOS 15.5
  }
  
  private func clearHotKey() {
    if let hotKey = hotKeyDefinition {
      KeyboardShortcuts.setShortcut(nil, for: hotKey)
    }
    hotKeyDefinition = nil
  }
  
  private func nameProhibited(_ name: String) -> Bool {
    return prohibitedBatchNames.contains {
      name.caseInsensitiveCompare($0) == .orderedSame 
    }
  }
  
  func controlTextDidChange(_ notification: Notification) {
    updateHotKeyControls()
  }
  
  func updateHotKeyControls() {
    guard let fieldContents = batchNameField?.stringValue else { return }
    let fieldValue = fieldContents.trimmingCharacters(in: .whitespacesAndNewlines)
    
    let validName: String? = if let originalName = saveBatchOriginalName, fieldValue.isEmpty || fieldValue == originalName {
      originalName
    } else if !fieldValue.isEmpty && !nameProhibited(fieldValue) {
      fieldValue
    } else {
      nil
    }
    
    if let name = validName {
      saveBatchConfirmButton?.isEnabled = true
      batchHotkeyCheckbox?.isEnabled = true
      
      if let hotKey = hotKeyDefinition, hotKey.rawValue == name {
        // don't need to regenerate the hotkey
        // short-circuit updaing the key field if we want it showing and it's already there
        if batchHotkeyCheckbox?.state == .on && hotKeyField != nil {
          return
        }
      } else {
        clearHotKey()
        createHotKey(forName: name)
      }
      if batchHotkeyCheckbox?.state == .on {
        createHotKeyField()
      } else {
        removeHotKeyField()
      }
      
    } else {
      // name is invalid
      batchHotkeyCheckbox?.isEnabled = false
      saveBatchConfirmButton?.isEnabled = false
      removeHotKeyField()
    }
  }
  
  @objc func batchHotkeyCheckboxChanged(_ sender: AnyObject) {
    if batchHotkeyCheckbox?.state == .on {
      updateHotKeyControls()
      _ = hotKeyField?.becomeFirstResponder()
    } else {
      removeHotKeyField()
      batchNameField?.becomeFirstResponder()
    }
  }
  
}
