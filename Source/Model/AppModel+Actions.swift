//
//  AppModel+Actions.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-03-20.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//

// swiftlint:disable file_length
import AppKit
import KeyboardShortcuts
import Settings
import os.log

// TODO: make methods throw or at least return error instead of bool
// TODO: os_log more caught errors
// TODO: restore the saved breakpoints that got made invalid

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
    deleteHistoryClip(atIndex: position)
    return clip
  }
  
  func item(at position: Int) -> Clip? {
    guard position < history.count else {
      return nil
    }
    return history.all[position]
  }
  
  func clearHistory() {
    deleteClips()
  }
  
  // TODO: add missing intent handlers
  // getting item from queue and batch, deleting from queue and batch, deleting entire batch,
  // paste all/multiple, replay last batch
  
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
    
    do {
      try queue.off()
    } catch {
      os_log(.default, "ignoring error from turning off queue %@", "\(error)")
    }
    
    if history.isListActive {
      // after canceling the queue its contents may have been added to the history
      history.trim(to: Self.effectiveMaxClips)
    }
    
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
  func queuedCopy(interactive: Bool = false) -> Bool {
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
      } catch {
        return
      }
      
      menu.addedClipToQueue(clip)
      updateMenuIcon(.increment)
      updateMenuTitle()
      
    } else if history.isListActive {
      history.add(clip)
      history.trim(to: Self.effectiveMaxClips)
      
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
  func queuedPaste(interactive: Bool = false) -> Bool {
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
      
      defer {
        Self.busy = false // in a defer so the catch below can simply early-exit
      }
      
      do {
        try self.queue.dequeue()
      } catch {
        return
      }
      
      if !queue.isOn && history.isListActive {
        // dequeuing has turned off the queue and its contents may have been added to the history
        history.trim(to: Self.effectiveMaxClips)
      }
      
      menu.poppedClipOffQueue()
      updateMenuIcon(.decrement)
      updateMenuTitle()
      updateClipboardMonitoring()
      
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
    queuedPasteMultiple(count: nil, interactive: true)
  }
  
  @IBAction
  func queuedPasteAll(_ sender: AnyObject) {
    menu.cancelTrackingWithoutAnimation() // do this before any alerts appear
    queuedPasteMultiple(count: queue.size, interactive: true)
  }
  
  @discardableResult
  func queuedPasteMultiple(count: Int?, interactive: Bool = false) -> Bool {
    guard !Self.busy else {
      return false
    }
    
    guard AppModel.allowPasteMultiple else {
      if interactive {
        showBonusFeaturePromotionAlert()
      }
      return false
    }
    
    guard !queue.isEmpty else {
      return false
    }
    guard accessibilityCheck(interactive: interactive) else {
      return false
    }
    
    if let count = count {
      return queuedPasteMultiple(min(count, queue.size), interactive: interactive)
      
    } else {
      showNumberToPasteAlert { number, seperatorStr in
        self.queuedPasteMultiple(number, seperator: seperatorStr, interactive: interactive)
      }
      
      return true
    }
  }
  
  @discardableResult
  private func queuedPasteMultiple(_ count: Int, seperator: String? = nil, interactive: Bool = true) -> Bool {
    guard count >= 1 && count <= queue.size else {
      return false
    }
    if count == 1 {
      return queuedPaste(interactive: interactive)
    } else {
      do {
        try queue.replaying() // ensures queue head is on the clipboard
      } catch {
        return false
      }
      
      Self.busy = true
      
      // menu icon will show "-" for the duration
      updateMenuIcon(.persistentDecrement)
      
      queuedPasteMultipleIterator(to: count, withSeparator: seperator) { [weak self] _ in
        guard let self = self else { return }
        
        do {
          try self.queue.finishBulkDequeue()
        } catch {
          // clipboard might be in wrong state, otherwise presume continuing
          // should be the most correct thing
        }
        
        if !queue.isOn && history.isListActive {
          // dequeuing has turned off the queue and its contents may have been added to the history
          history.trim(to: Self.effectiveMaxClips)
        }
        
        // final update to these and including icon not updated since the start
        self.menu.poppedClipsOffQueue(count)
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
  
  private func queuedPasteMultipleIterator(increment count: Int = 0, to max: Int, withSeparator seperator: String?,
                                           then completion: @escaping (Int) -> Void) {
    guard max > 0 && count < max else {
      // don't expect to ever be called with count>=max, exit condition is below, before recursive call
      completion(count)
      return
    }
    
    nop() // TODO: remove once no longer need a breakpoint here
    
    // presume item to be pasted is already be on the clpiaboard, make the frontmost application
    // to perform a paste, then advance the queue after our long delay and either exit or recurse
    invokeApplicationPaste(plusDelay: self.pasteMultipleDelay) { [weak self] in
      guard let self = self else { return }
      
      // catch up to the paste that just happened, ie. after the first paste newCount=1 here
      let newCount = count + 1
      
      if queue.isEmpty || newCount >= max { // exit after last item pasted
        completion(newCount)
        return
      }
      
      if let seperator = seperator, !seperator.isEmpty {
        // paste the separator between clips
        clipboard.copy(seperator)
        invokeApplicationPaste(plusDelay: self.pasteMultipleDelay) { [weak self] in
          guard self != nil else { return }
          next(newCount)
        }
      } else {
        next(newCount)
      }
      
      func next(_ nextCount: Int) {
        do {
          try queue.bulkDequeueNext()
        } catch {
          completion(nextCount)
          return
        }
        
        updateMenuTitle()
        queuedPasteMultipleIterator(increment: nextCount, to: max, withSeparator: seperator, then: completion)
      }
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
      try self.queue.dequeue()
    } catch {
      return
    }
    
    if !queue.isOn && history.isListActive {
      // dequeuing has turned off the queue and its contents may have been added to the history
      history.trim(to: Self.effectiveMaxClips)
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
    guard !Self.busy else {
      return false
    }
    guard AppModel.allowReplayFromHistory else {
      return false
    }
    guard accessibilityCheck() else {
      return false
    }
    
    guard history.isListActive && !queue.isOn && index < history.count else {
      return false
    }
    
    let clips = history.clipsFromIndex(index)
    guard !clips.isEmpty else {
      return false
    }
    
    do {
      try queue.setQueueClips(to: clips)
      try queue.replaying()
    } catch {
      return false
    }
    
    menu.startedQueueFromHistory(index)
    updateMenuIcon()
    updateMenuTitle()
    commenceClipboardMonitoring()
    
    return true
  }
  
  @IBAction
  func replayLastBatch(_ sender: AnyObject) {
    menu.cancelTrackingWithoutAnimation()
    replayBatch(history.lastBatch, interactive: true)
  }
  
  func replayLastBatch() {
    // convenience handler for the global keyboard shortcut
    replayBatch(history.lastBatch, interactive: true)
  }
  
  @IBAction
  func replaySavedBatch(_ sender: AnyObject) {
    menu.cancelTrackingWithoutAnimation()
    guard let item = sender as? BatchMenuItem ?? BatchMenuItem.parentBatchMenuItem(for: sender), let batch = item.batch else {
      return
    }
    
    replayBatch(batch, interactive: true)
  }
  
  func replaySavedBatch(_ batch: Batch) {
    // convenience handler for the global keyboard shortcut
    replayBatch(batch, interactive: true)
  }
  
  @discardableResult
  func replayBatch(_ batch: Batch?, interactive: Bool = false) -> Bool {
    guard !Self.busy else {
      return false
    }
    
    guard AppModel.allowReplayLastBatch else {
      if interactive {
        showBonusFeaturePromotionAlert()
      }
      return false
    }
    
    guard !queue.isOn else {
      return false
    }
    guard let batch = batch, !batch.isEmpty else {
      return false
    }
    
    do {
      try queue.replayQueue()
    } catch {
      return false
    }
    
    menu.startedQueueFromBatch()
    updateMenuIcon()
    updateMenuTitle()
    commenceClipboardMonitoring()
    
    return true
  }
  
  @IBAction
  func renameSavedBatch(_ sender: AnyObject) {
    menu.cancelTrackingWithoutAnimation()
    guard let item = sender as? BatchMenuItem ?? BatchMenuItem.parentBatchMenuItem(for: sender), let batch = item.batch else {
      return
    }
    
    guard let intialName = batch.fullname else {
      return
    }
    
    showRenameBatchAlert(withCurrentName: intialName, prohobitedNames: prohibitedNewBatchNames()) { [weak self] name, shortcut in
      guard let self = self else { return }
      
      batch.fullname = name
      batch.keyShortcut = shortcut
      CoreDataManager.shared.saveContext()
      
      replaceRegisteredHotKey(forRenamedBatch: batch)
      menu.renamedBatch(batch)
    } 
  }
  
  @IBAction
  func saveBatch(_ sender: AnyObject) {
    menu.cancelTrackingWithoutAnimation() // do this before any alerts appear
    saveBatch()
  }
  
  @discardableResult
  func saveBatch() -> Bool {
    guard !Self.busy else {
      return false
    }
    
    guard AppModel.allowSavedBatches else {
      showBonusFeaturePromotionAlert()
      return false
    }
    
    guard let batch = history.currentBatch, !batch.isEmpty else {
      return false
    }
    
    showSaveBatchAlert(showingCount: batch.count, prohobitedNames: prohibitedNewBatchNames()) { [weak self] name, shortcut in
      guard let self = self else { return }
      
      let newBatch = Batch.create(withName: name, shortcut: shortcut, clips: history.lastBatchClips)
      
      registerHotKeyHandler(forBatch: newBatch)
      menu.addedBatch(newBatch)
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
  
  func deleteHistoryClip(atIndex index: Int) {
    // index 0 is most recent clip
    guard !Self.busy else {
      return
    }
    guard index >= 0 && index < history.count else {
      return
    }
    
    history.remove(atIndex: index)
    
    menu.deletedClipFromHistory(index)
  }
  
  func deleteQueueClip(atIndex index: Int) {
    // index 0 is most recent clip
    guard !Self.busy else {
      return
    }
    guard index >= 0 && index < queue.size else {
      return
    }
    
    do {
      try queue.remove(atIndex: index)
    } catch {
      // was doing just `queue.off()` here but after that the menu
      // wouldn't be in sync, probably best to do nothing
      return
    }
    
    if !queue.isOn && history.isListActive {
      // removing has turned off the queue and its contents may have been added to the history
      history.trim(to: Self.effectiveMaxClips)
    }
    
    menu.deletedClipFromQueue(index)
    updateMenuIcon(.decrement)
    updateMenuTitle()
  }
  
  func deleteBatch(atIndex index: Int) {
    guard !Self.busy else {
      return
    }
    guard index >= 0 && index < history.batches.count else {
      return
    }
    let batch = history.batches[index]
    
    showDeleteBatchAlert(withTitle: history.batches[index].title ?? "") { [weak self] in
      guard let self = self else { return }
      
      unregisterHotKeyDefinition(forBatch: batch)
      history.removeSavedBatch(atIndex: index)
      menu.deletedBatch(index)
    }
  }
  
  func deleteBatchClip(atIndex subindex: Int, forBatchAtIndex index: Int) {
    guard !Self.busy else {
      return
    }
    guard index >= 0 && index < history.batches.count else {
      return
    }
    let batch = history.batches[index]
    
    batch.removeClip(atIndex: subindex)
    menu.deletedClip(subindex, fromBatch: index)
    
    // whan last clip is deleted then delete the whole batch, decided againt a confirmation alert 
    if batch.isEmpty {
      unregisterHotKeyDefinition(forBatch: batch)
      history.removeSavedBatch(atIndex: index)
      menu.deletedBatch(index)
    }
  }
  
  @IBAction
  func deleteHighlightedItem(_ sender: AnyObject) {
    if let batchItem = menu.highlightedBatchMenuItem(), let batch = batchItem.batch {
      if let index = history.batches.firstIndex(of: batch) { // do nothing if cannot find the batch
        if let highlightedSubitem = batchItem.submenu?.highlightedItem { // only delete the batch itself if no submenu selection
          if let clip = (highlightedSubitem as? ClipMenuItem)?.clip, let subindex = batch.getClipsArray().firstIndex(of: clip) {
            deleteBatchClip(atIndex: subindex, forBatchAtIndex: index)
          }
        } else {
          deleteBatch(atIndex: index)
        }
      }
    } else if let clip = menu.highlightedClipMenuItem()?.clip {
      if let index = history.all.firstIndex(of: clip) {
        deleteHistoryClip(atIndex: index)
      } else if let index = queue.clips.firstIndex(of: clip) {
        deleteQueueClip(atIndex: index)
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
  
  func clearHistory(suppressClearAlert: Bool, clipboardIncluded: Bool = false) {
    if suppressClearAlert {
      deleteClips(clipboardIncluded: clipboardIncluded)
    } else {
      showClearHistoryAlert() { [weak self] in
        self?.deleteClips(clipboardIncluded: clipboardIncluded)
      }
    }
  }
  
  private func deleteClips(clipboardIncluded: Bool = false) {
    do {
      try queue.clear()
    } catch {
      os_log(.default, "ignoring error from turning off queue %@", "\(error)")
    }
    history.clearHistory()
    menu.deletedHistory()
    if clipboardIncluded {
      clipboard.clear()
    }
    updateMenuIcon()
    updateMenuTitle()
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
        return
      }
      
      if !queue.isOn && history.isListActive {
        // removing has turned off the queue and contents may have been added to the history
        history.trim(to: Self.effectiveMaxClips)
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
  
  private func sanityCheckStatusItem() {
    #if false // DEBUG
    // swiftlint:disable force_cast
    os_log(.debug, "NSStatusItem = %@, isVisible = %d, UserDefaults showInStatusBar = %d, AppModel = %@, ProxyMenu = %@",
           menuIcon.statusItem, menuIcon.statusItem.isVisible, UserDefaults.standard.showInStatusBar,
           (NSApp.delegate as! AppDelegate).model!, (NSApp.delegate as! AppDelegate).model!.menuController!.proxyMenu)
    // swiftlint:enable force_cast
    #endif
  }
  
  // MARK: - alert details
  
  func showNumberToPasteAlert(_ completion: @escaping (Int, String?) -> Void) {
    takeFocus()
    
    var lastSeparator = Alerts.SeparatorChoice.none
    if UserDefaults.standard.object(forKey: "lastPasteSeparatorIndex") != nil {
      let index = UserDefaults.standard.integer(forKey: "lastPasteSeparatorIndex")
      if let value = PasteSeparator(rawValue: index) {
        lastSeparator = .builtIn(value)
      }
    } else if let title = UserDefaults.standard.string(forKey: "lastPasteSeparatorTitle") {
      lastSeparator = .addOn(title)
    }
    alerts.withNumberToPasteAlert(maxValue: queue.size, separatorDefault: lastSeparator) { [weak self] num, choise in
      guard let self = self else { return }
      if let num = num {
        var seperator: String?
        switch choise {
        case .builtIn(let selection):
          seperator = selection.string
          UserDefaults.standard.set(selection.rawValue, forKey: "lastPasteSeparatorIndex")
          UserDefaults.standard.removeObject(forKey: "lastPasteSeparatorTitle")
        case .addOn(let title):
          seperator = title
          UserDefaults.standard.set(title, forKey: "lastPasteSeparatorTitle")
          UserDefaults.standard.removeObject(forKey: "lastPasteSeparatorIndex")
        default:
          seperator = nil
          UserDefaults.standard.removeObject(forKey: "lastPasteSeparatorIndex")
          UserDefaults.standard.removeObject(forKey: "lastPasteSeparatorTitle")
        }
        completion(num, seperator)
      }
      
      returnFocus()
    } 
  }
  
  private func showClearHistoryAlert(_ completion: @escaping () -> Void) {
    if UserDefaults.standard.suppressClearAlert {
      completion()
      
    } else {
      takeFocus()
      
      alerts.withClearAlert() { [weak self] confirm, dontAskAgain in
        guard let self = self else { return }
        if confirm {
          completion()
          
          if dontAskAgain {
            UserDefaults.standard.suppressClearAlert = true
          }
        }
        
        returnFocus()
      }
    }
  }
  
  private func showBonusFeaturePromotionAlert() {
    takeFocus()
    
    alerts.withBonusFeaturePromotionAlert() { [weak self] confirm in
      guard let self = self else { return }
      if confirm {
        showSettings(selectingPane: .purchase)
      }
      
      returnFocus()
    }
  }
  
  private func showSaveBatchAlert(showingCount count: Int, prohobitedNames: Set<String>,
                                  _ completion: @escaping (String, HotKeyShortcut?) -> Void) {
    takeFocus()
    
    alerts.withSaveBatchAlert(forCurrentBatch: queue.isOn, showingCount: count,
                              excludingNames: prohobitedNames) { [weak self] name, shortcut in
      guard let self = self else { return }
      if let name = name {
        completion(name, shortcut)
      }
      
      returnFocus()
    }
  }
  
  private func showRenameBatchAlert(withCurrentName currentName: String, prohobitedNames: Set<String>,
                                    _ completion: @escaping (String, HotKeyShortcut?) -> Void) {
    takeFocus()
    
    alerts.withRenameBatchAlert(withCurrentName: currentName,
                                excludingNames: prohobitedNames) { [weak self]  name, shortcut in
      guard let self = self else { return }
      if name != nil || shortcut != nil {
        completion(name ?? currentName, shortcut)
      }
      
      returnFocus()
    }
  }
  
  private func showDeleteBatchAlert(withTitle title: String, _ completion: @escaping () -> Void) {
    if true { // UserDefaults.standard.suppressDeleteBatchAlert {
      completion()
      
    } else {
      takeFocus()
      
      alerts.withDeleteBatchAlert(withTitle: title) { [weak self] confirm, dontAskAgain in
        guard let self = self else { return }
        if confirm {
          completion()
          
          if dontAskAgain {
            UserDefaults.standard.suppressDeleteBatchAlert = true
          }
        }
        
        returnFocus()
      }
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
      takeFocus()
      
      alerts.withPermissionAlert() { [weak self] response in
        switch response {
        case .openSettings:
          self?.openSecurityPanel()
        case .openIntro:
          self?.showIntroAtPermissionPage()
        default:
          break
        }
        
        self?.returnFocus()
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
        history.clearHistory()
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
// swiftlint:enable file_length
