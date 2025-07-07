//
//  MenubarIcon.swift
//  Cleepp
//
//  Created by Pierre Houston on 2024-03-20.
//  Copyright © 2024 Bananameter Labs. All rights reserved.
//

import AppKit

class MenuBarIcon {
  
  enum QueueChangeDirection {
    case none, increment, decrement, persistentDecrement
  }
  
  @objc let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  
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
  
  private enum SymbolTransition {
    case replace
    case blink(transitionIcon: NSImage.Name)
  }
  
  init() {
    setImage(named: .menuIcon)
    
    statusItem.button?.imagePosition = .imageRight
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
  
  func enableRemoval(_ enable: Bool, wasRemoved: (()->Void)? = nil) {
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
