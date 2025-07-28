//
//  AppModel+Actions.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-03-20.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//

import AppKit
import Settings
import os.log

// TODO: make methods return error instead of bool

// TODO: put these somewhere else
func nop() { }
func dontWarnUnused(_ x: Any) { }

extension AppModel {
  
  private var copyTimeoutSeconds: Double { 1.0 }
  private var standardPasteDelaySeconds: Double { 0.33333 }
  private var standardPasteDelay: DispatchTimeInterval { .milliseconds(Int(standardPasteDelaySeconds * 1000)) }
  private var extraPasteDelaySeconds: Double { 0.66666 }
  private var extraPasteDelay: DispatchTimeInterval { .milliseconds(Int(extraPasteDelaySeconds * 1000)) }
  private var pasteMultipleDelay: DispatchTimeInterval { .milliseconds(Int(extraPasteDelaySeconds * 1000)) }
  
  private var extraDelayOnQueuedPaste: Bool {
    #if arch(x86_64) || arch(i386)
    true
    #else
    false
    #endif
    // or maybe is not processor, but instead the latest OS fixes need for longer delay
    //if #unavailable(macOS 14) { true } else { false }
  }
  
  // MARK: - simple intent handlers
  
  func delete(position: Int) -> Clip? {
    guard position < history.count else {
      return nil
    }
    let clip: Clip = history.all[position]
    deleteClip(atIndex: position)
    return clip
  }
  
  func item(at position: Int) -> Clip? {
    guard position < history.count else {
      return nil
    }
    return history.all[position]
  }
  
  func clearHistory(suppressClearAlert: Bool = false) {
    withClearAlert(suppressClearAlert: suppressClearAlert) {
      self.queue.off()
      self.history.clear()
      self.menu.deletedHistory()
      self.clipboard.clear()
      self.updateMenuIcon()
      self.updateMenuTitle()
    }
  }
  
  // MARK: - clipboard features
  
  @IBAction
  func startQueueMode(_ sender: AnyObject) {
    // convenience handler for the menu item
    menu.cancelTrackingWithoutAnimation() // do this before any alerts appear
    startQueueMode(interactive: true)
  }
  
  func startQueueMode() {
    // convenience handler for the global keyboard shortcut
    startQueueMode(interactive: true)
  }
  
  @discardableResult
  func startQueueMode(interactive: Bool = false) -> Bool {
    // handler for the global keyboard shortcut and menu item via convenience functions above,
    // and for the intent which calls this directly
    guard !Self.busy else {
      return false
    }
    guard accessibilityCheck(interactive: interactive) else {
      return false
    }
    guard !queue.isOn else {
      return false
    }
    
    queue.on()
    menuIcon.update(forQueueSize: 0)
    updateMenuTitle()
    commenceClipboardMonitoring()
    
    return true
  }
  
  @IBAction
  func cancelQueueMode(_ sender: AnyObject) {
    cancelQueueMode()
  }
  
  @discardableResult
  func cancelQueueMode() -> Bool {
    guard !Self.busy else {
      return false
    }
    guard queue.isOn else {
      return false
    }
    
    let count = queue.size
    
    queue.off()
    menu.cancelledQueue(count)
    updateMenuIcon()
    updateMenuTitle()
    updateClipboardMonitoring()
    
    return true
  }
  
  @IBAction
  func startReplay(_ sender: AnyObject) {
    do {
      try queue.replaying()
    } catch {
      return
    }
  }
  
  @IBAction
  func queuedCopy(_ sender: AnyObject) {
    // convenience handler for the menu item
    menu.cancelTrackingWithoutAnimation() // do this before any alerts appear
    queuedCopy(interactive: true)
  }
  
  func queuedCopy() {
    // convenience handler for the global keyboard shortcut
    queuedCopy(interactive: true)
  }
  
  @discardableResult
  func queuedCopy(interactive: Bool) -> Bool {
    // handler for the global keyboard shortcut and menu item via convenience functions above,
    // and for the intent which calls this directly
    guard !Self.busy else {
      return false
    }
    guard accessibilityCheck(interactive: interactive) else {
      return false
    }
    
    commenceClipboardMonitoring()
    
    if !queue.isOn {
      queue.on()
    }
    
    Self.busy = true
    
    // make the frontmost application perform a copy
    // let clipboard object detect this normally and invoke incrementQueue
    clipboard.invokeApplicationCopy() { [weak self] in
      guard let self = self else { return }
      
      // allow copy again if no copy deletected after this duration
      self.runOnCopyTimeoutTimer(afterTimeout: self.copyTimeoutSeconds) { [weak self] in
        guard self != nil else { return }
        
        Self.busy = false
      }
    }
    
    return true
  }
  
  func clipboardChanged(_ clip: Clip) {
    // cancel timeout if its timer is active and clear the busy flag controlled by the timer
    let withinTimeout = copyTimeoutTimer != nil
    if withinTimeout {
      cancelCopyTimeoutTimer()
      // perhaps assert Self.busy here?
      
      // i tried having this in a defer, awkward, should be the same to do it early
      Self.busy = false
    }
    
    if queue.isOn {
      do {
        try queue.add(clip)
        
        menu.addedClipToQueue(clip)
        updateMenuIcon(.increment)
        updateMenuTitle()
      } catch { }
      
    } else {
      history.add(clip)
      menu.addedClipToHistory(clip)
    }
  }
  
  @IBAction
  func queuedPaste(_ sender: AnyObject) {
    // convenience handler for the menu item
    menu.cancelTrackingWithoutAnimation() // do this before any alerts appear
    queuedPaste(interactive: true)
  }
  
  func queuedPaste() {
    // convenience handler for the global keyboard shortcut
    queuedPaste(interactive: true)
  }
  
  @discardableResult
  func queuedPaste(interactive: Bool) -> Bool {
    // handler for the global keyboard shortcut and menu item via convenience functions above,
    // and for the intent which calls this directly
    guard !Self.busy else {
      return false
    }
    
    guard !queue.isEmpty else {
      return false
    }
    guard accessibilityCheck(interactive: interactive) else {
      return false
    }
    
    do {
      try queue.replaying()
    } catch {
      return false
    }
    
    Self.busy = true
    
    let decrementQueueDelay = extraDelayOnQueuedPaste ? extraPasteDelay : standardPasteDelay
    
    // make the frontmost application perform a paste, then advance the queue after our
    // heuristic delay, keep the app from doing anything else until them
    invokeApplicationPaste(plusDelay: decrementQueueDelay) { [weak self] in
      guard let self = self else { return }
      
      do {
        try self.queue.remove()
        
        menu.poppedClipOffQueue()
        updateMenuIcon(.decrement)
        updateMenuTitle()
        updateClipboardMonitoring()
      } catch { }
      
      Self.busy = false
      
      #if APP_STORE
      if !queue.isOn {
        AppStoreReview.ask(after: 20)
      }
      #endif
    }
    
    return true
  }
  
  func invokeApplicationPaste(plusDelay delay: DispatchTimeInterval, then completion: @escaping () -> Void) {
    clipboard.invokeApplicationPaste() {
      // paste is always followed by a delay to give the frontmost app time to start performing the paste
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        completion()
      }
    }
  }
  
  @IBAction
  func queuedPasteMultiple(_ sender: AnyObject) {
    menu.cancelTrackingWithoutAnimation() // do this before any alerts appear
    guard !Self.busy else {
      return
    }
    
    guard AppModel.allowPasteMultiple else {
      showBonusFeaturePromotionAlert()
      return
    }
    
    guard !queue.isEmpty else {
      return
    }
    guard accessibilityCheck() else {
      return
    }
    
    menu.cancelTrackingWithoutAnimation() // do this before any alerts appear
    withNumberToPasteAlert() { number in
      // Tricky! See MenuController for how `withFocus` normally uses NSApp.hide
      // after making the menu open, except when returnFocusToPreviousApp false.
      // `withNumberToPasteAlert` must set that flag to false to run the alert
      // and so at this moment our app has not been hidden.
      // `invokeApplicationPaste` internally does a dispatch async around
      // controlling the frontmost app so it does so only after the `withFocus`
      // closure does NSApp.hide as it exits.
      // Because this runs after withFocus has already exited without doing
      // NSApp.hide (since withNumberToPasteAlert sets returnFocusToPreviousApp
      // to false), and we want to immediately control the app now, must do the
      // NSApp.hide ourselves here.
      NSApp.hide(self)
      
      self.queuedPasteMultiple(number, interactive: true)
    }
  }
  
  @IBAction
  func queuedPasteAll(_ sender: AnyObject) {
    menu.cancelTrackingWithoutAnimation() // do this before any alerts appear
    guard !Self.busy else {
      return
    }
    
    guard AppModel.allowPasteMultiple else {
      showBonusFeaturePromotionAlert()
      return
    }
    
    guard !queue.isEmpty else {
      return
    }
    guard accessibilityCheck() else {
      return
    }
    
    queuedPasteMultiple(queue.size, interactive: true)
  }
  
  // TODO: add support for paste all/multiple from an intent
  
  @discardableResult
  private func queuedPasteMultiple(_ count: Int, interactive: Bool = true) -> Bool {
    guard count >= 1 && count <= queue.size else {
      return false
    }
    if count == 1 {
      return queuedPaste(interactive: interactive)
    } else {
      do {
        try queue.putNextOnClipboard()
      } catch {
        return false
      }
      
      Self.busy = true
      
      // menu icon will show "-" for the duration
      updateMenuIcon(.persistentDecrement)
      
      queuedPasteMultipleIterator(to: count) { [weak self] num in
        guard let self = self else { return }
        
        self.queue.finishBulkRemove()
        
        // final update to these and including icon not updated since the start
        self.menu.poppedClipsOffQueue(num)
        self.updateMenuIcon()
        self.updateMenuTitle()
        self.updateClipboardMonitoring()
        
        Self.busy = false
        
        #if APP_STORE
        if !queue.isOn && interactive {
          AppStoreReview.ask(after: 20)
        }
        #endif
      }
      
      return true
    }
  }
  
  private func queuedPasteMultipleIterator(increment count: Int = 0, to max: Int, then completion: @escaping (Int)->Void) {
    guard max > 0 && count < max, let index = queue.headIndex, index < history.count else {
      // don't expect to ever be called with count>=max, exit condition is below, before recursive call
      completion(count)
      return
    }
    
    nop() // TODO: remove once no longer need a breakpoint here
    
    // presume item to be pasted is already be on the clpiaboard, make the frontmost application
    // to perform a paste, then advance the queue after our long delay and either exit or recurse
    invokeApplicationPaste(plusDelay: self.pasteMultipleDelay) { [weak self] in
      guard let self = self else { return }
      
      do {
        try queue.bulkRemoveNext()
      } catch {
        completion(count + 1)
        return
      }
      if queue.isEmpty || count + 1 >= max {
        completion(count + 1)
        return
      }
      
      updateMenuTitle()
      self.queuedPasteMultipleIterator(increment: count + 1, to: max, then: completion)
    }
  }
  
  @IBAction
  func advanceReplay(_ sender: AnyObject) {
    guard !Self.busy else {
      return
    }
    
    guard !queue.isEmpty else {
      return
    }
    
    do {
      try queue.replaying()
    } catch {
      return
    }
    
    do {
      try self.queue.remove()
    } catch {
      return
    }
    
    menu.poppedClipOffQueue()
    updateMenuIcon(.decrement)
    updateMenuTitle()
    updateClipboardMonitoring()
  }
  
  @IBAction
  func replayFromHistory(_ sender: AnyObject) {
    menu.cancelTrackingWithoutAnimation() // do this before any alerts appear
    guard let clip = (sender as? ClipMenuItem)?.clip, let index = history.all.firstIndex(of: clip) else {
      return
    }
    replayFromHistory(atIndex: index, interactive: true)
  }
  
  @discardableResult
  func replayFromHistory(atIndex index: Int, interactive: Bool = false) -> Bool {
    guard AppModel.allowReplayFromHistory else {
      return false
    }
    guard !Self.busy else {
      return false
    }
    guard accessibilityCheck() else {
      return false
    }
    
    guard !queue.isOn && index < history.count else {
      return false
    }
    
    queue.on()
    do {
      #if DEBUG
      try queue.setHead(toIndex: index)
      #endif
      
      menu.startedQueueFromHistory(index)
      updateMenuIcon()
      updateMenuTitle()
      commenceClipboardMonitoring()
    } catch {
      queue.off()
      
      return false
    }
    
    return true
  }
  
  @IBAction
  func copyClip(_ sender: AnyObject) {
    guard !Self.busy else {
      return
    }
    
    guard let clip = (sender as? ClipMenuItem)?.clip else {
      return
    }
    
    clipboard.copy(clip)
  }
  
  func deleteClip(atIndex index: Int) {
    guard !Self.busy else {
      return
    }
    guard index < history.count else {
      return
    }
    let clip = history.all[index]
    
    history.remove(clip)
    
    if index < queue.size {
      do {
        try queue.remove(atIndex: index)
      } catch {
        queue.off()
      }
      
      menu.deletedClipFromQueue(index)
      updateMenuIcon(.decrement)
      updateMenuTitle()
    } else {
      menu.deletedClipFromHistory(index - queue.size)
    }
    
    return
  }
  
  @IBAction
  func deleteHighlightedClip(_ sender: AnyObject) {
    guard !Self.busy else {
      return // TODO: restore logging breakpoint here once solving why it fires even when guard passes
    }
    
    guard let clip = menu.highlightedClipMenuItem()?.clip, let index = history.all.firstIndex(of: clip) else {
      return
    }
    
    history.remove(clip)
    
    if index < queue.size {
      do {
        try queue.remove(atIndex: index)
      } catch {
        queue.off()
      }
      
      menu.deletedClipFromQueue(index)
      updateMenuIcon(.decrement)
      updateMenuTitle()
      
    } else {
      menu.deletedClipFromHistory(index)
    }
  }
  
  private func maintainQueueAfterDeletion(atIndex index: Int) {
    if queue.isOn, let headIndex = queue.headIndex, index <= headIndex {
      do {
        try queue.remove(atIndex: index)
      } catch {
        fatalError("failed to fix queue after deleting item")
      }
    }
  }
  
  @IBAction
  func clear(_ sender: AnyObject) {
    guard !Self.busy else {
      return
    }
    
    clearHistory(suppressClearAlert: false)
  }
  
  @IBAction
  func undoLastCopy(_ sender: AnyObject) {
    guard !Self.busy else {
      return
    }
    
    guard AppModel.allowUndoCopy else {
      showBonusFeaturePromotionAlert()
      return
    }
    
    guard let clip = history.first else {
      return
    }
    
    history.remove(clip)
    
    if !queue.isEmpty {
      do {
        try queue.remove(atIndex: 0)
      } catch {
        queue.off()
      }
      
      menu.deletedClipFromQueue(0)
      updateMenuIcon(.decrement)
      updateMenuTitle()
    } else {
      menu.deletedClipFromHistory(0)
    }
  }
  
  // MARK: - opening windows
  
  @IBAction
  func showAbout(_ sender: AnyObject) {
    #if DEBUG
    if NSEvent.modifierFlags.contains(.option) {
      print("\(history.count) clip items stored")
      return
    }
    #endif
    takeFocus()
    about.openAbout()
  }
  
  @IBAction
  func showIntro(_ sender: AnyObject) {
    sanityCheckStatusItem() // log this here because it can be triggered from an open about box
    takeFocus()
    introWindowController.openIntro(with: self)
  }
  
  func showLicenses() {
    takeFocus()
    licensesWindowController.openLicenses()
  }
  
  @IBAction
  func showSettings(_ sender: AnyObject) {
    showSettings()
  }
  
  func showSettings(selectingPane pane: Settings.PaneIdentifier? = nil) {
    sanityCheckStatusItem() // log stuff here because it can be triggered from an open intro window
    takeFocus()
    settingsWindowController.show(pane: pane)
    settingsWindowController.window?.orderFrontRegardless()
  }
  
  func showIntroAtPermissionPage() {
    takeFocus()
    introWindowController.openIntro(atPage: .checkAuth, with: self)
  }
  
  func showIntroAtHistoryUpdatePage() {
    takeFocus()
    introWindowController.openIntro(atPage: .historyChoice, with: self)
  }
  
  func openSecurityPanel() {
    guard let url = URL(string: Self.openSettingsPanelURL) else {
      os_log(.default, "failed to create in-app URL to show Settings %@", Self.openSettingsPanelURL)
      return
    }
    if !NSWorkspace.shared.open(url) {
      os_log(.default, "failed to open in-app URL to show Settings %@", Self.openSettingsPanelURL)
    }
  }
  
  @IBAction
  func quit(_ sender: AnyObject) {
    NSApp.terminate(sender)
  }
  
  func sanityCheckStatusItem() {
    #if false // DEBUG
    os_log(.debug, "NSStatusItem = %@, isVisible = %d, UserDefaults showInStatusBar = %d, AppModel = %@, ProxyMenu = %@",
           menuIcon.statusItem, menuIcon.statusItem.isVisible, UserDefaults.standard.showInStatusBar,
           (NSApp.delegate as! AppDelegate).model!, (NSApp.delegate as! AppDelegate).model!.menuController!.proxyMenu)
    #endif
  }
  
  // MARK: - opening alerts
  
  private func showBonusFeaturePromotionAlert() {
    takeFocus()
    DispatchQueue.main.async {
      switch self.bonusFeaturePromotionAlert.runModal() {
      case NSApplication.ModalResponse.alertFirstButtonReturn:
        self.showSettings(selectingPane: .purchase)
      default:
        break
      }
      self.returnFocus()
    }
  }
  
  private func withNumberToPasteAlert(_ closure: @escaping (Int) -> Void) {
    let alert = numberQueuedAlert
    guard let field = alert.accessoryView as? RangedIntegerTextField else {
      return
    }
    takeFocus()
    DispatchQueue.main.async {
      switch alert.runModal() {
      case NSApplication.ModalResponse.alertFirstButtonReturn:
        alert.window.orderOut(nil) // i think withClearAlert above should call this too
        let number = Int(field.stringValue) ?? self.queue.size
        closure(number)
      default:
        break
      }
      self.returnFocus()
    }
  }
  
  private func withClearAlert(suppressClearAlert: Bool, _ closure: @escaping () -> Void) {
    guard !suppressClearAlert && !UserDefaults.standard.suppressClearAlert else {
      closure()
      return
    }
    takeFocus()
    let alert = clearAlert
    DispatchQueue.main.async {
      if alert.runModal() == NSApplication.ModalResponse.alertFirstButtonReturn {
        if alert.suppressionButton?.state == .on {
          UserDefaults.standard.suppressClearAlert = true
        }
        closure()
      }
      self.returnFocus()
    }
  }
  
  enum PermissionResponse { case cancel, openSettings, openIntro  }
  private func withPermissionAlert(_ closure: @escaping (PermissionResponse) -> Void) {
    takeFocus()
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
      self.returnFocus()
    }
  }
  
  // MARK: - utility functions
  
  internal func updateMenuIcon(_ direction: MenuBarIcon.QueueChangeDirection = .none) {
    menuIcon.update(forQueueSize: (queue.isOn ? queue.size : nil), direction) 
  }
  
  internal func updateMenuTitle() {
    menuIcon.badge = queue.isOn ? String(queue.size) : ""
  }
  
  private func accessibilityCheck(interactive: Bool = true) -> Bool {
    #if DEBUG
    if AppDelegate.shouldFakeAppInteraction {
      return true // clipboard short-circuits the frontmost app TODO: eventually use a mock clipboard obj
    }
    #endif
    let permissionGranted = hasAccessibilityPermissionBeenGranted()
    if interactive && !permissionGranted {
      withPermissionAlert() { [weak self] response in
        switch response {
        case .openSettings:
          self?.openSecurityPanel()
        case .openIntro:
          self?.showIntroAtPermissionPage()
        default:
          break
        }
      }
    }
    return permissionGranted
  }
  
  private func commenceClipboardMonitoring() {
    if !UserDefaults.standard.keepHistory {
      clipboard.restart()
    } else if UserDefaults.standard.ignoreEvents {
      UserDefaults.standard.ignoreEvents = false
      UserDefaults.standard.ignoreOnlyNextEvent = false
    }
  }
  
  private func updateClipboardMonitoring() {
    if !UserDefaults.standard.keepHistory && !queue.isOn {
      clipboard.stop()
      if !UserDefaults.standard.saveClipsAcrossDisabledHistory {
        history.clear()
        menu.deletedHistory()
      }
    }
  }
  
  // `runOnCopyTimeoutTimer` requires that `copyTimeoutTimer: DispatchSourceTimer?`
  // be declared as a property, cannot be done within this extension
  
  private func runOnCopyTimeoutTimer(afterTimeout timeout: Double, _ action: @escaping () -> Void) {
    if copyTimeoutTimer != nil {
      cancelCopyTimeoutTimer()
    }
    copyTimeoutTimer = DispatchSource.scheduledTimerForRunningOnMainQueue(afterDelay: timeout) { [weak self] in
      self?.copyTimeoutTimer = nil // doing this before calling closure supports closure itself calling runOnCopyTimeoutTimer, fwiw
      action()
    }
  }
  
  private func cancelCopyTimeoutTimer() {
    copyTimeoutTimer?.cancel()
    copyTimeoutTimer = nil
  }
  
}
