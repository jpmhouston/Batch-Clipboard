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
  enum BuiltInPasteSeparator: Int, CaseIterable {
    case newline, space, commaSpace
    // complications because this enum doesn't include none, that's within the enum below
    var menuIndex: Int { rawValue + 1 }
    init?(withMenuItem i: Int) { if i == 0 { return nil } ; self.init(rawValue: i - 1) }
    static var noneMenuIndex: Int { 0 }
    static var numMenuItems: Int { BuiltInPasteSeparator.allCases.count + 1 }
  }
  enum SeparatorChoice {
    case none, builtIn(BuiltInPasteSeparator), addOn(String)
    var string: String? {
      switch self {
      case .addOn(let s): s
      case .builtIn(.newline): "\n"  
      case .builtIn(.space): " "
      case .builtIn(.commaSpace): ", "
      default: nil
      }
    }
  }
  
  private var addOnPasteMultipleSeparators: [String: String] = [:]
  
  private var hotKeyDefinition: KeyboardShortcuts.Name?
  private var hotKeyShortcut: KeyboardShortcuts.Shortcut? 
  private var hotKeyField: KeyboardShortcuts.RecorderCocoa?
  private var saveBatchConfirmButton: NSButton?
  private var prohibitedBatchNames: Set<String> = []
  
  override init() {
    super.init()
    
    guard Bundle.main.loadNibNamed("Alerts", owner: self, topLevelObjects: nil) else {
      fatalError("alerts resources missing")
    }
    
    if let dict = UserDefaults.standard.dictionary(forKey: "pasteSseparators") as? [String: String],
       let popup = pasteWithSeparatorPopup
    {
      // pre-flight the dict, throw out empty strings and duplicates
      for (title, str) in dict {
        guard !title.isEmpty && !str.isEmpty else {
          continue
        }
        guard addOnPasteMultipleSeparators[title] == nil else {
          os_log(.info, "add-on paste separator cannot be added because of duplicate title: %@", title)
          continue
        }
        guard popup.indexOfItem(withTitle: title) == -1 else {
          os_log(.info, "add-on paste separator cannot be added because of duplicate title: %@", title)
          continue
        }
        addOnPasteMultipleSeparators[title] = str
      }
    }
    // add the titles to the menu as well as to our dictionary 
    for (title, _) in addOnPasteMultipleSeparators {
      pasteWithSeparatorPopup?.addItem(withTitle: title)
    }
  }
  
  // MARK: -
  
  private var bonusFeaturePromotionAlert: NSAlert {
    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = NSLocalizedString("promoteextras_alert_message", comment: "")
    alert.informativeText = NSLocalizedString("promoteextras_alert_comment", comment: "")
    alert.addButton(withTitle: NSLocalizedString("promoteextras_alert_show_settings", comment: ""))
    alert.addButton(withTitle: NSLocalizedString("promoteextras_alert_cancel", comment: ""))
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
  
  private func saveBatchAlert(withCount count: Int, forCurrentBatch isCurrentBatch: Bool) -> NSAlert {
    let alert = NSAlert()
    alert.messageText = NSLocalizedString(isCurrentBatch ? "save_current_batch_alert_message" : "save_last_batch_alert_message", comment: "")
    alert.informativeText = NSLocalizedString("save_batch_alert_comment", comment: "")
      .replacingOccurrences(of: "{count}", with: "\(count)")
    saveBatchConfirmButton = alert.addButton(withTitle: NSLocalizedString("save_batch_alert_confirm", comment: ""))
    alert.addButton(withTitle: NSLocalizedString("save_batch_alert_cancel", comment: ""))
    
    saveBatchConfirmButton?.isEnabled = false
    return alert
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
    
    switch separatorDefault {
    case .builtIn(let separator):
      pasteWithSeparatorPopup?.selectItem(at: separator.menuIndex)
    case .addOn(let separatorName):
      // rely on pre-fligting to know matching menu item isn't a built-in, or None 
      guard let menuIndex = pasteWithSeparatorPopup?.indexOfItem(withTitle: separatorName),
            menuIndex >= 0 && addOnPasteMultipleSeparators[separatorName] != nil else {
        pasteWithSeparatorPopup?.selectItem(at: BuiltInPasteSeparator.noneMenuIndex)
        break
      }
      pasteWithSeparatorPopup?.selectItem(at: menuIndex)
    default:
      pasteWithSeparatorPopup?.selectItem(at: BuiltInPasteSeparator.noneMenuIndex)
    }
    alert.window.initialFirstResponder = pasteMultipleField
    
    DispatchQueue.main.async {
      switch alert.runModal() {
      case NSApplication.ModalResponse.alertFirstButtonReturn:
        alert.window.orderOut(nil) // i think others above should call this too
        
        let number: Int
        if let s = self.pasteMultipleField?.stringValue, let entry = Int(s) {
          number = entry
        } else { 
          number = maxValue
        } 
        
        var separator = SeparatorChoice.none
        if let menuIndex = self.pasteWithSeparatorPopup?.indexOfSelectedItem, menuIndex != BuiltInPasteSeparator.noneMenuIndex {
          if menuIndex >= BuiltInPasteSeparator.numMenuItems {
            if let title = self.pasteWithSeparatorPopup?.titleOfSelectedItem, let s = self.addOnPasteMultipleSeparators[title] {
              separator = .addOn(s)
            }
          } else if let b = BuiltInPasteSeparator(withMenuItem: menuIndex) {
            separator = .builtIn(b)
          }
        }
        
        closure(number, separator)
        
      default:
        closure(nil, .none)
      }
    }
  }
  
  func withSaveBatchAlert(forCurrentBatch isCurrentBatch: Bool, showingCount count: Int, excludingNames exclude: Set<String>,
                          _ closure: @escaping (String?, KeyboardShortcuts.Name?) -> Void) {
    let alert = saveBatchAlert(withCount: count, forCurrentBatch: isCurrentBatch)
    
    alert.accessoryView = saveBatchAccessoryView
    batchNameField?.placeholderString = NSLocalizedString("save_batch_name_placeholder", comment: "")
    batchNameField?.stringValue = ""
    batchHotkeyCheckbox?.state = .off
    batchHotkeyCheckbox?.isEnabled = false
    prohibitedBatchNames = exclude
    
    batchNameField?.delegate = self
    batchHotkeyCheckbox?.target = self
    batchHotkeyCheckbox?.action = #selector(batchHotkeyCheckboxChanged(_:))
    
    alert.window.initialFirstResponder = batchNameField
    
    DispatchQueue.main.async {
      switch alert.runModal() {
      case NSApplication.ModalResponse.alertFirstButtonReturn:
        if let name = self.batchNameField?.stringValue, !name.isEmpty {
          closure(name, self.hotKeyDefinition)
        } else {
          closure(nil, nil)
        }
      default:
        self.clearHotKey()
        closure(nil, nil)
      }
      
      self.hotKeyField?.removeFromSuperview()
      self.hotKeyField = nil
      self.hotKeyDefinition = nil
      self.hotKeyShortcut = nil
    }
  }
  
  private func createHotKeyAndField(forName name: String) {
    // the field needs a hotkey for it to assign, set that up with the given name first
    guard let superview = batchHotkeyContainerView else { return }
    let hotKey = KeyboardShortcuts.Name(name)
    if let shortcut = hotKeyShortcut {
      KeyboardShortcuts.setShortcut(shortcut, for: hotKey)
    }
    let field = KeyboardShortcuts.RecorderCocoa(for: hotKey) { [weak self] in
      self?.hotKeyShortcut = $0 // closure called when field changed
    }
    superview.translatesAutoresizingMaskIntoConstraints = false
    field.translatesAutoresizingMaskIntoConstraints = false
    superview.addSubview(field)
    superview.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|[f]|", metrics: nil, views: ["f": field]))
    superview.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[f]|", metrics: nil, views: ["f": field]))
    hotKeyDefinition = hotKey
    hotKeyField = field
  }
  
  private func removeHotKeyAndField() {
    hotKeyField?.removeFromSuperview()
    hotKeyField = nil
    clearHotKey()
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
    guard let field = batchNameField else { return }
    removeHotKeyAndField()
    if let fieldValue = batchNameField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), !fieldValue.isEmpty {
      let allowed = !nameProhibited(fieldValue)
      batchHotkeyCheckbox?.isEnabled = allowed
      saveBatchConfirmButton?.isEnabled = allowed
      if allowed && batchHotkeyCheckbox?.state == .on {
        createHotKeyAndField(forName: field.stringValue)
      }
    } else {
      batchHotkeyCheckbox?.isEnabled = false
      saveBatchConfirmButton?.isEnabled = false
    }
  }
  
  @objc func batchHotkeyCheckboxChanged(_ sender: AnyObject) {
    if batchHotkeyCheckbox?.state == .off {
      removeHotKeyAndField()
      // hotKeyShortcut = nil -- to get a blank field when unchecking and rechecking
      batchNameField?.becomeFirstResponder()
    } else if let fieldValue = batchNameField?.stringValue, !fieldValue.isEmpty {
      createHotKeyAndField(forName: fieldValue)
      _ = hotKeyField?.becomeFirstResponder()
    }
  }
  
}
