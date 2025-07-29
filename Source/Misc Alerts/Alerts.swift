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
import os.log

class Alerts: NSObject {
  
  @IBOutlet var pasteMultipleAccessoryView: NSView?
  @IBOutlet weak var pasteMultipleField: RangedIntegerTextField?
  @IBOutlet weak var pasteWithSeparatorPopup: NSPopUpButton? // assume items in sync with PasteMultipleSeparator
  
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
  
  var bonusFeaturePromotionAlert: NSAlert {
    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = NSLocalizedString("promoteextras_alert_message", comment: "")
    alert.informativeText = NSLocalizedString("promoteextras_alert_comment", comment: "")
    alert.addButton(withTitle: NSLocalizedString("promoteextras_alert_show_settings", comment: ""))
    alert.addButton(withTitle: NSLocalizedString("promoteextras_alert_cancel", comment: ""))
    return alert
  }
  
  func numberQueuedAlert(withQueueSize size: Int) -> NSAlert {
    let alert = NSAlert()
    alert.messageText = NSLocalizedString("number_alert_message", comment: "")
    alert.informativeText = NSLocalizedString("number_alert_comment", comment: "")
      .replacingOccurrences(of: "{number}", with: String(size))
    alert.addButton(withTitle: NSLocalizedString("number_alert_confirm", comment: ""))
    alert.addButton(withTitle: NSLocalizedString("number_alert_cancel", comment: ""))
    return alert
  }
  
  internal var clearAlert: NSAlert {
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
  
  internal var permissionNeededAlert: NSAlert {
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
  
  func withNumberToPasteAlert(maxValue: Int, separatorDefault: SeparatorChoice?, _ closure: @escaping (Int?, SeparatorChoice) -> Void) {
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
  
}
