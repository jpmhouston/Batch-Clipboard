//
//  MenuController.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-07-10.
//  Portions Copyright © 2025 Bananameter Labs. All rights reserved.
//
//  Based on MenuController.swift from the Maccy project
//  Portions Copyright © 2024 Alexey Rodionov. All rights reserved.
//

import AppKit
import KeyboardShortcuts

class MenuController { 
  private let menu: AppMenu
  private let statusItem: NSStatusItem
  var proxyMenu: ProxyMenu! // not private (temporarily maybe) for debug logging code in appModel 
  
  private var extraVisibleWindows: [NSWindow] {
    NSApp.windows.filter({ $0.isVisible && $0.className != NSApp.statusBarWindow?.className })
  }
  
  init(_ menu: AppMenu, _ statusItem: NSStatusItem) {
    self.menu = menu
    self.statusItem = statusItem
    proxyMenu = ProxyMenu(performStatusItemClick) 
    statusItem.menu = proxyMenu
  }
  
  func popUp() {
    withFocus {
      self.simulateStatusItemClick()
    }
  }
  
  @objc
  private func performStatusItemClick(_ modifierFlags: NSEvent.ModifierFlags, _ isRightClick: Bool) {
    #if DEBUG
    if AppDelegate.shouldFakeAppInteraction && modifierFlags.contains(.capsLock) {
      AppDelegate.putPasteHistoryOnClipboard()
      return
    }
    #endif // DEBUG
    
    if !AppModel.busy {
      if modifierFlags.contains(.control) && modifierFlags.contains(.option) {
        UserDefaults.standard.ignoreEvents = !UserDefaults.standard.ignoreEvents
        
        if !modifierFlags.contains(.shift) && UserDefaults.standard.ignoreEvents {
          UserDefaults.standard.ignoreOnlyNextEvent = true
        }
        return
      }
      
      if !modifierFlags.contains(.option) && modifierFlags.contains(.control) {
        menu.performQueueModeToggle()
        return
      }
      if isRightClick && modifierFlags.isEmpty {
        menu.performQueueModeToggle()
        return
      }
    }
    
    if modifierFlags.contains(.option) {
      menu.enableExpandedMenu(true, full: modifierFlags.contains(.shift))
    }
    
    withFocus {
      self.simulateStatusItemClick()
    }
  }
  
  private func simulateStatusItemClick() {
    if let buttonCell = statusItem.button?.cell as? NSButtonCell {
      withMenuButtonHighlighted(buttonCell) {
        self.linkingMenuToStatusItem {
          self.menu.prepareForPopup()
          self.statusItem.button?.performClick(self)
        }
      }
    }
  }
  
  private func withMenuButtonHighlighted(_ buttonCell: NSButtonCell, _ closure: @escaping () -> Void) {
    if #available(macOS 11, *) {
      closure()
    } else {
      buttonCell.highlightsBy = [.changeGrayCellMask, .contentsCellMask, .pushInCellMask]
      closure()
      buttonCell.highlightsBy = []
    }
  }
  
  private func linkingMenuToStatusItem(_ closure: @escaping () -> Void) {
    statusItem.menu = menu
    closure()
    statusItem.menu = proxyMenu
  }
  
  // Executes closure with application focus (pun intended).
  //
  // Beware of hacks. This code is so fragile that you should
  // avoid touching it unless you really know what you do.
  // The code is based on hours of googling, trial-and-error
  // and testing sessions. Apologies from Maccy authors accepted..
  //
  // Once we scheduled menu popup, we need to activate
  // the application to let search text field become first
  // responder and start receiving key events.
  // Without forced activation, agent application
  // (LSUIElement) doesn't receive the focus.
  // Once activated, we need to run the closure asynchronously
  // (and with slight delay) because NSMenu.popUp() is blocking
  // execution until menu is closed (https://stackoverflow.com/q/1857603).
  // Annoying side-effect of running NSMenu.popUp() asynchronously
  // is global hotkey being immediately enabled so we no longer
  // can close menu by pressing the hotkey again. To workaround
  // this problem, lifecycle of global hotkey should live here.
  // 40ms delay was chosen by trial-and-error. It's the smallest value
  // not causing menu to close on the first time it is opened after
  // the application launch.
  //
  // Once we are done working with menu, we need to return
  // focus to previous application. However, if our selection
  // triggered new windows (Preferences, About, Intro),
  // we should preserve focus. Additionally, we should not
  // hide an application if there are additional visible windows
  // opened before.
  //
  // It's also possible to completely skip this activation
  // and fallback to default NSMenu behavior by enabling
  // UserDefaults.standard.avoidTakingFocus.
  private func withFocus(_ closure: @escaping () -> Void) {
    if UserDefaults.standard.avoidTakingFocus {
      closure()
    } else {
      NSApp.activate(ignoringOtherApps: true)
      Timer.scheduledTimer(withTimeInterval: 0.04, repeats: false) { _ in
        closure()
        if AppModel.returnFocusToPreviousApp && self.extraVisibleWindows.count == 0 {
          NSApp.hide(self)
          AppModel.returnFocusToPreviousApp = true
        }
      }
    }
  }
  
}
