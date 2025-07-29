//
//  TestQueue.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2025-07-30.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//

import Testing
import AppKit

@Suite("Queue test simulations", .serialized)
class QueueSims {
  
  // TODO: maybe allow expectations against degenerate cases, like queued-paste when nothing queued
  
  enum Token: String, CaseIterable {
    case start = "/q"       // start queueing
    case canc = "/x"        // cancel queue
    case begdq = "/r"       // start dequeueing (replaying) 
    case qcopy = "/k:"      // queued copy that implicitly starts queueing 
    case undo = "/u"        // undo most recent copy
    case qfromh = "/f:"     // start queue from a history index (counting from most recent)
    case paste = "/po"      // paste only without advancing
    case qpaste = "/p>"     // paste and advance
    case adv = "/>"         // advance
    case qpall = "/pa"      // paste all
    case qpmul = "/p:"      // paste multiple
    case qpmuls = "/b:"     // separtor between paste multiple (avoid: sp tab newln comma slash v.bar hash)
    case autoron = "/a+"    // auto-replay mode on (default) 
    case autoroff = "/a-"   // auto-replay mode off (even though this mode no longer used by app)
    case del = "/d:"        // delete with history index (counting from most recent) outside of queue
    case clear = "/w"       // clear all
    case hoff = "/h-"       // history off
    case hon = "/h+"        // history on (default)
    case stay = "/m+"       // stay mode on, queueing remains on when queue emptied (use after `start`)
    case nostay = "/m-"     // stay mode off, emptying queue turns it off (default)
    case isqon = "/s+"      // check if queue is on
    case isqoff = "/s-"     // check if queue is off
    case issize = "/s:"     // check if queue the expected size
    case iscnt = "/n:"      // check if history has the expected count
    case isclip = "/c:"     // compare string against clipboard
    case pasted = "/e:"     // compare string against everything pasted
    case deleted = "/l:"    // compare string against last item deleted
    case begcmp = "/=["     // compare to all history begin (including the queue, starting least recent)
    case begcmpq = "/=("    // compare to queue begin (starting least recent)
    case begcmpi = "/=[:"   // compare to history starting at index (including the queue, counting from most recent)
    case endcmp = "/]"      // compare to all history end
    case other = ""         // handy to have enum case for a str value instead of a token
  }
  
  let coreDataStack: CoreDataManager
  let clipboard: Clipboard
  let history: History
  let queue: ClipboardQueue
  var historyMatchIndex: Int?
  var compareToEnd = false
  var useReplayingMode = true
  var queuedPasteMultipleSeparator = ""
  
  let trimDelimiters = Set(" \n\r\t".map(Character.init))
  let skipDelimiters = Set(",|".map(Character.init))
  let keepDelimiters = Set("/".map(Character.init))
  let commentDelimiters = Set("#".map(Character.init))
  let delimiters: Set<Character> // init. to be union of all the delimieters above
  lazy var selfContainedTokenStrings: [String] = Token.allCases.map { $0.rawValue }.filter { !$0.isEmpty && $0.last != ":" }
    // hmmm, why did `.map(\rawValue)` not work above?
  
  init() {
    let bundle = Bundle(for: Self.self)
    guard let modelURL = bundle.url(forResource: "Storage", withExtension: ".momd") else {
      fatalError("can't find model")
    }
    guard let model = NSManagedObjectModel(contentsOf: modelURL) else {
      fatalError("can't create model")
    }
    
    delimiters = trimDelimiters.union(skipDelimiters).union(keepDelimiters).union(commentDelimiters)
    
    coreDataStack = CoreDataManager.reset() // replace instance with one having fresh everything
    coreDataStack.model = model
    coreDataStack.inMemory = true
    //coreDataStack.useUniqueTestDatabaseLocation(withName: "Batch_Clipboard_queuesim")
    //CoreDataManager.queuecheck() // do init/deinit and test functions always run on a side queue?
    
    clipboard = Clipboard()
    history = History()
    queue = ClipboardQueue(clipboard: clipboard, history: history)
  }
  
  deinit {
    // it seems some coredata cleanup from one run is interfering with the next, even with
    // the call to reset() in init should clearly separate the two, but maybe because they share
    // the one model in the same process there's some shared state IDK... hoping this helps
    CoreDataManager.queuecheck() // do init/deinit and test functions always run on a side queue?
    coreDataStack.teardown()
    
    sleep(1)
  }
  
  let logQueueAfterEveryOp = false
  let logClipObjPointers = false
  let logQueueAfterRun = false
  
  static let sample = [ "#sample# " +     hon + "h1,h2" + start + "qA,qB,qC" + iscnt+"5" + issize+"3" + qpaste + qpaste + issize+"1" + iscnt+"5" + canc + isqoff + iscnt+"5" +
                                           pasted+"qAqB" + begcmp + "h1,h2,qA,qB,qC" + endcmp ]
  
  static let paste1EmptyH = [ "#paste1# " +               hon + start + "qA,qB" + issize+"2" + iscnt+"2" + qpaste + isqon + iscnt+"2" ]
  static let pasteAllEmptyH = [ "#pasteAll# " +           hon + start + "qA,qB" + issize+"2" + iscnt+"2" + qpaste + qpaste + isqoff + iscnt+"2" ]
  static let paste1plusH = [ "#paste1+H# " +              hon + "h1,h2" + start + "qA,qB" + issize+"2" + qpaste + isqon + iscnt+"4" ]
  static let pasteAllplusH = [ "#pasteAll+H# " +          hon + "h1,h2" + start + "qA,qB" + issize+"2" + qpaste + qpaste + isqoff + iscnt+"4" ]
  static let paste1Hoff = [ "#paste1-H# " +               hoff + start + "qA,qB" + issize+"2" + qpaste + isqon + iscnt+"2" ]
  static let pasteAllHoff = [ "#pasteAll-H# " +           hoff + start + "qA,qB" + issize+"2" + qpaste + qpaste + isqoff + iscnt+"2" ]
  static let queueAgainClearsH = [ "#QQ->-H# " +          hoff + start + "qA,qB" + qpaste + qpaste + isqoff + iscnt+"2" + start + iscnt+"0" ]
  static let queueAfterCancClearsH = [ "#QXQ->-H# " +     hoff + start + "qA,qB" + canc + isqoff + iscnt+"2" + start + iscnt+"0" ]
  
  static let pmultAllEmptyH = [ "#pmultAll# " +           hon + start + "qA,qB,qC" + qpall + isqoff + pasted+"qAqBqC" ]
  static let pmult1EmptyH = [ "#pmult# " +                hon + start + "qA,qB,qC" + qpmul+"1" + issize+"2" + pasted+"qA" ]
  static let pmultEmptyH = [ "#pmult# " +                 hon + start + "qA,qB,qC" + qpmul+"2" + issize+"1" + pasted+"qAqB" ]
  static let pmultWSepEmptyH = [ "#pmult+,# " +           hon + start + "qA,qB,qC" + qpmuls+"." + qpmul+"2" + isqon + pasted+"qA.qB" ]
  static let pmultAllplusH = [ "#pmultAll+H# " +          hon + "h1,h2" + start + "qA,qB,qC" + qpall + isqoff + iscnt+"5" + pasted+"qAqBqC" ]
  static let pmultplusH = [ "#pmultAll+H# " +             hon + "h1,h2" + start + "qA,qB,qC" + qpmul+"2" + issize+"1" + iscnt+"5" + pasted+"qAqB" ]
  static let pmultAllHoff = [ "#pmultAll-H# " +           hoff + start + "qA,qB,qC" + qpall + isqoff + pasted+"qAqBqC" ]
  static let pmultHoff = [ "#pmultH-# " +                 hoff + start + "qA,qB,qC" + qpmul+"2" + issize+"1" + pasted+"qAqB" ]
  
  static let queueFromHThenPaste = [ "#qFromH# " +        hon + "h1,h2,h3" + qfromh+"1" + iscnt+"3" + begcmpq + "h2,h3" + endcmp + qpaste + qpaste + isqoff + iscnt+"3" +
                                                            pasted+"h2h3" + begcmp + "h1,h2,h3" + endcmp ]
  static let queueFromHThenCanc = [ "#q&cancFromH# " +    hon + "h1,h2,h3" + qfromh+"1" + canc + isqoff + iscnt+"3" + begcmp + "h1,h2,h3" + endcmp ]
  static let queueAllFromH = [ "#qAllFromH# " +           hon + "h1,h2,h3" + qfromh+"2" + iscnt+"3" + begcmpq + "h1,h2,h3" + endcmp + qpmul+"3" + pasted+"h1h2h3" ]
  static let queue1FromH = [ "#q1FromH# " +               hon + "h1,h2,h3" + qfromh+"0" + iscnt+"3" + begcmpq + "h3" + endcmp + qpaste + pasted+"h3" + begcmp + "h1,h2,h3" + endcmp ]
  
  static let delFromH = [ "#delFromH# " +                 hon + "h1,h2,h3" + issize+"3" + iscnt+"3" + del+"1" + iscnt+"2" + begcmp + "h1,h3" + endcmp ]
  static let delFromHOldest = [ "#delFromH-># " +         hon + "h1,h2,h3" + del+"2" + begcmp + "h2,h3" + endcmp + del+"1" + begcmp + "h3" + endcmp + del+"0" + iscnt+"0" ]
  static let delFromHNewest = [ "#delFromH<-# " +         hon + "h1,h2,h3" + del+"0" + begcmp + "h1,h2" + endcmp + del+"0" + begcmp + "h1" + endcmp + del+"0" + iscnt+"0" ]
  static let delFromHplusQ = [ "#delFromH+Q# " +          hon + "h1,h2,h3" + start + "qA,qB" + issize+"3" + iscnt+"5" + del+"3" + iscnt+"4" + begcmp + "h1,h3,qA,qB" + endcmp ]
  static let delFromHplusQOldest = [ "#delFromH+Q-># " +  hon + "h1,h2" + start + "qA" + del+"2" + begcmp + "h2,qA" + endcmp + del+"1" + begcmp + "qA" + endcmp ]
  static let delFromHplusQNewest = [ "#delFromH+Q<-# " +  hon + "h1,h2" + start + "qA" + del+"1" + begcmp + "h1,qA" + endcmp + del+"1" + begcmp + "qA" + endcmp ]
  static let delFromQEmptyH = [ "#delFromQ# " +           hon + start + "qA,qB,qC" + issize+"3" + del+"1" + issize+"2" + begcmp + "qA,qC" + endcmp ]
  static let delFromQEmptyHOldest = [ "#delFromQ0H-># " + hon + start + "qA,qB,qC" + del+"2" + begcmp + "qB,qC" + endcmp + del+"1" + begcmp + "qC" + endcmp + del+"0" + isqoff + iscnt+"0" ]
  static let delFromQEmptyHNewest = [ "#delFromQ0H<-# " + hon + start + "qA,qB,qC" + del+"0" + begcmp + "qA,qB" + endcmp + del+"0" + begcmp + "qA" + endcmp + del+"0" + isqoff + iscnt+"0" ]
  static let delFromQplusH = [ "#delFromQ+H# " +          hon + "h1" + start + "qA,qB,qC" + iscnt+"4" + issize+"3" + del+"1" + issize+"2" + begcmpq + "qA,qC" + endcmp ]
  static let delFromQplusHOldest = [ "#delFromQ+H#-># " + hon + "h1" + start + "qA,qB,qC" + del+"2" + issize+"2" + begcmpq + "qB,qC" + endcmp + del+"1" +
                                                            begcmpq + "qC" + endcmp + del+"0" + isqoff + iscnt+"1" ]
  static let delFromQplusHNewest = [ "#delFromQ+H<-# " +  hon + "h1" + start + "qA,qB,qC" + del+"0" + issize+"2" + begcmpq + "qA,qB" + endcmp + del+"0" +
                                                            begcmpq + "qA" + endcmp + del+"0" + isqoff + iscnt+"1" ]
  static let delFromQHoff = [ "#delFromQ-H# " +           hoff + start + "qA,qB,qC" + issize+"3" + del+"1" + issize+"2" + begcmp + "qA,qC" + endcmp + iscnt+"2" ]
  static let delFromQHoffOldest = [ "#delFromQ-H-># " +   hoff + start + "qA,qB,qC" + del+"2" + begcmp + "qB,qC" + endcmp + del+"1" + begcmp + "qC" + endcmp + del+"0" + isqoff + iscnt+"0" ]
  static let delFromQHoffNewest = [ "#delFromQ-H<-# " +   hoff + start + "qA,qB,qC" + del+"0" + begcmp + "qA,qB" + endcmp + del+"0" + begcmp + "qA" + endcmp + del+"0" + isqoff + iscnt+"0" ]
  
  static let clearH = [ "#clearH# " +                     hon + "h1,h2" + clear + iscnt+"0" ]
  static let clearHandQ = [ "#clearH+Q# " +               hon + "h1,h2" + start + "qA,qB" + clear + isqoff + iscnt+"0" ]
  static let clearQnoH = [ "#clearQH-# " +                hon + start + "qA,qB" + clear + isqoff + iscnt+"0" ]
  static let clearQHoff = [ "#clearQH-# " +               hoff + start + "qA,qB" + clear + isqoff + iscnt+"0" ]
  
  // TODO: discovery why enabling several at a time causes coredata exceptions & crashes!
  
  @Test("queue simulator", arguments: [ sample,
                                        //paste1EmptyH, pasteAllEmptyH, paste1plusH, pasteAllplusH, paste1Hoff, pasteAllHoff,
                                        //queueAgainClearsH, queueAfterCancClearsH,
                                        //pmultAllEmptyH, pmult1EmptyH, pmultEmptyH, pmultWSepEmptyH, pmultAllplusH, pmultplusH, pmultAllHoff, pmultHoff,
                                        //queueFromHThenPaste, queueFromHThenCanc, queueAllFromH, queue1FromH,
                                        //delFromH, delFromHOldest, delFromHNewest, delFromHplusQ, delFromHplusQOldest, delFromHplusQNewest,
                                        //delFromQEmptyH, delFromQEmptyHOldest, delFromQEmptyHNewest, delFromQplusH, delFromQplusHOldest, delFromQplusHNewest,
                                        //delFromQHoff, delFromQHoffOldest, delFromQHoffNewest,
                                        //clearH, clearHandQ, clearQnoH, clearQHoff,
                                      ])
  func queueSim(run: [String]) async throws {
    try #require(history.count == 0) // with xcode 26, build fails without `try` here
    
    var lastDeleted: String? = nil
    var n = 0
    
    for segment in run {
      var tokenize = segment
      while !tokenize.isEmpty {
        guard let str = nextTokenString(from: &tokenize) else { continue }
        
        let (op, param, value) = Token.parseOpAndParam(str)
        defer { n += 1 }
        
        switch op {
        case .hon: queue.freshHistoryMode = false
        case .hoff: queue.freshHistoryMode = true
        case .stay: queue.stayOnWhenEmptied = true
        case .nostay: queue.stayOnWhenEmptied = false
          
        case .start: // replicates AppModel.startQueueMode 
          guard !queue.isOn else { print("unexpected second start-queueing token '\(start)' [\(n)]"); continue }
          queue.on()
          #expect(queue.isOn, "at start-queueing token '\(start)' [\(n)]")
        case .canc: // replicates AppModel.cancelQueueMode
          if !queue.isOn { print("unexpected cancel-queueing token '\(canc)' [\(n)] without previous start-queueing '\(start)'") }
          queue.off()
          #expect(!queue.isOn, "at cancel-queueing token '\(canc)' [\(n)]")
        case .begdq: // replicates AppModel.startReplay
          guard queue.isOn else { print("unexpected queueing already on at start-dequeueing token '\(begdq)' [\(n)]"); continue }
          guard queue.size > 0 else { print("unexpected queue non-empty at start-dequeueing token '\(begdq)' [\(n)]"); continue }
          try queue.replaying()
        
        case .qfromh: // replicates AppModel.undoLastCopy
          guard let i = value else { print("unexpected start-from-history token '\(qfromh)' [\(n)] non-int parameter, instead '\(param ?? "")'"); continue }
          #expect(!queue.isOn, "at start-from-history token '\(qfromh) [\(n)]")
          #expect(i < history.count, "at start-from-history token '\(qfromh) [\(n)]")
          queue.on()
          try queue.setHead(toIndex: i)
          try queue.replaying()
        
        case .isqon:
          #expect(queue.isOn)
        case .isqoff:
          #expect(!queue.isOn)
        case .issize:
          guard let value = value else { print("unexpected is-size token '\(issize)' [\(n)] non-int parameter, instead '\(param ?? "")'"); continue }
          #expect(queue.isOn, "at is-size token \(issize) [\(n)]")
          guard queue.isOn else { continue }
          #expect(queue.size == value, "at is-size token '\(issize)' [\(n)]")
        case .iscnt:
          guard let value = value else { print("unexpected is-history-count token '\(iscnt)' [\(n)] non-int parameter, instead '\(param ?? "")'"); continue }
          #expect(history.count == value, "at is-history-count token '\(iscnt)' [\(n)]")
        
        case .qcopy: // replicates AppModel.queuedCopy + clipboardChanged 
          guard let param = param, !param.isEmpty else { print("unexpected queued-copy token '\(qcopy)' [\(n)] parameter empty"); continue }
          if !queue.isOn {
            queue.on()
          }
          let newcc = ClipContent(type: NSPasteboard.PasteboardType.string.rawValue,
                                  value: param.data(using: .utf8))
          let newclip = Clip(contents: [newcc], application: ProcessInfo.processInfo.processName)
          try queue.add(newclip)
          coreDataStack.saveContext()
        
        case .undo: // replicates AppModel.undoLastCopy
          guard let clip = history.first else { print("kinda fishy, was this intentional? no first history item at undo-copy token '\(undo)' [\(n)]"); return }
          history.remove(clip)
          if !queue.isEmpty {
            try queue.remove(atIndex: 0)
          }
          coreDataStack.saveContext()
        
        case .paste:
          // tell clipboard to paste
          await withCheckedContinuation { continuation in
            clipboard.invokeApplicationPaste(then: continuation.resume)
          }
        case .qpaste: // replicates AppModel.queuedPaste
          guard queue.isOn else { print("unexpected queueing not on at queued-paste token '\(qpaste)' [\(n)]"); continue }
          guard queue.size > 0 else { print("unexpected queue not be empty at queued-paste token '\(qpaste)' [\(n)]"); continue }
          // queue supports dequeueing while replaying mode off, test it even though app doesn't use it
          if useReplayingMode {
            try queue.replaying()
          } else {
            try queue.putNextOnClipboard()
          }
          // tell fake clipboard to fake paste
          await withCheckedContinuation { continuation in
            clipboard.invokeApplicationPaste(then: continuation.resume)
            //print("pasted '\(clipboard.currentText ?? "?")'")
          }
          try queue.dequeue()
        case .adv: // replicates AppModel.advanceReplay
          #expect(queue.isOn, "at advance-in-queue token '\(adv)' [\(n)]")
          guard queue.isOn else { continue }
          #expect(queue.size > 0, "at advance-in-queue token '\(adv)' [\(n)]")
          guard queue.size > 0 else { continue }
          if useReplayingMode {
            try queue.replaying()
          }
          try queue.dequeue()
        
        case .autoron: useReplayingMode = true
        case .autoroff: useReplayingMode = false
        
        case .qpall, .qpmul: // replicates AppModel.queuedPasteMultiple + queuedPasteMultipleIterator
          let num: Int
          let sep: String
          if op == .qpall {
            #expect(queue.isOn, "at queued-paste-all token '\(qpall)' [\(n)]")
            guard queue.isOn else { continue }
            guard queue.size > 0 else { print("kinda fishy, was this intentional? queue size is 0 at queued-paste-all token '\(qpall)' [\(n)]"); continue }
            num = queue.size
            sep = ""
          } else {
            guard let value = value else { print("unexpected queued-paste-multiple token '\(qpmul)' [\(n)] non-int parameter, instead '\(param ?? "")'"); continue }
            #expect(queue.isOn, "at queued-paste-multiple token '\(qpmul)' [\(n)]")
            guard queue.isOn else { continue }
            #expect(value <= queue.size, "at queued-paste-multiple token '\(qpmul)' [\(n)]")
            guard queue.size > 0 else { print("kinda fishy, was this intentional? queue size is 0 at queued-paste-multiple token '\(qpmul)' [\(n)]"); continue }
            num = value
            sep = queuedPasteMultipleSeparator
          }
          if useReplayingMode {
            try queue.replaying()
          } else {
            try queue.putNextOnClipboard()
          }
          if num == 1 {
            // queuedPasteMultiple calls queuedPaste here, so this also effectively replicates AppModel.queuedPaste
            await withCheckedContinuation { continuation in
              clipboard.invokeApplicationPaste(then: continuation.resume)
              //print("pasted '\(clipboard.currentText ?? "?")'")
            }
            try queue.dequeue()
            break
          }
          // this part is queuedPasteMultipleIterator
          var cnt = 0
          while true {
            guard num > 0 && cnt < num, let index = queue.headIndex, index < history.count else {
              break
            }
            await withCheckedContinuation { continuation in
              clipboard.invokeApplicationPaste(then: continuation.resume)
              //print("pasted '\(clipboard.currentText ?? "?")'")
            }
            cnt += 1
            if queue.isEmpty || cnt >= num {
              break
            }
            if !sep.isEmpty {
              clipboard.copy(sep)
              await withCheckedContinuation { continuation in
                clipboard.invokeApplicationPaste(then: continuation.resume)
                //print("pasted '\(clipboard.currentText ?? "?")'")
              }
            }
            try queue.bulkDequeueNext()
          }
          // this from the end of queuedPasteMultiple
          try self.queue.finishBulkDequeue()
        
        case .qpmuls:
          guard let param = param, !param.isEmpty else { print("unexpected paste-multiple-separator token '\(qpmuls)' [\(n)] parameter empty"); continue }
          queuedPasteMultipleSeparator = param
        
        case .del: // replicates AppModel.deleteClip & deleteHighlightedClip 
          guard let i = value else { print("unexpected delete-item token '\(del)' [\(n)] non-int parameter, instead '\(param ?? "")'"); continue }
          #expect(i < history.count, "at delete-item token '\(del)' [\(n)]")
          guard i < history.count else { continue }
          lastDeleted = history.all[i].text ?? ""
          if i < queue.size {
            try queue.remove(atIndex: i)
          } else {
            history.remove(atIndex: i)
          }
          coreDataStack.saveContext()
        //case .qdel: had this separate op but combined them to better replicate AppModel.deleteClip
        //  guard let i = value else { print("unexpected delete-queue-item token '\(qdel)' [\(n)] non-int parameter, instead '\(param ?? "")'"); continue }
        //  #expect(queue.isOn, "at delete-queue-item token '\(qdel)' [\(n)]")
        //  guard queue.isOn else { continue }
        //  #expect(i < queue.size, "index \(i) should be within queue but isn't at delete-queue-item token '\(qdel)' [\(n)]")
        //  guard i < queue.size else { continue }
        //  lastDeleted = history.all[i].text ?? ""
        //  try queue.remove(atIndex: i)
        //  coreDataStack.saveContext()
        case .deleted:
          guard let param = param, !param.isEmpty else { print("unexpected match-deleted token '\(deleted)' [\(n)] parameter empty"); continue }
          guard let last = lastDeleted else { print("unexpected match-deleted token '\(deleted)' [\(n)] when no record of a delete"); continue }
          #expect(param == last)
        
        case .clear: // replicates AppModel.deleteHistoryClips
          queue.off()
          history.clear()
          coreDataStack.saveContext()
          #expect(queue.size == 0, "at clear-history token \(clear) [\(n)]")
          #expect(history.count == 0, "at clear-history token \(clear) [\(n)]")
        
        case .isclip:
          guard let param = param, !param.isEmpty else { print("unexpected is-clip token '\(isclip)' [\(n)] parameter empty"); continue }
          let txt = clipboard.currentText
          #expect(txt != nil, "empty clipboard at is-clip token '\(isclip)' [\(n)]")
          guard let txt = txt else { continue }
          #expect(param == txt)
          
        case .pasted:
          guard let param = param, !param.isEmpty else { print("unexpected match-all-pasted token '\(pasted)' [\(n)] parameter empty"); continue }
          #expect(param == clipboard.accumulatedTextBuffer)
        
        case .begcmp:
          guard historyMatchIndex == nil else { print("unexpected second begin-history-compare '\(begcmp)' [\(n)]"); continue }
          historyMatchIndex = history.count - 1
          compareToEnd = true
        case .begcmpq:
          guard historyMatchIndex == nil else { print("unexpected second being-queue-compare token '\(begcmpq)' [\(n)]"); continue }
          historyMatchIndex = queue.size - 1
          compareToEnd = true
        case .begcmpi:
          guard historyMatchIndex == nil else { print("unexpected second begin-from-index-compare '\(begcmpi)' [\(n)]"); continue }
          historyMatchIndex = history.count - 1
          compareToEnd = false
        case .endcmp:
          guard let i = historyMatchIndex else { print("unexpected end-compare token '\(endcmp)' [\(n)] without previous begin-xx-compare"); continue }
          if compareToEnd {
            #expect(i == -1, "\(i+1) more history items not compareed [\(n)]")
          }
          historyMatchIndex = nil
        
        case .other:
          if let i = historyMatchIndex {
            #expect(history.count > 0, "expected history non-empty and '\(str)' next [\(n)]")
            #expect(i >= 0, "expected more history items with '\(str)' next  [\(n)]")
            guard i >= 0, history.count > 0 else { continue } // don't bother decrementing index
            let clip = history.all[i]
            #expect(clip.isText, "at history index \(i) [\(n)]")
            if let cliptxt = clip.text {
              #expect(cliptxt == str, "at history index \(i) [\(n)]")
            }
            historyMatchIndex = i - 1
            
          } else { // replicates AppModel.clipboardChanged
            let newcc = ClipContent(type: NSPasteboard.PasteboardType.string.rawValue,
                                    value: str.data(using: .utf8))
            let newclip = Clip(contents: [newcc], application: ProcessInfo.processInfo.processName)
            if queue.isOn {
              try queue.add(newclip)
            } else {
              history.add(newclip)
            }
            coreDataStack.saveContext()
          }
          
        } // switch op
        
        if logQueueAfterEveryOp {
          print("after '\(str)': \(queue.dump)")
          if logClipObjPointers && history.count > 0 { print("\(history.ptrs)") }
        }
      } // loop over tokens in str
      
    } // loop over str
    
    if logQueueAfterRun && !logQueueAfterEveryOp {
      print("after run': \(queue.dump)")
      if logClipObjPointers && history.count > 0 { print("\(history.ptrs)") }
    }
  }
  
}

// allow unqualified abbreviated name in run definitions
var start =     QueueSims.Token.start.rawValue
var canc =      QueueSims.Token.canc.rawValue
var begdq =     QueueSims.Token.begdq.rawValue
var qcopy =     QueueSims.Token.qcopy.rawValue
var undo =      QueueSims.Token.undo.rawValue
var qfromh =    QueueSims.Token.qfromh.rawValue
var paste =     QueueSims.Token.paste.rawValue
var qpaste =    QueueSims.Token.qpaste.rawValue
var adv =       QueueSims.Token.adv.rawValue
var qpall =     QueueSims.Token.qpall.rawValue
var qpmul =     QueueSims.Token.qpmul.rawValue
var qpmuls =    QueueSims.Token.qpmuls.rawValue
var autoron =   QueueSims.Token.autoron.rawValue
var autoroff =  QueueSims.Token.autoroff.rawValue
var del =       QueueSims.Token.del.rawValue
var clear =     QueueSims.Token.clear.rawValue
var hoff =      QueueSims.Token.hoff.rawValue
var hon =       QueueSims.Token.hon.rawValue
var stay =      QueueSims.Token.stay.rawValue
var nostay =    QueueSims.Token.nostay.rawValue
var isqon =     QueueSims.Token.isqon.rawValue
var isqoff =    QueueSims.Token.isqoff.rawValue
var issize =    QueueSims.Token.issize.rawValue
var iscnt =     QueueSims.Token.iscnt.rawValue
var isclip =    QueueSims.Token.isclip.rawValue
var pasted =    QueueSims.Token.pasted.rawValue
var deleted =   QueueSims.Token.deleted.rawValue
var begcmp =    QueueSims.Token.begcmp.rawValue
var begcmpq =   QueueSims.Token.begcmpq.rawValue
var begcmpi =   QueueSims.Token.begcmpi.rawValue
var endcmp =    QueueSims.Token.endcmp.rawValue

extension QueueSims.Token {
  static func parseOpAndParam(_ str: String) -> (QueueSims.Token, String?, Int?) {
    if let token = QueueSims.Token(rawValue: str) { // empty string nicely matches .other already
      return (token, nil, nil)
    }
    if let colon = str.firstIndex(where: { $0 == ":" }) {
      let prefix = String(str[...colon])
      let param = String(str[str.index(after: colon)...])
      if !param.isEmpty, let token = QueueSims.Token(rawValue: prefix) {
        return (token, param, Int(param))
      }
    }
    return (.other, nil, nil)
  }
}

extension QueueSims {
  func isDelimiter(_ c: Character) -> Bool { delimiters.contains(c) } // must mutate b/c delimiters is lazy  
  func stopTrimming(_ c: Character) -> Bool { !trimDelimiters.contains(c) }
  
  func nextTokenString(from src: inout String) -> String? {
    // consume leading whitespace, delimiters left over from last token (thus ",," gets eaten, doesn't return empty str) 
    if let pastTrim = src.firstIndex(where: stopTrimming), pastTrim > src.startIndex {
      src.removeSubrange(src.startIndex ..< pastTrim)
    }
    if src.isEmpty { return nil }
    
    // consume comments
    if commentDelimiters.contains(src.first!) {
      let match = String(src.removeFirst())
      src.removeSubrange(src.startIndex ..< src.index(after: src.startIndex))
      if let next = src.firstIndex(where: { $0 == match.first }) {
        src.removeSubrange(src.startIndex ... next)
        // find whitespace again after the closed comment
        if let pastMoreTrim = src.firstIndex(where: stopTrimming), pastMoreTrim > src.startIndex {
          src.removeSubrange(src.startIndex ..< pastMoreTrim)
        }
      } else {
        src.removeAll() // trailing comment without close delimeter, eat the rest of the str
      }
    }
    if src.isEmpty { return nil }
    
    // match to self-containted tokens
    for tokenstr in selfContainedTokenStrings {
      if src.starts(with: tokenstr) {
        src.removeSubrange(src.startIndex ..< src.index(src.startIndex, offsetBy: tokenstr.count))
        return tokenstr
      }
    }
    
    // parse token string to the next delimiter
    var tokenstr = ""
    if keepDelimiters.contains(src.first!) {
      tokenstr += String(src.removeFirst())
    }
    if let next = src.firstIndex(where: isDelimiter) {
      tokenstr += src.prefix(upTo: next)
      if skipDelimiters.contains(src[next]) {
        src.removeSubrange(src.startIndex ... next)
      } else {
        src.removeSubrange(src.startIndex ..< next)
      }
    } else {
      tokenstr += src
      src.removeAll()
    }
    return tokenstr
  }
}

// support `nop()` lins allowing breakpoint at what would be the end of a block
func nop() { }
