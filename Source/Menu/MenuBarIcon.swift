//
//  MenubarIcon.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-03-20.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//

import AppKit

class MenuBarIcon {
  
  enum QueueChangeDirection {
    case none, increment, decrement, persistentDecrement
  }
  
  @objc let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  var menu: NSMenu?
  
  var isEnabled: Bool = true {
    didSet {
      statusItem.button?.appearsDisabled = !isEnabled
    }
  }
  
  var isVisible: Bool = true {
    didSet {
      statusItem.isVisible = isVisible
    }
  }
  
  var badge: String = "" {
    didSet {
      statusItem.button?.title = if badge.isEmpty { badge } else { badge.trimmingCharacters(in: .whitespaces) + " " }
    }
  }
  // OR?:
//  var count: Int? = nil {
//    didSet {
//      statusItem.button?.title = if let c = count { String(c) + " " } else { "" }
//    }
//  }
  
  var image: NSImage? {
    set {
      statusItem.button?.image = newValue
    }
    get {
      statusItem.button?.image
    }
  }
  
  private var visibilityObserver: NSKeyValueObservation?
  private var iconBlinkTimer: DispatchSourceTimer?
  private var iconBlinkIntervalSeconds: Double { 0.75 }
  private var shouldOpenCallback: (() -> Bool)?
  
  private enum SymbolTransition {
    case replace
    case blink(transitionIcon: NSImage.Name)
  }
  
  init() {
    setImage(named: .menuIcon)
    
    statusItem.button?.imagePosition = .imageRight
    statusItem.button?.sendAction(on: .leftMouseDown)
    if #unavailable(macOS 11) {
      (statusItem.button?.cell as? NSButtonCell)?.highlightsBy = []
    }
  }
  
  func setImage(named name: NSImage.Name) {
    guard let iconImage = NSImage(named: name) else {
      return
    }
    self.image = iconImage
  }
  
  func performClick() {
    statusItem.button?.performClick(nil)
  }
  
  func setDirectOpen(toMenu menu: NSMenu?, _ callback: (() -> Bool)? = nil) {
    if let menu = menu, let callback = callback {
      self.menu = menu
      shouldOpenCallback = callback
      statusItem.button?.target = self
      statusItem.button?.action = #selector(statusBarButtonClicked(sender:))
      statusItem.menu = nil // has to be nil for the action to be called
    } else {
      // otherwise expect statusItem.menu to be set behind our backs to
      // the ProxyMenu, and it's invoked just by being opened
      self.menu = nil
      shouldOpenCallback = nil
      statusItem.button?.target = nil
      statusItem.button?.action = nil
    }
  }
  
  @objc func statusBarButtonClicked(sender: NSStatusBarButton) {
    // thx to https://stackoverflow.com/a/59690507/592739
    guard let callback = shouldOpenCallback, let menu = menu else {
      return
    }
    if callback() {
      statusItem.menu = menu
      if #available(macOS 11, *) {
        statusItem.button?.performClick(nil)
      } else {
        let buttonCell = statusItem.button?.cell as? NSButtonCell
        buttonCell?.highlightsBy = [.changeGrayCellMask, .contentsCellMask, .pushInCellMask]
        statusItem.button?.performClick(nil)
        buttonCell?.highlightsBy = []
      }
      // example at SO sets menu to nil again in `menuDidClose`, but
      // MenuController does it right after calling `button.performClick`
      // so try that here too
      statusItem.menu = nil
    }
  }
  
  func enableRemoval(_ enable: Bool, wasRemoved: (() -> Void)? = nil) {
    if !enable {
      statusItem.behavior = []
      visibilityObserver?.invalidate()
    } else if let callback = wasRemoved {
      statusItem.behavior = .removalAllowed
      visibilityObserver = statusItem.observe(\.isVisible, options: .new) { _, change in
        if change.newValue == false {
          callback()
        }
      }
    } else {
      statusItem.behavior = .terminationOnRemoval
      visibilityObserver?.invalidate()
    }
  }
  
  func update(forQueueSize queueSize: Int?, _ direction: QueueChangeDirection = .none) {
    var icon = NSImage.Name.menuIcon
    var transition = SymbolTransition.replace
    switch (queueSize, direction) {
    case (let s?, .increment) where s == 1:
      icon = .menuIconNonempty
      transition = .blink(transitionIcon: .menuIconEmptyPlus)
    case (_?, .increment):
      icon = .menuIconNonempty
      transition = .blink(transitionIcon: .menuIconNonemptyPlus)
    case (let s?, .decrement) where s == 0:
      icon = .menuIconEmpty
      transition = .blink(transitionIcon: .menuIconNonemptyMinus)
    case (_?, .decrement):
      icon = .menuIconNonempty
      transition = .blink(transitionIcon: .menuIconNonemptyMinus)
    case (nil, .decrement):
      transition = .blink(transitionIcon: .menuIconNonemptyMinus)
    case (_, .persistentDecrement):
      icon = .menuIconNonemptyMinus
    case (let s?, .none) where s == 0:
      icon = .menuIconEmpty
    case (_?, .none):
      icon = .menuIconNonempty
    default:
      break
    }
    
    guard let iconImage = NSImage(named: icon) else {
      return
    }
    
    if case .blink(let transitionIcon) = transition, let transitionImage = NSImage(named: transitionIcon) {
      // first show transition symbol, then blink to the final symbol
      statusItem.button?.image = transitionImage
      runOnIconBlinkTimer(afterDelay: iconBlinkIntervalSeconds) { [weak self] in
        self?.statusItem.button?.image = iconImage
      }
    } else {
      statusItem.button?.image = iconImage
    }
  }
  
  private func runOnIconBlinkTimer(afterDelay delay: Double, _ action: @escaping () -> Void) {
    if iconBlinkTimer != nil {
      cancelBlinkTimer()
    }
    iconBlinkTimer = DispatchSource.scheduledTimerForRunningOnMainQueue(afterDelay: delay) { [weak self] in
      self?.iconBlinkTimer = nil // doing this before calling closure supports closure itself calling runOnIconBlinkTimer, fwiw
      action()
    }
  }
  
  internal func cancelBlinkTimer() {
    iconBlinkTimer?.cancel()
    iconBlinkTimer = nil
  }
  
}
