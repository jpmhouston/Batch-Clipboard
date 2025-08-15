//
//  History.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-07-10.
//  Portions Copyright © 2025 Bananameter Labs. All rights reserved.
//
//  Based on History.swift from the Maccy project
//  Portions Copyright © 2024 Alexey Rodionov. All rights reserved.
//
//  Maybe makes more sense with this named HistoryManager or something like that,
//  and then HistoryList just be named History.
//
//  TODO: make a BatchList containing ordered set of batches list HistoryList
//  rather than having batch entities be "loose" with sort index to maintain order
//  something to do when adding a saved batch settings panel
//

import AppKit
import os.log

class History {
  var maxItemsOverride = 0
  
  var currentList: HistoryList?
  var currentBatch: Batch?
  
  var usingHistory: Bool { currentList != nil }
  var lastBatch: Batch? { currentBatch }
  var lastBatchClips: [Clip] { currentBatch?.getClipsArray() ?? [] }
  var isLastBatchEmpty: Bool { currentBatch?.isEmpty ?? true }
  var all: [Clip] { currentList?.getClipsArray() ?? [] }
  var clips: [Clip] { currentList?.getClipsArray() ?? [] }
  var first: Clip? { all.first }
  var count: Int { currentList?.clips?.count ?? 0 }
  var batches: [Batch] { return Batch.saved }
  
  #if MACCY_DUPLICATE_HANDLING
  private var sessionLog: [Int: Clip] = [:]
  #endif
  
  init() {
    loadCurrentBatch()
    // loadList needs to be called explicitly later, if user doesn't want the clipboard history
    // feature on then currentList remains nil
  }
  
  func loadCurrentBatch() {
    currentBatch = Batch.current
    
    if currentBatch == nil {
      currentBatch = Batch.createUnnamed()
    }
  }
  
  func loadList() {
    #if DEBUG
    let haveClipsInBatches = Clip.anyWithinBatches // !!! remove once tested
    print("have clips in batches? \(haveClipsInBatches)")
    #endif
    
    currentList = HistoryList.current
    
    if currentList == nil {
      if !Clip.anyWithinBatches {
        // There was no history list and no clips in batchs, seems likely user has upgraded and
        // the history list needs to populated with all the stored clips. Add them in the order
        // `Clip.all` sorts them in, most recent first and oldest last.
        currentList = HistoryList.create(withClips: Clip.all)
      } else {
        // Cannot trust the history. Need to clear all except those that are within batches
        Clip.deleteAllOutsideBatches()
        currentList = HistoryList.create()
      }
    }
  }
  
  func offloadList() {
    // don't delete the history list, it's optionally kept for when user turns history back on
    currentList = nil
  }
  
  // MARK: -
  
  func clipAtIndex(_ index: Int) -> Clip? {
    currentList?.clipAtIndex(index) 
  }
  
  func clipsFromIndex(_ index: Int) -> [Clip] {
    currentList?.clipsFromIndex(index) ?? []
  }
  
  func add(_ clip: Clip) {
    #if MACCY_DUPLICATE_HANDLING
    // don't want ot completely remove this until i understand it
    if let existingHistoryItem = findSimilarItem(clip) {
      if isModified(clip) == nil {
        clip.contents = existingHistoryItem.contents
      }
      clip.firstCopiedAt = existingHistoryItem.firstCopiedAt
      clip.numberOfCopies += existingHistoryItem.numberOfCopies
      clip.pin = existingHistoryItem.pin
      clip.title = existingHistoryItem.title
      if !clip.fromSelf {
        clip.application = existingHistoryItem.application
      }
      remove(existingHistoryItem)
    }
    
    sessionLog[Clipboard.shared.changeCount] = clip
    #endif
    
    currentList?.addNewClip(clip)
    CoreDataManager.shared.saveContext()
  }
  
  func update(_ clip: Clip?) {
    CoreDataManager.shared.saveContext()
  }
  
  func remove(_ clip: Clip) {
    deleteClip(clip)
    CoreDataManager.shared.saveContext()
  }
  
  func remove(atIndex index: Int) {
    guard index < count else {
      return
    }
    deleteClip(all[index])
    CoreDataManager.shared.saveContext()
  }
  
  func trim(to maxItems: Int) {
    // trim results and the database based on size setting
    guard maxItems < count else {
      return
    }
    
    let overflowItems = all.suffix(from: maxItems)
    overflowItems.forEach(deleteClip(_:))
    CoreDataManager.shared.saveContext()
  }
  
  func clearHistory() {
    clips.forEach(deleteClip(_:))
    CoreDataManager.shared.saveContext()
  }
  
  func clearCurrentBatch() {
    currentBatch?.clear()
    CoreDataManager.shared.saveContext()
  }
  
  func removeSavedBatch(atIndex index: Int) {
    guard index < batches.count else {
      return
    }
    deleteBatch(batches[index])
    CoreDataManager.shared.saveContext()
  }
  
  func removeSavedBatch(_ batch: Batch) {
    deleteBatch(batch)
    CoreDataManager.shared.saveContext()
  }
  
  func deleteAllData() {
    currentList = nil
    currentBatch = nil
    let fetchRequest = NSFetchRequest<HistoryList>(entityName: "HistoryList")
    do {
      let historyLists = try CoreDataManager.shared.context.fetch(fetchRequest)
      historyLists.forEach {
        CoreDataManager.shared.context.delete($0)
      }
    } catch {
      os_log(.default, "unhandled error deleting history list %@", error.localizedDescription)
    }
    Batch.deleteAll()
    Clip.deleteAll()
  }
  
  // MARK: -
  
  private func deleteClip(_ clip: Clip) {
    // coredata has some relationshipdelete rules, it seems none of them are like reference counting
    // to do this automatically: if the clips no longer belongs to any batch then fully delete it
    currentList?.removeFromClips(clip)
    if clip.parentConnectionsEmpty {
      clip.clearContents()
      CoreDataManager.shared.context.delete(clip)
    }
  }
  
  private func deleteBatch(_ batch: Batch) {
    batch.clear()
    CoreDataManager.shared.context.delete(batch)
  }
  
  #if MACCY_DUPLICATE_HANDLING
  private func findSimilarItem(_ clip: Clip) -> Clip? {
    let duplicates = all.filter({ $0 == clip || $0.supersedes(clip) })
    if duplicates.count > 1 {
      return duplicates.first(where: { $0.objectID != clip.objectID })
    } else {
      return isModified(clip)
    }
  }
  
  private func isModified(_ clip: Clip) -> Clip? {
    if let modified = clip.modified, sessionLog.keys.contains(modified) {
      return sessionLog[modified]
    }
    
    return nil
  }
  #endif
  
  //index
  // MARK: -
  
  #if DEBUG
  var summary: String { "\(count) history clips" }
  var desc: String { debugHistoryAndBatchDescription() }
  var dump: String { debugHistoryAndBatchDescription(ofLength: 0) }
  var ptrs: String { clips.map { "0x\(String(unsafeBitCast($0, to: Int.self), radix: 16))" }.joined(separator: ", ") }
  #endif
  
  var debugDescription: String { debugHistoryAndBatchDescription() }
  
  func debugHistoryAndBatchDescription(ofLength length: Int? = 0) -> String {
    // describe history in most recent first order, plus last batch if space allowed 
    
    let len = length ?? 120 // length <= 0 means unlimited length string, length nil means pick this default length
    var desc: String
    if self.count == 0 {
      desc = "[no history]"
    } else {
      desc = "[history \(self.count)] "
    }
    if len > 0 && len <= desc.count {
      return desc
    }
    
    var remainlen = len - desc.count
    var nplanned = self.count
    let minper = 8
    let cntcomma = 2
    var cntper = minper // num character to print per item
    var cntcommas = (nplanned - 1) * cntcomma
    if len > 0 && remainlen < nplanned * minper + cntcommas {
      // can't fit all history, pick how to truncate
      nplanned = max(self.count, 8)
      cntcommas = max(nplanned - 1, 0) * cntcomma
    }
    cntper = nplanned == 0 ? minper : max((len - cntcommas) / nplanned, minper)
    
    for (i, clip) in self.clips.enumerated() {
      remainlen = len - desc.count
      let ntogo = self.count - i // ie. how many left to add to str, including this one
      let nplannedtogo = nplanned - i // how many left that were intended to include, including this one
      if ntogo == 1 {
        cntper = max(len - remainlen, minper) // last one, give it whatever chars remain
      } else if len <= 0 || nplannedtogo > 0 {
        // last one planned, keep going'
      } else if remainlen < minper {
        desc += "\(ntogo) more" // just trust that nplanned set to qsize+1 will avoid "[history remaining 2] 2 more..."
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
    
    if let batchclips = self.currentBatch?.getClipsArray(), !batchclips.isEmpty {
      if len <= 0 {
        desc += " [last/current batch \(batchclips.count)] "
      } else {
        let bmarker = " [last b \(batchclips.count)] "
        if len < desc.count + bmarker.count {
          return desc
        }
        desc += bmarker
      }
      
      remainlen = len - desc.count
      var batchplanned = batchclips.count
      if len > 0 && remainlen < (batchplanned - 1) * (minper + cntcomma) + minper {
        batchplanned = 1 // maybe pick this better?
      }
      let cntcommas = max(batchplanned - 1, 0) * cntcomma
      cntper = (remainlen - cntcommas) / batchplanned // batchclips.isEmpty test above means batchplanned > 0
      
      for (i, clip) in batchclips.enumerated() {
        remainlen = len - desc.count
        let ntogo = batchclips.count - i
        let ntogoplanned = batchplanned - i
        if ntogo == 1 {
          cntper = max(len - remainlen, minper) // last one, give it whatever chars remain
        } else if len <= 0 || ntogoplanned > 0 {
          // keep goin'
        } else if remainlen < minper {
          desc += "\(ntogo) more" // just trust that batchplanned set well to avoid "[last batch 2] 2 more..."
          break
        } else if ntogoplanned == 0 {
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
          desc += ", "
        }
      }
    }
    
    return desc
  }
  
}
