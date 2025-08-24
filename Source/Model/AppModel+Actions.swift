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
  private var copyIntentDelaySeconds: Double { 0.25 }
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
  
  // MARK: - intent helpers
  
  func historyItemCount() -> Int {
    return history.count
  }
  
  func historyItem(at historyIntentIdx: Int) -> Clip? {
    let index = historyIntentIdx - 1
    guard index >= 0 && index < history.count else {
      return nil
    }
    return history.all[index]
  }
  
  func deleteHistoryItem(at historyIntentIdx: Int) -> Clip? {
    let index = historyIntentIdx - 1
    guard index >= 0 && index < history.count else {
      return nil
    }
    let clip = history.all[index]
    deleteHistoryClip(atIndex: index)
    return clip
  }
  
  func replayFromHistory(at historyIntentIdx: Int) -> Bool {
    let index = historyIntentIdx - 1
    guard index >= 0 && index < history.count else {
      return false
    }
    return replayFromHistory(atIndex: index, interactive: false)
  }
  
  func queueItemCount() -> Int {
    return queue.size
  }
  
  func queueItem(at queueIntentIdx: Int) -> Clip? {
    let index = queue.size - queueIntentIdx
    guard index >= 0 && index < queue.size else {
      return nil
    }
    return queue.clips[index]
  }
  
  func deleteQueueItem(at queueIntentIdx: Int) -> Clip? {
    let index = queue.size - queueIntentIdx
    guard index >= 0 && index < queue.size else {
      return nil
    }
    let clip = queue.clips[index]
    deleteQueueClip(atIndex: index)
    return clip
  }
  
  func replayQueue() -> Bool {
    return replayBatch(nil, interactive: false)
  }
  
  func savedBatchCount() -> Int {
    return history.batches.count
  }
  
  func batchTitle(at batchIntentIdx: Int) -> String? {
    let batchIndex = batchIntentIdx - 1
    let batches = history.batches
    guard batchIndex >= 0 && batchIndex < batches.count else { return nil }
    return batches[batchIndex].fullname ?? ""
  }
  
  func savedBatchItemCount(at batchIntentIdx: Int) -> Int {
    let batchIndex = batchIntentIdx - 1
    let batches = history.batches
    guard batchIndex >= 0 && batchIndex < batches.count else { return 0 }
    return batches[batchIndex].count
  }
  
  func getFromBatch(at batchIntentIdx: Int, clipItemAt clipsIntentIdx: Int) -> Clip? {
    let batchIndex = batchIntentIdx - 1
    let batches = history.batches
    guard batchIndex >= 0 && batchIndex < batches.count else { return nil }
    let batch = batches[batchIndex]
    let clipIndex = batch.count - clipsIntentIdx
    guard clipIndex >= 0 && clipIndex < batch.count else { return nil }
    return batch.getClipsArray()[clipIndex]
  }
  
  func deleteFromBatch(at batchIntentIdx: Int, clipItemAt clipsIntentIdx: Int) -> Clip? {
    let batchIndex = batchIntentIdx - 1
    let batches = history.batches
    guard batchIndex >= 0 && batchIndex < batches.count else { return nil }
    let batch = batches[batchIndex]
    let clipIndex = batch.count - clipsIntentIdx
    guard let clip = batch.clipAtIndex(clipIndex) else { return nil }
    batch.removeClip(atIndex: clipIndex)
    return clip
  }
  
  func deleteBatch(at batchIntentIdx: Int) -> String? {
    let batchIndex = batchIntentIdx - 1
    let batches = history.batches
    guard batchIndex >= 0 && batchIndex < batches.count else { return nil }
    let title = batches[batchIndex].fullname ?? ""
    deleteBatch(atIndex: batchIndex)
    return title
  }
  
  func replayBatch(at batchIntentIdx: Int) -> Bool {
    let batchIndex = batchIntentIdx - 1
    let batches = history.batches
    guard batchIndex >= 0 && batchIndex < batches.count else { return false }
    return replayBatch(batches[batchIndex], interactive: false)
  }
  
  func replayBatch(named name: String) -> Bool {
    guard let batch = history.batches.first(where: { $0.fullname?.caseInsensitiveCompare(name) == .orderedSame }) else {
      return false
    }
    return replayBatch(batch, interactive: false)
  }
  
  func indexOfBatch(named name: String) -> Int? {
    guard let index = history.batches.firstIndex(where: { $0.fullname?.caseInsensitiveCompare(name) == .orderedSame }) else {
      return nil
    }
    return index
  }
  
  func putClipOnClipboard(_ clip: Clip) {
    clipboard.copy(clip)
  }
  
  func pasteSequentialItems(count: Int, separator: String, completion: @escaping (Bool) -> Void) -> Bool {
    let num = count > 0 && count <= queue.size ? count : queue.size
    return queuedPasteMultiple(num, separator: separator.isEmpty ? nil : separator, interactive: false, completion: completion)
  }
  
  func performQueuedCopy(completion: @escaping (Bool) -> Void) -> Bool {
    guard queuedCopy(interactive: false) else {
      return false
    }
    // fake a wait for completion, always calling with success=true after a fixed delay,
    // as there isn't a good way to hook this up to the clipboardChanged callback
    DispatchQueue.main.asyncAfter(deadline: .now() + copyIntentDelaySeconds) {
      completion(true)
    }
    return true
  }
  
  func performQueuedPaste(completion: @escaping (Bool) -> Void) -> Bool {
    return queuedPaste(interactive: false, completion: completion)
  }
  
  // MARK: - clipboard features
  
  @IBAction
  func startQueueMode(_ sender: AnyObject) {
    // handler for the menu item
    menu.cancelTrackingWithoutAnimation() // do this before any alerts appear
    startQueueMode(interactive: true)
  }
  
  func startQueueMode() {
    // handler for the global keyboard shortcut
    startQueueMode(interactive: true)
  }
  
  @discardableResult
  func startQueueMode(interactive: Bool = false) -> Bool {
    // handler for the global keyboard shortcut and menu item via functions above,
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
    ensureMenuIconVisible()
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
    letMenuIconAutoHide()
    updateClipboardMonitoring()
    
    return true
  }
  
  @IBAction
  func startReplay(_ sender: AnyObject) {
    startReplay()
  }
  
  @discardableResult
  func startReplay() -> Bool {
    do {
      try queue.replaying()
      return true
    } catch {
      return false
    }
  }
  
  @IBAction
  func queuedCopy(_ sender: AnyObject) {
    // handler for the menu item
    menu.cancelTrackingWithoutAnimation() // do this before any alerts appear
    queuedCopy(interactive: true)
  }
  
  func queuedCopy() {
    // handler for the global keyboard shortcut
    queuedCopy(interactive: true)
  }
  
  @discardableResult
  func queuedCopy(interactive: Bool = false) -> Bool {
    // handler for the global keyboard shortcut and menu item via functions above,
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
      ensureMenuIconVisible()
      updateMenuIcon()
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
      // perhaps assert the busy flag is set here? better to not change the flag if the timer expired,
      // although its a shared timer just like the flag so its not really much better
      
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
    // handler for the menu item
    menu.cancelTrackingWithoutAnimation() // do this before any alerts appear
    queuedPaste(interactive: true)
  }
  
  func queuedPaste() {
    // handler for the global keyboard shortcut
    queuedPaste(interactive: true)
  }
  
  @discardableResult
  func queuedPaste(interactive: Bool = false, completion: ((Bool) -> Void)? = nil) -> Bool {
    // handler for the global keyboard shortcut and menu item via functions above,
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
      guard let self = self else {
        completion?(false)
        return
      }
      
      do {
        try self.queue.dequeue()
      } catch {
        Self.busy = false
        completion?(false)
        return
      }
      
      if !queue.isOn && history.isListActive {
        // dequeuing has turned off the queue and its contents may have been added to the history
        history.trim(to: Self.effectiveMaxClips)
      }
      
      menu.poppedClipOffQueue()
      updateMenuIcon(.decrement)
      updateMenuTitle()
      if !queue.isOn {
        letMenuIconAutoHide()
      }
      updateClipboardMonitoring()
      
      Self.busy = false
      
      #if APP_STORE
      if interactive && !queue.isOn {
        AppStoreReview.ask(after: 20)
      }
      #endif
      
      completion?(true)
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
    doQueuedPasteMultiple(all: false)
  }
  
  @IBAction
  func queuedPasteAll(_ sender: AnyObject) {
    menu.cancelTrackingWithoutAnimation() // do this before any alerts appear
    doQueuedPasteMultiple(all: true)
  }
  
  private func doQueuedPasteMultiple(all: Bool) {
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
    // this is done in the full queuedPasteMultiple below, but do it here first with interactive true
    // so the potential alert happens before the other alert below asking for count and separator
    guard accessibilityCheck(interactive: true) else {
      return
    }
    
    // interactive=false used below because the interactive part, the accessibilityCheck call
    // and optionally the number & separator alert, have already been done
    
    if all {
      queuedPasteMultiple(queue.size, interactive: false)
      
    } else {
      showNumberToPasteAlert { number, separatorStr in
        self.queuedPasteMultiple(number, separator: separatorStr, interactive: false)
      }
    }
  }
  
  @discardableResult
  private func queuedPasteMultiple(_ count: Int, separator: String? = nil, interactive: Bool = false,
                                   completion: ((Bool) -> Void)? = nil) -> Bool {
    guard !Self.busy else {
      return false
    }
    guard count >= 1 && count <= queue.size else {
      return false
    }
    if count == 1 {
      return queuedPaste(interactive: interactive)
    }
    
    guard accessibilityCheck(interactive: interactive) else {
      return false
    }
    
    do {
      try queue.replaying() // ensures queue head is on the clipboard
    } catch {
      return false
    }
    
    Self.busy = true
    
    // menu icon will show "-" for the duration
    updateMenuIcon(.persistentDecrement)
    
    queuedPasteMultipleIterator(to: count, withSeparator: separator) { [weak self] pastedCount in
      guard let self = self else {
        completion?(false)
        return
      }
      var success = (pastedCount == count)
      
      do {
        try queue.finishBulkDequeue()
      } catch {
        // clipboard might be in wrong state, otherwise presume continuing
        // should be the most correct thing
        success = false
      }
      
      if !queue.isOn && history.isListActive {
        // dequeuing has turned off the queue and its contents may have been added to the history
        history.trim(to: Self.effectiveMaxClips)
      }
      
      // final update to these and including icon not updated since the start
      menu.poppedClipsOffQueue(count)
      updateMenuIcon()
      updateMenuTitle()
      if !queue.isOn {
        letMenuIconAutoHide()
      }
      updateClipboardMonitoring()
      
      Self.busy = false
      
      completion?(success)
      
      #if APP_STORE
      if !queue.isOn && interactive {
        AppStoreReview.ask(after: 20)
      }
      #endif
    }
    
    return true
  }
  
  private func queuedPasteMultipleIterator(increment count: Int = 0, to max: Int, withSeparator separator: String?,
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
      
      if let separator = separator, !separator.isEmpty {
        // paste the separator between clips
        clipboard.copy(separator)
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
        queuedPasteMultipleIterator(increment: nextCount, to: max, withSeparator: separator, then: completion)
      }
    }
  }
  
  @IBAction
  func advanceQueue(_ sender: AnyObject) {
    advanceQueue()
  }
  
  @discardableResult
  func advanceQueue() -> Bool {
    guard !Self.busy else {
      return false
    }
    
    guard !queue.isEmpty else {
      return false
    }
    
    do {
      try queue.replaying()
    } catch {
      return false
    }
    
    do {
      try self.queue.dequeue()
    } catch {
      return false
    }
    
    if !queue.isOn && history.isListActive {
      // dequeuing has turned off the queue and its contents may have been added to the history
      history.trim(to: Self.effectiveMaxClips)
    }
    
    menu.poppedClipOffQueue()
    updateMenuIcon(.decrement)
    updateMenuTitle()
    if !queue.isOn {
      letMenuIconAutoHide()
    }
    updateClipboardMonitoring()
    
    return true
  }
  
  @IBAction
  func copyClip(_ sender: AnyObject) {
    guard let clip = (sender as? ClipMenuItem)?.clip else {
      return
    }
    copyClip(clip)
  }
  
  @discardableResult
  func copyClip(_ clip: Clip) -> Bool {
    guard !Self.busy else {
      return false
    }
    
    clipboard.copy(clip)
    return true
  }
  
  @IBAction
  func replayFromHistory(_ sender: AnyObject) {
    // by-pass the replay feature if its not supported, make just like a normal select/click
    if !AppModel.allowReplayFromHistory {
      copyClip(sender)
      return
    }
    
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
    guard accessibilityCheck(interactive: interactive) else {
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
      try queue.replayClips(clips)
      try queue.replaying()
    } catch {
      return false
    }
    
    menu.startedQueueFromHistory(index)
    ensureMenuIconVisible()
    updateMenuIcon()
    updateMenuTitle()
    commenceClipboardMonitoring()
    
    return true
  }
  
  @IBAction
  func replayLastBatch(_ sender: AnyObject) {
    menu.cancelTrackingWithoutAnimation()
    replayBatch(nil, interactive: true)
  }
  
  func replayLastBatch() {
    // handler for the global keyboard shortcut
    replayBatch(nil, interactive: true)
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
    // handler for the global keyboard shortcut
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
    if let batch = batch {
      guard !batch.isEmpty else {
        return false
      }
    } else {
      guard !queue.isBatchEmpty else {
        return false
      }
    }
    
    do {
      if let batch = batch {
        try queue.replayClips(batch.getClipsArray())
      } else {
        try queue.replayQueue()
      }
      try queue.replaying()
    } catch {
      return false
    }
    
    menu.startedQueueFromBatch()
    ensureMenuIconVisible()
    updateMenuIcon()
    updateMenuTitle()
    commenceClipboardMonitoring()
    
    return true
  }
  
  @IBAction
  func renameSavedBatch(_ sender: AnyObject) {
    menu.cancelTrackingWithoutAnimation() // do this before any alerts appear
    guard !Self.busy else {
      return
    }
    
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
    guard !Self.busy else {
      return
    }
    
    guard AppModel.allowSavedBatches else {
      showBonusFeaturePromotionAlert()
      return
    }
    
    guard let batch = history.currentBatch, !batch.isEmpty else {
      return
    }
    
    showSaveBatchAlert(showingCount: batch.count, prohobitedNames: prohibitedNewBatchNames()) { [weak self] name, shortcut in
      guard let self = self else { return }
      
      let newBatch = Batch.create(withName: name, shortcut: shortcut, clips: history.lastBatchClips)
      
      registerHotKeyHandler(forBatch: newBatch)
      menu.addedBatch(newBatch)
    }
  }
  
  @discardableResult
  func saveBatch(withName name: String) -> Bool {
    // callable from intent
    guard !Self.busy else {
      return false
    }
    guard prohibitedNewBatchNames().contains(name) == false else {
      return false
    }
    
    let newBatch = Batch.create(withName: name, shortcut: nil, clips: history.lastBatchClips)
    
    registerHotKeyHandler(forBatch: newBatch)
    menu.addedBatch(newBatch)
    
    return true
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
    if !queue.isOn {
      letMenuIconAutoHide()
    }
    updateClipboardMonitoring()
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
    menu.cancelTrackingWithoutAnimation() // do this before any alerts appear
    clearHistory(interactive: true)
  }
  
  func clearHistory(clipboardIncluded: Bool = false, interactive: Bool = false) {
    guard !Self.busy else {
      return
    }
    
    if !interactive {
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
    letMenuIconAutoHide()
    updateClipboardMonitoring()
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
  
  @IBAction
  func installUpdate(_ sender: AnyObject) {
    #if SPARKLE_UPDATES
    updaterController.updater.checkForUpdates()
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
        var separator: String?
        switch choise {
        case .builtIn(let selection):
          separator = selection.string
          UserDefaults.standard.set(selection.rawValue, forKey: "lastPasteSeparatorIndex")
          UserDefaults.standard.removeObject(forKey: "lastPasteSeparatorTitle")
        case .addOn(let title):
          separator = title
          UserDefaults.standard.set(title, forKey: "lastPasteSeparatorTitle")
          UserDefaults.standard.removeObject(forKey: "lastPasteSeparatorIndex")
        default:
          separator = nil
          UserDefaults.standard.removeObject(forKey: "lastPasteSeparatorIndex")
          UserDefaults.standard.removeObject(forKey: "lastPasteSeparatorTitle")
        }
        completion(num, separator)
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
  
  private func accessibilityCheck(interactive: Bool) -> Bool {
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
          self?.ensureMenuIconVisible(pollingForWindowsToClose: true)
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
    }
    if UserDefaults.standard.ignoreEvents {
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
    copyTimeoutTimer?.cancel()
    copyTimeoutTimer = DispatchSource.scheduledTimerForRunningOnMainQueue(afterDelay: timeout) { [weak self] in
      self?.copyTimeoutTimer = nil // doing this before calling closure supports closure itself calling runOnCopyTimeoutTimer, fwiw
      action()
    }
  }
  
  private func cancelCopyTimeoutTimer() {
    copyTimeoutTimer?.cancel()
    copyTimeoutTimer = nil
  }
  
  private func sanityCheckStatusItem() {
    #if DEBUG
    // swiftlint:disable force_cast
    os_log(.debug, "NSStatusItem = %@, isVisible = %d, UserDefaults showInStatusBar = %d, AppModel = %@, ProxyMenu = %@",
           menuIcon.statusItem, menuIcon.statusItem.isVisible, UserDefaults.standard.showInStatusBar,
           (NSApp.delegate as! AppDelegate).model!, (NSApp.delegate as! AppDelegate).model!.menuController!.proxyMenu)
    // swiftlint:enable force_cast
    #endif
  }
  
}
// swiftlint:enable file_length
