//
//  ClipboardQueue.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-05-20.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//
//  Layer on top of history providing queue primitives, also maintains
//  which item is on the clipboard after each call
//

import AppKit
import os.log

class ClipboardQueue {
  
  var isOn = false
  var isReplaying = false // stopped just queuing new clips and have started pasting
  var stayOnWhenEmptied = false
  var clipsAreNew = false // ie. not replayed from a batch
  var clearBatchPending = false
  
  var batch: Batch? { history.currentBatch }
  var batchClips: [Clip] { history.currentBatch?.getClipsArray() ?? [] }
  var clips: [Clip] { Array(batchClips.prefix(size)) }
  var size = 0
  var notEmpty: Bool { isOn && size > 0 }
  var isEmpty: Bool { !isOn || size == 0 }
  
  enum QueueError: Error {
    case logicError
    case noSuchItem
    case sizeOutOfSync
    case missingQueueBatch
    case cannotAccesQueueBatch
    case alreadyInProgress
  }
  
  //better if these were protocols that can be easily mocked
  private let clipboard: Clipboard
  private let history: History
  
  //private var internalSize = 0
  
  init(clipboard c: Clipboard, history h: History) {
    clipboard = c
    history = h
  }
  
  // MARK: -
  
  func on(allowStayingOnAfterDecrementToZero allowEmpty: Bool = false) {
    isOn = true
    isReplaying = false
    clipsAreNew = true
    stayOnWhenEmptied = allowEmpty
    clearBatchPending = false
    size = 0
    
    // erase the previous "last batch" once starting build a new one
    history.clearCurrentBatch()
  }
  
  func off() throws {
    guard isOn else {
      return
    }
    
    // In case pasteboard is currently set to an item deeper in the queue, reset to the latest clip copied.
    if isReplaying && size > 1 {
      try clipboard.copy(getNewest())
    }
    
    isOn = false
    size = 0
    
    // Cancelling the queue is one of the triggers to move clips into the history.
    if clipsAreNew && history.isListActive {
      try copyQueueToHistory()
    }
  }
  
  func clear() throws {
    isOn = false
    size = 0
    history.clearCurrentBatch()
  }
  
  func replaying() throws {
    if !isOn {
      on()
    }
    if !isReplaying {
      isReplaying = true
      try clipboard.copy(getNext())
    }
  }
  
  func putNextOnClipboard() throws {
    try clipboard.copy(getNext())
  }
  
  func add(_ clip: Clip) throws {
    if !isOn {
      on(allowStayingOnAfterDecrementToZero: false)
    }
    guard let batch = batch else {
      throw QueueError.missingQueueBatch
    }
    
    // A batch clear is pending when a paste empties it and stayOnWhenEmptied is true, we would clear
    // the batch right away but if the user isntead cancels queueing then prefer to leave the
    // batch at it's previous state rather than empty. This is because the current batch is used
    // as the "last batch" in the menu so the user can replay it.
    if size == 0 && clearBatchPending {
      history.clearCurrentBatch()
      clearBatchPending = false
    }
    
    batch.addClip(clip)
    
    size += 1
    
    guard size <= batch.count else {
      throw QueueError.sizeOutOfSync
    }
    
    // In replaying mode where always want next item to be pasted on the clipboard, presuming the item
    // passed in has come from the clipboard, replace it again with the next item to be pasted.
    // But if size of the queue is only 1, then we've already got the one we want for either mode.
    if isReplaying && size > 1 {
      try clipboard.copy(getNext())
    }
  }
  
  func dequeue() throws {
    guard !isEmpty else {
      throw QueueError.noSuchItem
    }
    
    size -= 1
    
    if isEmpty {
      // Emptying queue naturally (by pasting all the clips) is one of the triggers to move clips
      // into the history.
      if clipsAreNew && history.isListActive {
        try copyQueueToHistory()
      }
      
      isOn = stayOnWhenEmptied
      clearBatchPending = stayOnWhenEmptied
      
      // Want clipboard to be left at the latest item that's been copied. If this queue came
      // from newly copied clips then nothing to do because in either mode (replaying or not)
      // when down to the last clip then this one on the clipboard was indeed the last item copied.
      // But if the queue came from replaying a batch then only if history is on can we restore
      // the clip the user most recently copied.
      if !clipsAreNew && history.isListActive && history.count > 0, let clip = history.clipAtIndex(0) {
        clipboard.copy(clip)
      }
      
    } else if isReplaying {
      // In replaying mode where always leave the next item to be pasted on the clipboard.
      try clipboard.copy(getNext())
      
    } else if !isReplaying {
      // In normal mode where always leave the latest item that's been copied on the clipboard
      // (1.0 betas stayed like this even when pasting from the queue, still support that in
      // this abstraction, but the app always goes into replaying mode on the first paste)
      try clipboard.copy(getNewest())
    }
  }
  
  func remove(atIndex index: Int) throws {
    guard let batch = batch else {
      throw QueueError.missingQueueBatch
    }
    guard !isEmpty && index >= 0 && index < size else {
      throw QueueError.noSuchItem
    }
    let priorSize = size
    
    // Presume index passed in is ordered like the clip menu *used to be*, where most recent
    // is index 0 and counts up as it goes to the first copied / next pasted.
    batch.removeFromClips(at: index)
    
    size -= 1
    
    if isEmpty {
      // Emptying queue by deleting the last clip is one of the triggers to move clips
      // into the history
      if clipsAreNew && history.isListActive {
        try copyQueueToHistory()
      }
      
      isOn = stayOnWhenEmptied
      clearBatchPending = stayOnWhenEmptied
      
      // Want clipboard to be left at the latest item that's been copied. If this queue came
      // from newly copied clips then nothing to do because in either mode (replaying or not)
      // when down to the last clip then this one on the clipboard was indeed the last item copied
      // (that hasn't been deleted). But if the queue came from replaying a batch then only if
      // history is on can we restore the clip the user most recently copied.
      if !clipsAreNew && history.isListActive && history.count > 0, let clip = history.clipAtIndex(0) {
        clipboard.copy(clip)
      }
      
    } else if isReplaying && index == priorSize - 1 {
      // In replaying mode where always leave the next item to be pasted on the clipboard,
      // but that next one is the one that's just been removed, not put on the clipboard the
      // new next one in its place.
      try clipboard.copy(getNext())
      
    } else if !isReplaying && index == 0 && clipsAreNew {
      // In normal mode where always leave the latest item that's been copied on the clipboard,
      // but the latest item has been removed, use the new latest one in its place
      try clipboard.copy(getNewest())
    }
  }
  
  func setQueueClips(to clips: [Clip]) throws {
    // fill batch with clips from history
    if clips.isEmpty {
      return
    }
    
    guard let batch = batch else {
      throw QueueError.missingQueueBatch
    }
    
    history.clearCurrentBatch()
    batch.addExistingClips(clips)
    
    isOn = true
    isReplaying = false
    clipsAreNew = false
    stayOnWhenEmptied = false
    clearBatchPending = false
    size = clips.count
    
    // leave clipboard unchanged because isReplaying is false
  }
  
  func replayQueue() throws {
    guard !isOn else {
      throw QueueError.alreadyInProgress
    }
    guard let batch = batch else {
      throw QueueError.missingQueueBatch
    }
    guard batch.count > 0 else {
      throw QueueError.noSuchItem
    }
    
    isOn = true
    isReplaying = true
    clipsAreNew = false
    stayOnWhenEmptied = false
    clearBatchPending = false
    size = batch.count
    
    // because replaying is true, put next to be pasted on the clipboard
    try clipboard.copy(getNext())
  }
  
  // MARK: -
  
  // call bulkDequeueNext or finishBulkDequeue afrer each paste, bulkDequeueNext after all but the last
  // abd finishBulkDequeue after the last. ie, to paste 2 queueu items: 
  //   replaying() / putNextOnClipboard()
  //   *paste*
  //   bulkDequeueNext()
  //   *paste*
  //   finishBulkDequeue()
  
  func bulkDequeueNext() throws {
    // shouldn't call after last item
    guard size > 1 else {
      throw QueueError.noSuchItem
    }
    
    size -= 1
    
    // when pasting multiple, want next item to be pasted on the clipboard
    try clipboard.copy(getNext())
  }
  
  func finishBulkDequeue() throws {
    guard !isEmpty else {
      throw QueueError.noSuchItem
    }
    
    size -= 1
    
    if isEmpty {
      // Emptying queue naturally (by pasting all the clips) is one of the triggers to move clips
      // into the history
      if clipsAreNew && history.isListActive {
        try copyQueueToHistory()
      }
      
      isOn = stayOnWhenEmptied
      clearBatchPending = stayOnWhenEmptied
      
      // Want clipboard to be left at the latest item that's been copied. If this queue came
      // from newly copied clips then nothing to do because in either mode (replaying or not)
      // when down to the last clip then this one on the clipboard was indeed the last item copied.
      // But if the queue came from replaying a batch then only if history is on can we restore
      // the clip the user most recently copied.
      if !clipsAreNew && history.isListActive && history.count > 0, let clip = history.clipAtIndex(0) {
        clipboard.copy(clip)
      }
      
    } else if isReplaying {
      // In replaying mode where always leave the next item to be pasted on the clipboard.
      try clipboard.copy(getNext())
      
    } else if !isReplaying && clipsAreNew {
      // In normal mode where always leave the latest item that's been copied on the clipboard
      // (1.0 betas stayed like this even when pasting from the queue, still support that in
      // this abstraction, but the app always goes into replaying mode on the first paste)
      try clipboard.copy(getNewest())
      
    } else if !isReplaying && !clipsAreNew {
      // In normal mode where always leave the latest item that's been copied on the clipboard
      // (1.0 betas stayed like this even when pasting from the queue, still support that in
      // this abstraction, but the app always goes into replaying mode on the first paste)
      // Here however the queue came from replaying a batch then only if history is on can we
      // restore the clip the user most recently copied.
      if history.isListActive && history.count > 0, let clip = history.clipAtIndex(0) {
        clipboard.copy(clip)
      }
    }
  }
  
  // MARK: -
  
  private func getNext() throws -> Clip? {
    if size == 0 {
      return nil
    }
    
    guard let batch = batch else {
      throw QueueError.missingQueueBatch
    }
    guard size <= batch.count else {
      throw QueueError.sizeOutOfSync
    }
    
    guard let clip = batch.clipAtIndex(size - 1) else {
      throw QueueError.cannotAccesQueueBatch
    }
    return clip
  }
  
  private func getNewest() throws -> Clip? {
    if size == 0 {
      return nil
    }
    
    guard let batch = batch else {
      throw QueueError.missingQueueBatch
    }
    guard batch.count > 0 else {
      throw QueueError.sizeOutOfSync
    }
    
    guard let clip = batch.first else {
      throw QueueError.cannotAccesQueueBatch
    }
    return clip
  }
  
  private func copyQueueToHistory() throws {
    guard let batch = batch else {
      throw QueueError.missingQueueBatch
    }
    
    if !batch.isEmpty {
      batchClips.reversed().forEach(history.add(_:))
    }
  }
  
  // MARK: -
  
  #if DEBUG
  func putPasteRecordOnClipboard() { clipboard.putPastedClipTextOnClipboard()  } // used by ui tests
  
  var summary: String { "\(size) queue clips" }
  var desc: String { debugQueueDescription() }
  var dump: String { debugQueueDescription(ofLength: 0) }
  var ptrs: String { clips.map { "0x\(String(unsafeBitCast($0, to: Int.self), radix: 16))" }.joined(separator: ", ") }
  #endif
  
  var debugDescription: String { debugQueueDescription() }
  
  func debugQueueDescription(ofLength length: Int? = nil) -> String {
    // describe queue and current batch, and at least some history if any
    // in most recent first order, ie the order the queue will be replaying starts with the
    // final one listed in the string / or the last one before the end or "[history]" marker
    
    guard !(batch?.clips == nil && size > 0) else {
      return "error: queue batch nil when size is \(size)"
    }
    let clips = self.batchClips
    guard clips.count >= size else {
      return "error: queue clips count \(clips.count) when size is \(size)"
    }
    
    let len = length ?? 120 // length <= 0 means unlimited length string, length nil means pick this default length
    let batchclips = self.batch?.getClipsArray() ?? []
    let historyclips = history.clips
    var desc: String
    var historymark = ""
    var batchmark = ""
    if self.size > 0 {
      desc = "[queue \(self.size)]"
      if batchclips.count > self.size {
        batchmark = " [\(len <= 0 ? "pasted from batch":"b") \(batchclips.count - self.size)] "
      }
      if historyclips.count > 0 {
        historymark = " [\(len <= 0 ? "history":"h") \(historyclips.count)] "
      }
    } else if batchclips.count > 0 {
      desc = "[\(len <= 0 ? "no queue, last batch":"last batch") \(batchclips.count)]"
      if historyclips.count > 0 {
        historymark = " [\(len <= 0 ? "history":"h") \(historyclips.count)] "
      }
    } else if historyclips.count > 0 {
      desc = "[\(len <= 0 ? "no queue, no last batch, history":"no queue, h") \(historyclips.count)]"
    } else {
      return "[no queue, no history]"
    }
    if len > 0 && len <= desc.count + batchmark.count + historymark.count {
      return desc + batchmark + historymark
    }
    desc += " " // if included it earler, short-circuit return just above would have had a dbl-space  
    
    var remainlen = len - desc.count - batchmark.count - historymark.count
    var historyplanned = historyclips.count // how many to include from history, or more if room
    var totalplanned = batchclips.count + historyclips.count
    let minper = 8
    let cntcomma = 2
    var cntper = minper // num character to print per item
    let commasomitted = 1 + (batchmark.isEmpty ? 1 : 0) + (historymark.isEmpty ? 1 : 0)
    var cntcommas = max(totalplanned - commasomitted, 0) * cntcomma
    if len > 0 && remainlen < totalplanned * minper + cntcommas {
      // can't fit all queue & history, pick how to truncate
      historyplanned = 1 // maybe pick this better?
      totalplanned = batchclips.count + historyplanned
      cntcommas = max(totalplanned - commasomitted, 0) * cntcomma
    }
    cntper = totalplanned == 0 ? minper : max((len - cntcommas) / totalplanned, minper)
    
    for (i, clip) in batchclips.enumerated() {
      let ntogo = batchclips.count - i // how many left to include, including this one
      let nqtogo = self.size - i
      if ntogo == 1 && historyclips.count == 0 {
        cntper = max(len - desc.count, minper) // last one, use whatever length remains
      }
      desc += clip.debugContentsDescription(ofLength: len <= 0 ? 0 : cntper)
      if nqtogo == 1 && ntogo > 1 {
        desc += batchmark 
      } else if ntogo > 1 {
        desc += ", " // if change to omit this space, dont forget to change cntcomma to 1
      }
    }
    
    desc += historymark
    for (i, clip) in historyclips.enumerated() {
      remainlen = len - desc.count
      let ntogo = historyclips.count - i // how many left to include, including this one
      let nplannedtogo = historyplanned - i // how many left that were intended to include, including this one
      if ntogo == 1 {
        cntper = max(remainlen, minper) // last one, use whatever length remains
      } else if len <= 0 || nplannedtogo > 0 {
        // keep goin'
      } else if remainlen < minper {
        // trust that historyplanned was set well to avoid "[history remaining 2] 2 more..."
        desc += "\(ntogo) more"
        break
      } else if nplannedtogo == 0 {
        // this iteration is the first past the # planned, whatever items will fit is bonus,
        // re-adjust characters per item
        if remainlen > (minper + cntcomma) * (ntogo - 1) + minper {
          let cntcommas = (ntogo - 1) * cntcomma
          cntper = (remainlen - cntcommas) / ntogo
        } else {
          cntper = minper
        }
      }
      
      desc += clip.debugContentsDescription(ofLength: len <= 0 ? 0 : cntper)
      if ntogo > 1 {
        desc += ", " // if change to omit this space, dont forget to change cntcomma to 1
      }
    }
    
    return desc
  }
  
}
