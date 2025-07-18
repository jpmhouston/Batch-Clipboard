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
    
    restoreClipboardMonitoring()
    
    queue.on()
    menuIcon.update(forQueueSize: 0)
    updateMenuTitle()
    
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
    
    queue.off()
    menu.cancelledQueue()
    updateClipboardMonitoring()
    updateMenuIcon()
    updateMenuTitle()
    
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
    
    restoreClipboardMonitoring()
    
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
        updateClipboardMonitoring()
        updateMenuIcon(.decrement)
        updateMenuTitle()
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
        updateClipboardMonitoring()
        self.updateMenuIcon()
        self.updateMenuTitle()
        
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
    updateClipboardMonitoring()
    updateMenuIcon(.decrement)
    updateMenuTitle()
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
    
    guard index < history.count else {
      return false
    }
    let clip = history.all[index]
    
    queue.on()
    do {
      try queue.setHead(toIndex: index)
      
      menu.startedQueueFromHistory(atClip: clip)
      updateClipboardMonitoring()
      updateMenuIcon()
      updateMenuTitle()
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
    
    if index < queue.size {
      menu.deletedClipFromQueue(clip)
      
      fixQueueAfterDeletingClip(atIndex: index)
    } else {
      menu.deletedClipFromHistory(clip)
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
      menu.deletedClipFromQueue(clip)
      fixQueueAfterDeletingClip(atIndex: index)
    } else {
      menu.deletedClipFromHistory(clip)
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
      menu.deletedClipFromQueue(clip)
      fixQueueAfterDeletingClip(atIndex: 0)
    } else {
      menu.deletedClipFromHistory(clip)
    }
  }
  
  // MARK: - opening windows
  
  @IBAction
  func showAbout(_ sender: AnyObject) {
    Self.returnFocusToPreviousApp = false
    about.openAbout()
    Self.returnFocusToPreviousApp = true
  }
  
  @IBAction
  func showIntro(_ sender: AnyObject) {
    Self.returnFocusToPreviousApp = false
    introWindowController.openIntro(with: self)
    Self.returnFocusToPreviousApp = true
  }
  
  func showLicenses() {
    Self.returnFocusToPreviousApp = false
    licensesWindowController.openLicenses()
    Self.returnFocusToPreviousApp = true
  }
  
  @IBAction
  func showSettings(_ sender: AnyObject) {
    showSettings()
  }
  
  func showSettings(selectingPane pane: Settings.PaneIdentifier? = nil) {
    Self.returnFocusToPreviousApp = false
    settingsWindowController.show(pane: pane)
    settingsWindowController.window?.orderFrontRegardless()
    Self.returnFocusToPreviousApp = true
  }
  
  func showIntroAtPermissionPage(_ sender: AnyObject) {
    Self.returnFocusToPreviousApp = false
    introWindowController.openIntro(atPage: .checkAuth, with: self)
    Self.returnFocusToPreviousApp = true
  }
  
  func showIntroAtHistoryUpdatePage(_ sender: AnyObject) {
    Self.returnFocusToPreviousApp = false
    introWindowController.openIntro(atPage: .checkAuth, with: self) // TODO: new page for migrating to disabled history
    Self.returnFocusToPreviousApp = true
  }
  
  @IBAction
  func quit(_ sender: AnyObject) {
    NSApp.terminate(sender)
  }
  
  // MARK: - alerts
  
  private func showBonusFeaturePromotionAlert() {
    Self.returnFocusToPreviousApp = false
    DispatchQueue.main.async {
      switch self.bonusFeaturePromotionAlert.runModal() {
      case NSApplication.ModalResponse.alertFirstButtonReturn:
        self.showSettings(selectingPane: .purchase)
      default:
        break
      }
      Self.returnFocusToPreviousApp = true
    }
  }
  
  private func withNumberToPasteAlert(_ closure: @escaping (Int) -> Void) {
    let alert = numberQueuedAlert
    guard let field = alert.accessoryView as? RangedIntegerTextField else {
      return
    }
    Self.returnFocusToPreviousApp = false
    DispatchQueue.main.async {
      switch alert.runModal() {
      case NSApplication.ModalResponse.alertFirstButtonReturn:
        alert.window.orderOut(nil) // i think withClearAlert above should call this too
        let number = Int(field.stringValue) ?? self.queue.size
        closure(number)
      default:
        break
      }
      Self.returnFocusToPreviousApp = true
    }
  }
  
  private func withClearAlert(suppressClearAlert: Bool, _ closure: @escaping () -> Void) {
    guard !suppressClearAlert && !UserDefaults.standard.suppressClearAlert else {
      closure()
      return
    }
    Self.returnFocusToPreviousApp = false
    let alert = clearAlert
    DispatchQueue.main.async {
      if alert.runModal() == NSApplication.ModalResponse.alertFirstButtonReturn {
        if alert.suppressionButton?.state == .on {
          UserDefaults.standard.suppressClearAlert = true
        }
        closure()
      }
      AppModel.returnFocusToPreviousApp = true
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
    return interactive ? Permissions.check() : Permissions.allowed
  }
  
  private func restoreClipboardMonitoring() {
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
      }
    }
  }
  
  private func fixQueueAfterDeletingClip(atIndex index: Int) {
    if queue.isOn, let headIndex = queue.headIndex, index <= headIndex {
      do {
        try queue.remove(atIndex: index)
      } catch {
        os_log(.default, "failed to fix queue after deleting item, %@", error.localizedDescription)
        queue.off()
      }
      
      updateMenuIcon(.decrement)
      updateMenuTitle()
      // menu updates the head of queue item itself when deleting
    }
  }
  
  // `copyTimeoutTimer: DispatchSourceTimer?` must be declared as a property
  
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
