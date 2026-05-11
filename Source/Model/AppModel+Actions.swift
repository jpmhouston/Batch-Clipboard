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
  
  private var canStartQueue: Bool { queue.isOff && stack.isOff }
  private var canAddToQueue: Bool { stack.isOff }
  private var canCancelQueue: Bool { queue.isOn }
  private var shouldQueueNewClip: Bool { queue.isOn && stack.isOff }
  private var canPasteFromQueue: Bool { queue.notEmpty && stack.isOff }
  private var canPopFromQueue: Bool { queue.notEmpty && stack.isOff }
  private var canStartDequeueing: Bool { queue.isOn && stack.isOff }
  private var canReplayQueue: Bool { queue.isOff && stack.isOff }
  private var canStartStack: Bool { stack.isOff }
  private var canPushToStack: Bool { true } // might disallow in some cases in the future, idk
  private var canPopFromStack: Bool { stack.notEmpty }
  
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
  func startStackMode(_ sender: AnyObject) {
    // handler for the menu item
    menu.cancelTrackingWithoutAnimation() // do this before any alerts appear
    startStackMode(interactive: true)
  }
  
  func startStackMode() {
    // handler for the global keyboard shortcut
    startStackMode(interactive: false)
  }
  
  @discardableResult
  func startStackMode(interactive: Bool = false) -> Bool {
    // handler for the global keyboard shortcut and menu item via functions above,
    // and for the intent which calls this directly
    guard !Self.busy else {
      return false
    }
    guard canStartStack else {
      return false
    }
    guard accessibilityCheck(interactive: interactive) else {
      return false
    }
    
    // push current clipboard state onto the stack, prepare for temp cut/copy
    stack.push()
    
    ensureMenuIconVisible()
    updateMenuTitle()
    commenceClipboardMonitoring()
    
    return true
  }
  
  @IBAction
  func stackCopy(_ sender: AnyObject) {
    // handler for the menu item
    menu.cancelTrackingWithoutAnimation() // do this before any alerts appear
    stackCopy(interactive: true)
  }
  
  func stackCopy() {
    // handler for the global keyboard shortcut
    stackCopy(interactive: false)
  }
  
  @discardableResult
  func stackCopy(interactive: Bool = false) -> Bool {
    // handler for the global keyboard shortcut and menu item via functions above,
    // and for the intent which calls this directly
    guard !Self.busy else {
      return false
    }
    guard canPushToStack else {
      return false
    }
    guard accessibilityCheck(interactive: interactive) else {
      return false
    }
    
    nop() // TODO: remove once no longer need a breakpoint here
    
    // push current clipboard state onto the stack, prepare for temp cut/copy
    stack.push()
    
    ensureMenuIconVisible()
    updateMenuIcon()
    updateMenuTitle()
    
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
  
  @IBAction
  func stackPaste(_ sender: AnyObject) {
    // handler for the menu item
    menu.cancelTrackingWithoutAnimation() // do this before any alerts appear
    stackPaste(interactive: true)
  }
  
  @discardableResult
  func stackPaste(interactive: Bool = false, completion: ((Bool) -> Void)? = nil) -> Bool {
    // handler for the global keyboard shortcut and menu item via function above
    // (well, the shortcut is doubled up with the queue paste shortcut, calling this when stack in use),
    // and for the intent which calls this directly
    guard !Self.busy else {
      return false
    }
    guard canPopFromStack else {
      return false
    }
    guard accessibilityCheck(interactive: interactive) else {
      return false
    }
    
    Self.busy = true
    
    let popStackDelay = extraDelayOnQueuedPaste ? extraPasteDelay : standardPasteDelay
    
    // make the frontmost application perform a paste, then advance the queue after our
    // heuristic delay, keep the app from doing anything else until them
    invokeApplicationPaste(plusDelay: popStackDelay) { [weak self] in
      guard let self = self else {
        completion?(false)
        return
      }
      
      stack.pop()
      
      Self.busy = false
      
      updateMenuIcon()
      updateMenuTitle()
      if stack.isOff && queue.isOff {
        letMenuIconAutoHide()
      }
      updateClipboardMonitoring()
      
      #if APP_STORE
      if interactive && stack.isOff {
        AppStoreReview.ask(after: 20)
      }
      #endif
      
      completion?(true)
    }
    
    return true
  }
  
  @IBAction
  func popStack(_ sender: AnyObject) {
    // handler for the menu item
    popStack()
  }
  
  @discardableResult
  func popStack() -> Bool {
    guard !Self.busy else {
      return false
    }
    guard canPopFromStack else {
      return false
    }
    
    stack.pop()
    
    updateMenuIcon()
    updateMenuTitle()
    if stack.isOff && queue.isOff {
      letMenuIconAutoHide()
    }
    updateClipboardMonitoring()
    
    return true
  }
  
  // stack ↑ queue ↓
  
  @IBAction
  func startQueueMode(_ sender: AnyObject) {
    // handler for the menu item
    menu.cancelTrackingWithoutAnimation() // do this before any alerts appear
    startQueueMode(interactive: true)
  }
  
  @IBAction
  func startQueueModeWithCurrentClip(_ sender: AnyObject) {
    // handler for the menu item
    menu.cancelTrackingWithoutAnimation() // do this before any alerts appear
    startQueueMode(withCurrentClip: true, interactive: true)
  }
  
  func startQueueMode() {
    // handler for the global keyboard shortcut
    startQueueMode(interactive: true)
  }
  
  func startQueueModeWithCurrentClip() {
    // handler for the global keyboard shortcut
    startQueueMode(withCurrentClip: true, interactive: true)
  }
  
  @discardableResult
  func startQueueMode(withCurrentClip addCurrentClip: Bool = false, interactive: Bool = false) -> Bool {
    // handler for the global keyboard shortcut and menu item via functions above,
    // and for the intent which calls this directly
    
    // when starting from current clip and using history, use replayFromHistory technique instead of the code below
    // normally only permitted when `allowReplayFromHistory`, but an exception is made for this feature
    if addCurrentClip && history.isListActive && history.count > 0, let clip = history.clipAtIndex(0) {
      if clipboard.currentMatchesClip(clip) {
        return replayFromHistory(atIndex: 0, overridePermission: true, interactive: interactive)
      }
      os_log(.error, "clipboard doesn't match first history clip!\n%s\n  vs:\n%s", clipboard.currentContents().map({ $0.type }).joined(separator: ","),
             clip.types.map({ $0.rawValue }).joined(separator: ","))
    }
    
    guard !Self.busy else {
      return false
    }
    guard canStartQueue else {
      return false
    }
    guard accessibilityCheck(interactive: interactive) else {
      return false
    }
    
    queue.on()
    ensureMenuIconVisible()
    menuIcon.update(forQueueSize: 0)
    
    if addCurrentClip && !clipboard.isEmpty, let clip = clipboard.newClipFromCurrent() {
      do {
        try queue.add(clip)
        menu.addedClipToQueue(clip)
        updateMenuIcon(.increment)
      } catch {
        // maybe do something to remove `clip` from coredata?
        updateMenuIcon()
      }
    }
    
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
    guard canCancelQueue else {
      return false
    }
    
    let count = queue.size
    
    do {
      try queue.off()
    } catch {
      os_log(.default, "ignoring error from turning off queue %@", "\(error)")
    }
    
    menu.cancelledQueue(count)
    updateMenuIcon()
    updateMenuTitle()
    letMenuIconAutoHide()
    updateClipboardMonitoring()
    
    return true
  }
  
  @discardableResult
  func toggleQueueMode() -> Bool {
    if canStartQueue {
      return startQueueMode(interactive: true)
    } else if canCancelQueue{
      return cancelQueueMode()
    } else {
      return false
    }
  }
  
  @IBAction
  func startReplay(_ sender: AnyObject) {
    startReplay()
  }
  
  @discardableResult
  func startReplay() -> Bool {
    guard canStartDequeueing else {
      return false
    }
    
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
    guard canStartQueue || canAddToQueue else {
      return false
    }
    guard accessibilityCheck(interactive: interactive) else {
      return false
    }
    
    nop() // TODO: remove once no longer need a breakpoint here
    
    if queue.isOff {
      queue.on()
      ensureMenuIconVisible()
      updateMenuIcon()
    }
    
    commenceClipboardMonitoring()
    
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
    
    #if DEBUG
    // temporary to exercise `currentMatchesClip`, remove once test cases for it added
    if clipboard.currentMatchesClip(clip) == false {
      os_log(.error, "clipboard doesn't match clip just taken from it!\n%s\n  vs:\n%s", clipboard.currentContents().map({ $0.type }).joined(separator: ","),
             clip.types.map({ $0.rawValue }).joined(separator: ","))
    }
//    else {
//      os_log(.debug, "clipboard matches clip just taken from it as expected :)\n%s", clip.types.map({ $0.rawValue }).joined(separator: ","))
//    }
    #endif
    
    if shouldQueueNewClip {
      do {
        try queue.add(clip)
      } catch {
        return
      }
      
      menu.addedClipToQueue(clip)
      updateMenuIcon(.increment)
      updateMenuTitle()
    }
    
    history.add(clip)
    history.trim(to: Self.effectiveMaxClips)
    
    menu.addedClipToHistory(clip)
  }
  
  @IBAction
  func queuedPaste(_ sender: AnyObject) {
    // handler for the menu item
    menu.cancelTrackingWithoutAnimation() // do this before any alerts appear
    queuedPaste(interactive: true)
  }
  
  func queuedPaste() {
    // handler for the global keyboard shortcut - shared for both queue & stack paste
    if stack.isOn {
      stackPaste(interactive: true)
    } else {
      queuedPaste(interactive: true)
    }
  }
  
  @discardableResult
  func queuedPaste(interactive: Bool = false, completion: ((Bool) -> Void)? = nil) -> Bool {
    // handler for the global keyboard shortcut and menu item via functions above,
    // and for the intent which calls this directly
    guard !Self.busy else {
      return false
    }
    guard canPasteFromQueue else {
      return false
    }
    guard accessibilityCheck(interactive: interactive) else {
      return false
    }
    
    nop() // TODO: remove once no longer need a breakpoint here
    
    do {
      if queue.notReplaying {
        try queue.replaying()
      } else {
        try queue.putNextOnClipboard()
      }
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
        try queue.dequeue()
      } catch {
        Self.busy = false
        completion?(false)
        return
      }
      
      Self.busy = false
      
      menu.poppedClipOffQueue()
      updateMenuIcon(.decrement)
      updateMenuTitle()
      if queue.isOff {
        letMenuIconAutoHide()
      }
      updateClipboardMonitoring()
      
      #if APP_STORE
      if interactive && queue.isOff {
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
  func advanceQueue(_ sender: AnyObject) {
    advanceQueue()
  }
  
  @discardableResult
  func advanceQueue() -> Bool {
    guard !Self.busy else {
      return false
    }
    guard canPopFromQueue else {
      return false
    }
    
    nop() // TODO: remove once no longer need a breakpoint here
    
    do {
      if queue.notReplaying {
        try queue.replaying()
      } else {
        try queue.putNextOnClipboard()
      }
      try self.queue.dequeue()
    } catch {
      return false
    }
    
    menu.poppedClipOffQueue()
    updateMenuIcon(.decrement)
    updateMenuTitle()
    if queue.isOff {
      letMenuIconAutoHide()
    }
    updateClipboardMonitoring()
    
    return true
  }
  
  // multi-queued paste ↓ 
  
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
  
  func queuedPasteMultiple() {
    // handler for the global keyboard shortcut
    doQueuedPasteMultiple(all: false)
  }
  
  private func doQueuedPasteMultiple(all: Bool) {
    guard !Self.busy else {
      return
    }
    guard canPasteFromQueue else {
      return
    }
    
    guard AppModel.allowPasteMultiple else {
      showBonusFeaturePromotionAlert()
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
    guard canPasteFromQueue && count >= 1 && count <= queue.size else {
      return false
    }
    if count == 1 {
      return queuedPaste(interactive: interactive)
    }
    
    guard accessibilityCheck(interactive: interactive) else {
      return false
    }
    
    do {
      if queue.notReplaying {
        try queue.replaying()
      } else {
        try queue.putNextOnClipboard()
      }
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
      
      Self.busy = false
      
      // final update to these and including icon not updated since the start
      menu.poppedClipsOffQueue(count)
      updateMenuIcon()
      updateMenuTitle()
      if queue.isOff {
        letMenuIconAutoHide()
      }
      updateClipboardMonitoring()
      
      completion?(success)
      
      #if APP_STORE
      if queue.isOff && interactive {
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
  
  // misc queue actions ↓
  
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
  func undoLastCopy(_ sender: AnyObject) {
    guard !Self.busy else {
      return
    }
    
    guard AppModel.allowUndoCopy else {
      showBonusFeaturePromotionAlert()
      return
    }
    
    // can only reliably do this when queue or history are on
    // trust that this menu item get disabled otherwise
    
    if canPopFromQueue {
      do {
        try queue.remove(atIndex: 0) // automatically restores clipboard to prev if appropriate
      } catch {
        return
      }
      
      menu.deletedClipFromQueue(0)
      updateMenuIcon(.decrement)
      updateMenuTitle()
    }
    
    if history.isListActive, let clip = history.first {
      history.remove(clip)
      
      menu.deletedClipFromHistory(0)
      
      if canPopFromStack, let newClip = history.first, newClip == stack.top {
        stack.pop(ontoClipboard: false)
      }
    }
    
    // maybe this, pop from stack even though possibly not always correct since user might
    // have copied several items since pushing to the stack (it's an else to the history case
    // above because then can more exactly determine if its correct to pop or not):
    //else if canPopFromStack {
    //  stack.pop()
    //}
  }
  
  // replays ↓
  
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
  func replayFromHistory(atIndex index: Int, overridePermission: Bool = false, interactive: Bool = false) -> Bool {
    guard !Self.busy else {
      return false
    }
    guard overridePermission || AppModel.allowReplayFromHistory else {
      return false
    }
    guard canReplayQueue && history.isListActive && index < history.count else {
      return false
    }
    guard accessibilityCheck(interactive: interactive) else {
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
  
  @IBAction
  func replaySavedBatchLooped(_ sender: AnyObject) {
    menu.cancelTrackingWithoutAnimation()
    guard let item = sender as? BatchMenuItem ?? BatchMenuItem.parentBatchMenuItem(for: sender), let batch = item.batch else {
      return
    }
    
    replayBatch(batch, looped: true, interactive: true)
  }
  
  @discardableResult
  func replayBatch(_ batch: Batch?, looped: Bool? = nil, interactive: Bool = false) -> Bool {
    guard !Self.busy else {
      return false
    }
    
    guard AppModel.allowReplayLastBatch else {
      if interactive {
        showBonusFeaturePromotionAlert()
      }
      return false
    }
    
    guard canReplayQueue else {
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
        try queue.replayClips(batch.getClipsArray(), repeatAfterDecrementToZero: looped ?? batch.repeating)
      } else {
        try queue.replayQueue(repeatAfterDecrementToZero: looped ?? false)
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
  
  // saved batches ↓
  
  @IBAction
  func editSavedBatch(_ sender: AnyObject) {
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
    
    showEditBatchAlert(withCurrentName: intialName, prohobitedNames: prohibitedNewBatchNames(),
                       repeating: batch.repeating) { [weak self] name, shortcut, repeating, delete in
      guard let self = self else { return }
      if delete {
        if let index = history.batches.firstIndex(of: batch) {
          // with confirmation alert:
          deleteBatch(atIndex: index)
          // or without confirmation alert:
          //unregisterHotKeyDefinition(forBatch: batch)
          //history.removeSavedBatch(atIndex: index)
          //menu.deletedBatch(index)
        }
        return
      }
      batch.fullname = name
      batch.keyShortcut = shortcut
      batch.repeating = repeating
      CoreDataManager.shared.saveContext()
      
      replaceRegisteredHotKey(forRenamedBatch: batch)
      menu.editedBatch(batch)
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
    
    nop() // TODO: remove once no longer need a breakpoint here
    
    showSaveBatchAlert(showingCount: batch.count, prohobitedNames: prohibitedNewBatchNames()) { [weak self] name, shortcut, repeating in
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
  
  // deleting clips ↓
  
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
    
    menu.deletedClipFromQueue(index)
    updateMenuIcon(.decrement)
    updateMenuTitle()
    if queue.isOff {
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
  
  // MARK: - opening windows
  
  @IBAction
  func showAbout(_ sender: AnyObject) {
    takeFocus()
    showSettings(selectingPane: .about)
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
    if settingsFirstOpen && pane == nil {
      settingsWindowController.show(pane: .general)
      settingsFirstOpen = false
    } else {
      settingsWindowController.show(pane: pane)
    }
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
                                  _ completion: @escaping (String, HotKeyShortcut?, Bool) -> Void) {
    takeFocus()
    
    let allowRepeat = AppModel.allowRepeatingBatch && UserDefaults.standard.showRepeatBatchDefaultOption
    alerts.withSaveBatchAlert(forCurrentBatch: queue.isOn, excludingNames: prohobitedNames, showingCount: count,
                              showingRepeat: allowRepeat) { [weak self] name, shortcut, repeating in
      guard let self = self else { return }
      if let name = name {
        completion(name, shortcut, repeating)
      }
      
      returnFocus()
    }
  }
  
  private func showEditBatchAlert(withCurrentName currentName: String, prohobitedNames: Set<String>, repeating: Bool,
                                  _ completion: @escaping (String, HotKeyShortcut?, Bool, Bool) -> Void) {
    takeFocus()
    
    let allowRepeat = AppModel.allowRepeatingBatch && UserDefaults.standard.showRepeatBatchDefaultOption
    alerts.withEditBatchAlert(withCurrentName: currentName, excludingNames: prohobitedNames,
                              repeating: allowRepeat ? repeating : nil) { [weak self]  name, shortcut, repeating, delete in
      guard let self = self else { return }
      if delete {
        completion(currentName, shortcut, false, true)
      } else {
        completion(name ?? currentName, shortcut, repeating, false)
      }
      
      returnFocus()
    }
  }
  
  private func showDeleteBatchAlert(withTitle title: String, _ completion: @escaping () -> Void) {
    if UserDefaults.standard.suppressDeleteBatchAlert {
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
    if stack.isOn {
      menuIcon.updateWithStackIcon()
    } else {
      menuIcon.update(forQueueSize: (queue.isOn ? queue.size : nil), direction)
    }
  }
  
  internal func updateMenuTitle() {
    if stack.isOn {
      menuIcon.badge = stack.size > 1 ? String(stack.size) : ""
    } else if queue.isOn {
      menuIcon.badge = String(queue.size)
    } else {
      menuIcon.badge = ""
    }
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
    if !UserDefaults.standard.keepHistory && queue.isOff {
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
