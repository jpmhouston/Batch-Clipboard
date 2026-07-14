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
import os.log
#if SPARKLE_UPDATES
import Sparkle
#endif
#if !APP_STORE
import DiskArbitration
#endif

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
  
  var model: AppModel?
  
  func applicationDidFinishLaunching(_ aNotification: Notification) {
    var askToResetDate = false
    
    if ProcessInfo.processInfo.arguments.contains("ui-testing") {
      if !CoreDataManager.deleteDatabase() {
        NSApplication.shared.terminate(nil)
        return
      }
    } else {
      // detect launch with the option key held early, but use this after potential move-app alert
      askToResetDate = NSEvent.modifierFlags.contains(.option)
    }
    
    DispatchQueue.main.async { [weak self] in
      // alerts opened synchronously during launch need to do so after `DidFinishLaunching` fnishes
      guard let self = self else { return }
      
      #if !APP_STORE
      if !UserDefaults.standard.suppressLaunchFromDMGAlert &&
          isOnVolumeBackedByDiskImage(URL(fileURLWithPath: Bundle.main.bundlePath)) {
        switch showDiskImageLaunchAlert() {
        case true:
          UserDefaults.standard.suppressLaunchFromDMGAlert = true
        case false:
          break
        default:
          NSApplication.shared.terminate(nil)
          return
        }
      }
      #endif
      
      if askToResetDate {
        switch showResetAlert() {
        case true:
          if !CoreDataManager.deleteDatabase() {
            NSApplication.shared.terminate(nil)
            return
          }
        case false:
          break
        default:
          NSApplication.shared.terminate(nil)
          return
        }
      }
      
      model = AppModel()
    }
  }
  
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    model?.wasReopened()
    return false // best to return false instead of true to tell NSApp to do nothing
  }
  
  func applicationWillBecomeActive(_ notification: Notification) {
    model?.wasActvated()
  }
  
  func application(_ application: NSApplication, open urls: [URL]) {
    // get the first of the url's, ignore the rest
    guard let url = urls.first else {
      return
    }
    if url.absoluteString == AppModel.showIntroInAppURL {
      model?.showIntro(self)
    }
    if url.absoluteString == AppModel.showAboutInAppURL {
      model?.showAbout(self)
    }
    if url.absoluteString == AppModel.showLicensesInAppURL {
      model?.showLicenses()
    }
    if url.absoluteString == AppModel.toggleQueueModeInAppURL {
      model?.toggleQueueMode()
    }
  }
  
  func applicationWillTerminate(_ notification: Notification) {
    model?.terminate()
    CoreDataManager.shared.saveContext()
  }
  
  func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
    return model?.dockMenu
  }
  
  @available(macOS 11.0, *)
  func application(_ application: NSApplication, handlerFor intent: INIntent) -> Any? {
    guard let model = model else { return nil }
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
  
  // MARK: -
  
  private func showResetAlert() -> Bool? {
    NSApp.activate(ignoringOtherApps: true)
    
    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = NSLocalizedString("resetdata_alert_message", comment: "")
    alert.informativeText = NSLocalizedString("resetdata_alert_comment", comment: "")
    let deleteButton = alert.addButton(withTitle: NSLocalizedString("resetdata_alert_deleteandlaunch", comment: ""))
    alert.addButton(withTitle: NSLocalizedString("resetdata_alert_launch", comment: ""))
    let quitButton = alert.addButton(withTitle: NSLocalizedString("resetdata_alert_terminate", comment: ""))
    if #available(macOS 11.0, *) {
      deleteButton.hasDestructiveAction = true
    } else {
      deleteButton.keyEquivalent = "" 
    }
    quitButton.keyEquivalent = "\u{1B}"
    
    switch alert.runModal() {
    case .alertFirstButtonReturn:
      return true
    case .alertSecondButtonReturn:
      return false
    default:
      return nil
    }
  }
  
  #if !APP_STORE
  func showDiskImageLaunchAlert() -> Bool? {
    NSApp.activate(ignoringOtherApps: true)
    
    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.showsSuppressionButton = true
    alert.messageText = NSLocalizedString("runoffdmg_alert_message", comment: "")
    alert.informativeText = NSLocalizedString("runoffdmg_alert_comment", comment: "")
    let launchButton = alert.addButton(withTitle: NSLocalizedString("runoffdmg_alert_launch", comment: ""))
    launchButton.keyEquivalent = ""
    let quitButton = alert.addButton(withTitle: NSLocalizedString("runoffdmg_alert_terminate", comment: ""))
    quitButton.keyEquivalent = "\u{1B}"
    
    switch alert.runModal() {
    case .alertFirstButtonReturn:
      return alert.suppressionButton?.state == .on
    default:
      return nil
    }
  }
  
  private func isOnVolumeBackedByDiskImage(_ pathURL: URL) -> Bool {
    // Disk image detection (derived from function generated by Xcode 26's LLM assistant running ChatGPT,
    // however needed do a web search myself to find a working technique)
    
    // LLM originally suggested once getting `volumeURL`, but it wasn't clear where to go from `deviceNumber`:
    //let fm = FileManager.default
    //guard let attributes = try? fm.attributesOfFileSystem(forPath: volumeURL.path),
    //      let deviceNumber = attributes[.systemNumber] as? NSNumber else { return false }
    //
    // Instead of using `DADiskCreateFromBSDName` below, the LLM originally recommended using an apparently
    // undocumented (or maybe hallucinated?) function `DADiskCopyDisks` to iterate over all disks and pick out
    // the matching one. It suggest matching by bsd device name (a la /dev/diskXxxx) and code to fetch that
    // was an adventure all unto itself, but match ing deviceNumber probably would have worked.
    //for disk in DADiskCopyDisks(session) as? [DADisk] ?? [] { ... }
    
    // Get the mount path for the file’s volume, use Disk Arbitration session to find its detailed information.
    guard let volumeURL = try? pathURL.resourceValues(forKeys: [.volumeURLKey]).volume,
          let session = DASessionCreate(kCFAllocatorDefault),
          let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, volumeURL as CFURL),
          let description = DADiskCopyDescription(disk) as NSDictionary? else {
      os_log(.default, "launch volume check failed to access disk description")
      return false
    }
    
    // Check for keys in teh DADisk that indicate a .dmg file
    // (no thanks to LLM which suggested value of `DAMediaPath` key would be path to the .dmg, but instead
    // to https://github.com/balena-io/etcher/issues/2661 which did the work of comparing DADisk description dicts)
    os_log(.default, "launch from path %@, volume %@", pathURL.description, volumeURL.description)
    os_log(.default, "volume desc fields DeviceProtocol %@, DeviceModel %@, MediaPath %@", description[kDADiskDescriptionDeviceProtocolKey as String] as? String ?? "?", description[kDADiskDescriptionDeviceModelKey as String] as? String ?? "?", description[kDADiskDescriptionMediaPathKey as String] as? String ?? "?")
    return description[kDADiskDescriptionDeviceProtocolKey as String] as? String == "Virtual Interface" ||
           description[kDADiskDescriptionDeviceModelKey as String] as? String == "Disk Image"
  }
  #endif
  
}
