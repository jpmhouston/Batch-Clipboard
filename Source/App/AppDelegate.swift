//
//  AppDelegate.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-07-10.
//  Portions Copyright © 2025 Bananameter Labs. All rights reserved.
//
//  Based on AppDelegate.swift from the Maccy project
//  Portions Copyright © 2024 Alexey Rodionov. All rights reserved.
//

import Cocoa
import Intents
import KeyboardShortcuts
import Sauce
#if SPARKLE_UPDATES
import Sparkle
#endif
import os.log

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
  @IBOutlet weak var copyMenuItem: NSMenuItem!
  @IBOutlet weak var pasteMenuItem: NSMenuItem!
  @IBOutlet weak var cutMenuItem: NSMenuItem!
  
  var model: AppModel!
  
  func applicationDidFinishLaunching(_ aNotification: Notification) {
    if ProcessInfo.processInfo.arguments.contains("ui-testing") {
      if CoreDataManager.deleteDatabase() {
        model = AppModel()
      } else {
        NSApplication.shared.terminate(nil)
      }
      
    } else if NSEvent.modifierFlags.contains(.option) {
      showResetAlert() { [weak self] in
        self?.model = AppModel()
      }
      
    } else {
      model = AppModel()
    }
  }
  
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    model.wasReopened()
    return false // best to return false instead of true to tell NSApp to do nothing
  }
  
  func application(_ application: NSApplication, open urls: [URL]) {
    // get the first of the url's, ignore the rest
    guard let url = urls.first else {
      return
    }
    if url.absoluteString == AppModel.showIntroInAppURL {
      model.showIntro(self)
    }
    if url.absoluteString == AppModel.showLicensesInAppURL {
      model.showLicenses()
    }
  }
  
  func applicationWillTerminate(_ notification: Notification) {
    model.terminate()
    CoreDataManager.shared.saveContext()
  }
  
  @available(macOS 11.0, *)
  func application(_ application: NSApplication, handlerFor intent: INIntent) -> Any? {
    os_log(.default, "intent %@", String(describing: type(of: intent)))
    return switch intent {
    case is StartCopyingIntent:           StartCopyingIntentHandler(model)
    case is StartPastingIntent:           StartPastingIntentHandler(model)
    case is CancelIntent:                 CancelIntentHandler(model)
    case is BatchCopyIntent:              BatchCopyIntentHandler(model)
    case is BatchPasteIntent:             BatchPasteIntentHandler(model)
    case is AdvanceIntent:                AdvanceIntentHandler(model)
    case is ClearIntent:                  ClearIntentHandler(model)
    case is RepeatBatchIntent:            RepeatBatchIntentHandler(model)
    case is SelectNamedBatchIntent:       SelectNamedBatchIntentHandler(model)
    case is PasteSequentiallyIntent:      PasteSequentiallyIntentHandler(model)
    
    #if ALL_INTENTS
    case is HistoryItemCountIntent:       HistoryItemCountIntentHandler(model)
    case is GetHistoryItemIntent:         GetHistoryItemIntentHandler(model)
    case is SelectHistoryItemIntent:      SelectHistoryItemIntentHandler(model)
    case is StartFromHistoryItemIntent:   StartFromHistoryItemIntentHandler(model)
    case is DeleteHistoryItemIntent:      DeleteHistoryItemIntentHandler(model)
    
    case is BatchItemCountIntent:         BatchItemCountIntentHandler(model)
    case is GetBatchItemIntent:           GetBatchItemIntentHandler(model)
    case is SelectBatchItemIntent:        SelectBatchItemIntentHandler(model)
    case is DeleteBatchItemIntent:        DeleteBatchItemIntentHandler(model)
    
    case is SavedBatchCountIntent:        SavedBatchCountIntentHandler(model)
    case is SavedBatchTitleIntent:        SavedBatchTitleIntentHandler(model)
    case is SelectSavedBatchIntent:       SelectSavedBatchIntentHandler(model)
    case is FindNamedBatchIntent:         FindNamedBatchIntentHandler(model)
    case is DeleteSavedBatchIntent:       DeleteSavedBatchIntentHandler(model)
    
    case is SavedBatchItemCountIntent:    SavedBatchItemCountIntentHandler(model)
    case is GetSavedBatchItemIntent:      GetSavedBatchItemIntentHandler(model)
    case is SelectSavedBatchItemIntent:   SelectSavedBatchItemIntentHandler(model)
    case is DeleteSavedBatchItemIntent:   DeleteSavedBatchItemIntentHandler(model)
    #endif
    default: nil
    }
  }
  
  func showResetAlert(_ continuation: () -> Void) {
    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = NSLocalizedString("resetdata_alert_message", comment: "")
    alert.informativeText = NSLocalizedString("resetdata_alert_comment", comment: "")
    let deleteButton = alert.addButton(withTitle: NSLocalizedString("resetdata_alert_deleteandlaunch", comment: ""))
    alert.addButton(withTitle: NSLocalizedString("resetdata_alert_launch", comment: ""))
    let quitButton = alert.addButton(withTitle: NSLocalizedString("resetdata_alert_terimnate", comment: ""))
    if #available(macOS 11.0, *) {
      deleteButton.hasDestructiveAction = true
    } else {
      deleteButton.keyEquivalent = "" 
    }
    quitButton.keyEquivalent = "\u{1B}"
    
    switch alert.runModal() {
    case .alertFirstButtonReturn:
      if CoreDataManager.deleteDatabase() {
        continuation()
      } else {
        NSApplication.shared.terminate(nil)
      }
    case .alertSecondButtonReturn:
      continuation()
    default:
      NSApplication.shared.terminate(nil)
    }
  }
  
}
