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

// TODO: unit tests needed badly

class ClipboardQueue {
  
  enum QueueError: Error {
    case logicError
    case noSuchItem
    case sizeExceedsHistory
  }
  
  var isOn = false
  var isReplaying = false
  var stayOnWhenEmptied = false
  var freshHistoryMode = false
  var size = 0 {
    didSet {
      history.maxItemsOverride = size
    }
  }
  
  //better if these were protocol that can be easily mocked
  private let clipboard: Clipboard
  private let history: History
  
  init(clipboard c: Clipboard, history h: History) {
    clipboard = c
    history = h
  }
  
  // MARK: -
  
  var notEmpty: Bool {
    isOn && size > 0
  }
  
  var isEmpty: Bool {
    !notEmpty
  }
  
  var headIndex: Int? {
    if isEmpty {
      nil
    } else {
      size - 1
    }
  }
  
  // MARK: -
  
  func on(allowStayingOnAfterDecrementToZero allowEmpty: Bool = false) {
    isOn = true
    isReplaying = false
    stayOnWhenEmptied = allowEmpty
    size = 0
    
    if freshHistoryMode {
      history.clear()
      CoreDataManager.shared.saveContext()
    }
  }
  
  func off() {
    isOn = false
    size = 0
    
    // in case pasteboard was left set to an item deeper in the queue, reset to the latest item copied
    if isReplaying, let newestItem = history.first {
      clipboard.copy(newestItem)
    }
    
    isReplaying = false
  }
  
  func replaying() throws {
    if !isReplaying {
      isReplaying = true
      try putNextOnClipboard()
    }
  }
  
  // MARK: -
  
  func add(_ clip: Clip) throws {
    if !isOn {
      on(allowStayingOnAfterDecrementToZero: false)
    }
    
    // currently item not treated differently by history when queue on vs off
    // but this may change in the future
    history.add(clip)
    
    size += 1
    
    // we presume the item passed in has come from the clipboard,
    // if size of the queue is only 1, then we've already got the one we want for either mode
    if isReplaying && size > 1 {
      guard let headIndex = headIndex else {
        throw QueueError.logicError
      }
      guard headIndex < history.count else {
        throw QueueError.sizeExceedsHistory
      }
      
      // in replaying mode where always want next item to be pasted on the clipboard, presuming the item
      // passed in has come from the clipboard, replace it again with the next item to be pasted
      clipboard.copy(history.all[headIndex])
    }
  }
  
  func putNextOnClipboard() throws {
    guard !isEmpty, let headIndex = headIndex else {
      throw QueueError.noSuchItem
    }
    guard headIndex < history.count else {
      throw QueueError.sizeExceedsHistory
    }
    
    clipboard.copy(history.all[headIndex])
  }
  
  func dequeue() throws {
    guard !isEmpty, let priorHeadIndex = headIndex else {
      throw QueueError.noSuchItem
    }
    guard priorHeadIndex >= 0 && priorHeadIndex < history.count else {
      throw QueueError.sizeExceedsHistory
    }
    
    size -= 1
    
    if isEmpty {
      guard priorHeadIndex == 0 else {
        throw QueueError.logicError
      }
      
      isOn = stayOnWhenEmptied
      // leave clipboard alone, want it to be left at the latest item that's been copied, but even
      // in replaying mode where next item on clipbboard not the last item copies, when queue size
      // was 1 the next to paste was the latest copied
      
    } else if isReplaying {
      guard let newHeadIndex = headIndex else {
        throw QueueError.logicError // should have insted entered the `if empty` case above
      }
      guard newHeadIndex < history.count else {
        throw QueueError.sizeExceedsHistory
      }
      
      // in replaying mode where always leave the next item to be pasted on the clipboard
      clipboard.copy(history.all[newHeadIndex])
      
    } else {
      // in normal mode where always leave the latest item that's been copied on the clipboard
      // (1.0 betas stayed like this even when pasting from the queue, still support that in
      // this abstraction, but the app always goes into replaying mode on the first paste)
      clipboard.copy(history.first)
    }
  }
  
  func remove(atIndex index: Int) throws {
    guard !isEmpty, let priorHeadIndex = headIndex else {
      throw QueueError.noSuchItem
    }
    guard priorHeadIndex >= 0 && priorHeadIndex < history.count else {
      throw QueueError.sizeExceedsHistory
    }
    
    guard index >= 0 && index <= priorHeadIndex else { 
      throw QueueError.noSuchItem
    }
    guard index < history.count else { // transitively, should be true
      throw QueueError.logicError
    }
    
    let clip = history.all[index]
    history.remove(clip)
    
    size -= 1
    
    if isEmpty {
      guard priorHeadIndex == 0 else {
        throw QueueError.logicError
      }
      
      isOn = stayOnWhenEmptied
      // leave clipboard alone, want it to be left at the latest item that's been copied, but even
      // in replaying mode where next item on clipbboard not the last item copies, when queue size
      // was 1 the next to paste was the latest copied
      
    } else if isReplaying && index == priorHeadIndex {
      guard let newHeadIndex = headIndex else {
        throw QueueError.logicError // should have insted entered the `if empty` case above
      }
      guard newHeadIndex < history.count else {
        throw QueueError.sizeExceedsHistory
      }
      
      // in replaying mode where always leave the next item to be pasted on the clipboard, but the
      // next one has been removed, use the new next one in its place
      clipboard.copy(history.all[newHeadIndex])
      
    } else if !isReplaying && index == 0 {
      // in normal mode where always leave the latest item that's been copied on the clipboard,
      // but the latest item has been removed, use the new latest one in its place
      clipboard.copy(history.first)
    }
  }
  
  func setHead(toIndex index: Int) throws {
    if !isOn {
      on()
    }
    
    size = index + 1
    
    if isReplaying && size > 1 {
      guard index < history.count else {
        throw QueueError.sizeExceedsHistory
      }
      
      // in the mode where always want next item to be pasted on the clipboard
      clipboard.copy(history.all[index])
    }
  }
  
  // MARK: -
  
  // call bulkDequeueNext inbetween pastes, finishBulkDequeue at the end
  // to paste 3\2 queueu items: 
  // replaying() / putNextOnClipboard()
  // *paste*
  // bulkDequeueNext()
  // *paste*
  // finishBulkDequeue()
  
  func bulkDequeueNext() throws {
    // shouldn't call after last item
    guard size > 1 else {
      throw QueueError.noSuchItem
    }
    
    size -= 1
    
    guard let newHeadIndex = headIndex else {
      throw QueueError.logicError // should have insted entered the `if empty` case above
    }
    
    // when pasting multiple, want next item to be pasted on the clipboard
    clipboard.copy(history.all[newHeadIndex])
  }
  
  func finishBulkDequeue() throws {
    guard !isEmpty else {
      throw QueueError.noSuchItem
    }
    
    size -= 1
    
    if isEmpty {
      isOn = stayOnWhenEmptied
      // leave clipboard alone, want it to be left at the latest item copied which should
      // be the one from the previous iteration
      
    } else if !isReplaying {
      // in the mode where always want the latest item that's been copied on the clipboard
      clipboard.copy(history.all.first)
      
    } else if isReplaying {
      let index = size - 1
      guard index < history.count else {
        throw QueueError.sizeExceedsHistory
      }
      
      // in the mode where always want next item to be pasted on the clipboard
      clipboard.copy(history.all[index])
    }
  }
  
  // MARK: -
  
  #if DEBUG
  func putPasteRecordOnClipboard() { clipboard.putPastedClipTextOnClipboard()  } // used by ui tests
  
  var desc: String { debugQueueAndHistoryDescription() }
  var log: String { debugQueueAndHistoryDescription() }
  var dump: String { debugQueueAndHistoryDescription(ofLength: 0) }
  #endif
  
  var debugDescription: String {
    debugQueueAndHistoryDescription()
  }
  
  func debugQueueAndHistoryDescription(ofLength length: Int? = nil) -> String {
    // describe queue and at least some history that follows (if any) in most recent first order
    // so the order the queue will be replaying starts with the last one, or the last onw
    // before the "[history]" marker
    
    var len = length ?? 120 // length <= 0 means unlimited length string, length nil means pick this default length
    if history.count == 0 {
      return "empty"
    }
    var desc = ""
    var historymark = ""
    if len <= 0 {
      if self.isEmpty {
        desc = "[no-queue, history \(history.count)] "
      } else {
        desc = "[queue \(self.size)] "
        if history.count > self.size {
          historymark = " [history remaining \(history.count - self.size)] "
        }
      }
    } else {
      if self.isEmpty {
        desc = "[no-q, h \(history.count)] "
        len = max(1, len - desc.count)
      } else {
        desc = "[q \(self.size)] "
        if history.count > self.size {
          historymark = " [h \(history.count - self.size)] "
          len = max(1, len - desc.count - historymark.count)
        } else {
          len = max(1, len - desc.count)
        }
      }
    }
    
    // figurin'
    let minper = 8
    let cntcomma = 2
    var cntper = minper // num character to print per item
    var nplanned = history.count // how many after queue to print from history, or more if room
    if len > 0 {
      // don't need no figurin'
    } else if len < history.count / (minper + cntcomma) && self.size > 3 { // if not many queued, don't prioritize them
      // prioriize queue & truncate history items, set size-per based on printing queue then at least 1 past that
      nplanned = self.size + history.count > self.size ? 1 : 0 
      let cntcommas = nplanned <= 1 ? 0 : (nplanned - 1) * cntcomma // the count of chars for comma separators for nplanned-many items
      if len < nplanned * minper + cntcommas { 
        cntper = minper
      } else {
        cntper = (len - cntcommas) / nplanned
      }
    } else if len < history.count / (minper + cntcomma) {
      // can't fit all history, pick how to truncate, include at least all queued
      nplanned = max(self.size, 8)
      let cntcommas = nplanned <= 1 ? 0 : (nplanned - 1) * cntcomma // the count of chars for comma separators for nplanned-many items
      if len < nplanned * minper + (nplanned <= 1 ? 0 : (nplanned - 1) * cntcomma) {
        cntper = minper
      } else {
        cntper = (len - cntcommas) / nplanned
      }
    } else {
      // could fit all history at smaller chars per item, but maybe truncate for use more chars per item
      nplanned = max(self.size, 12)
      let cntcommas = nplanned <= 1 ? 0 : (nplanned - 1) * cntcomma // the count of chars for comma separators for nplanned-many items
      cntper = (len - cntcommas) / nplanned
    }
    
    // build string
    for (i, clip) in history.all.enumerated() { // was `i in 0 ..< history.count` & `clip = history.all[i]` below
      let remainlen = len - desc.count
      
      let ntogo = history.count - i // ie. how many left to add to str, including this one
      let ntogoqueued = self.size - i // when == 1 this is the last if the queue, <= 0 all of queue already added to str 
      let ntogoplanned = nplanned - i // when > 0 xxxxxxxxx, when == 0 this is the first of the gravy
      if len <= 0 || ntogoplanned > 1 {
        // keep goin'
      } else if ntogo == 1 {
        cntper = max(len - remainlen, minper) // last one, give it whatever chars remain
      } else if ntogoplanned > 0 {
        // last one planned, keep going'
      } else if ntogoplanned == 0 {
        // included all we planned to, any more items is gravy, adjust char per item for including more
        if remainlen > (minper + cntcomma) * ntogo {
          let cntcommas = (ntogo - 1) * cntcomma // note, only here if ntogo > 1
          cntper = (remainlen - cntcommas) / ntogo
        } else {
          cntper = minper
        }
      } else if remainlen < minper {
        desc += "\(ntogo) more" // just trust that nplanned set to qsize+1 will avoid "[history remaining 2] 2 more..."
        break
      }
      
//      if i >= history.count {
//        break // seen during unit tests, in danger of instead failing with 'mutated while being enumerated' exception
//      }
//      let clip = history.all[i]
      desc += clip.debugContentsDescription(ofLength: len <= 0 ? 0 : cntper)
      if ntogoqueued == 1 && ntogo > 1 {
        desc += historymark
      } else if ntogo > 1 {
        desc += ", " // if change to omit this space, dont forget to change cntcomma to 1
      }
    }
    return desc
  }
  
}
