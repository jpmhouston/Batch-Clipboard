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
    model = AppModel()
  }
  
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    model.wasReopened()
    return false // best to return false instead of true to tell NSApp to do nothing
  }
  
  func application(_ application: NSApplication, open urls: [URL]) {
    // get the first of the url,s ignore the rest
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
    if intent is SelectIntent {
      return SelectIntentHandler(model)
    } else if intent is ClearIntent {
      return ClearIntentHandler(model)
    } else if intent is GetIntent {
      return GetIntentHandler(model)
    } else if intent is DeleteIntent {
      return DeleteIntentHandler(model)
    } else if intent is StartIntent  {
      return StartIntentHandler(model)
    } else if intent is CancelIntent {
      return CancelIntentHandler(model)
    } else if intent is BatchCopyIntent {
      return BatchCopyIntentHandler(model)
    } else if intent is BatchPasteIntent {
      return BatchPasteIntentHandler(model)
    }
    
    return nil
  }
  
}
