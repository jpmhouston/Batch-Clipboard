//
//  TestQueue.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2025-07-30.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//

// swiftlint:disable file_length
// swiftlint:disable function_body_length
// swiftlint:disable cyclomatic_complexity
import Testing
import AppKit

@Suite("Queue action simulations", .serialized)
class QueueSims {
  
  // TODO: maybe allow expectations against degenerate cases, like queued-paste when nothing queued
  
  enum Token: String, CaseIterable {
    case start = "/s"       // start queueing
    case canc = "/c"        // cancel queue
    case begdq = "/r"       // start dequeueing (replaying) 
    case qcopy = "/k:"      // queued copy that implicitly starts queueing 
    case undo = "/u"        // undo most recent copy
    case qagain = "/br"     // replay last queue batch
    case qfromh = "/f:"     // start queue from a history index (counting from most recent)
    case paste = "/po"      // paste only without advancing
    case qpaste = "/p>"     // paste and advance
    case adv = "/>"         // advance
    case qpall = "/pa"      // paste all
    case qpmul = "/p:"      // paste multiple
    case qpmuls = "/i:"     // separtor inbetween paste multiple (avoid: sp tab newln comma slash v.bar hash)
    case autoron = "/a+"    // auto-replay mode on (default) 
    case autoroff = "/a-"   // auto-replay mode off (even though this mode no longer used by app)
    case del = "/dh:"       // delete with history index (counting from most recent)
    case qdel = "/dq:"      // delete with queue index (counting from most recent)
    case clear = "/w"       // clear all
    case hoff = "/h-"       // history off
    case hon = "/h+"        // history on (default)
    case stay = "/m+"       // stay mode on, queueing remains on when queue emptied (use after `start`)
    case nostay = "/m-"     // stay mode off, emptying queue turns it off (default)
    case isqon = "/q+"      // check if queue is on
    case isqoff = "/q-"     // check if queue is off
    case issize = "/q:"     // check if queue the expected size
    case iscnt = "/n:"      // check if history has the expected count
    case isclip = "/c:"     // compare string against clipboard
    case pasted = "/e:"     // compare string against everything pasted
    case deleted = "/l:"    // compare string against last item deleted
    case begcmph = "/h["    // compare to all history begin
    case begcmphi = "/h[:"  // compare to history being, starting at index
    case begcmpq = "/q["    // compare to queue being, starting at least recent
    case begcmpqi = "/q[:"  // compare to queue being, starting at index
    case endcmp = "/]"      // compare to all history end (and can also end with another begcmpXX)
    case dump = "/?"        // log the state of the history & queue
    case other = ""         // handy to have enum case for a str value instead of a token
  }
  
  let coreDataStack: CoreDataManager
  let clipboard: Clipboard
  let history: History
  let queue: ClipboardQueue
  var historyMatchIndex: Int?
  var queueMatchIndex: Int?
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
  }
  
  let logQueueAfterEveryOp = false
  let logClipObjPointers = false
  let logQueueAfterRun = false
  
  static let smoke = [ "#sample# " +      hon + "h1,h2" + start + "qA,qB,qC" + iscnt+"2" + issize+"3" + qpaste + qpaste + issize+"1" + canc + isqoff + iscnt+"5" +
                                            pasted+"qAqB" + begcmph + "h1,h2,qA,qB,qC" + endcmp ]
  
  static let paste1EmptyH = [ "#paste1# " +               hon + start + "qA,qB" + issize+"2" + qpaste + isqon + issize+"1" ]
  static let pasteAllEmptyH = [ "#pasteAll# " +           hon + start + "qA,qB" + issize+"2" + iscnt+"0" + qpaste + qpaste + isqoff + iscnt+"2" ]
  static let paste1plusH = [ "#paste1+H# " +              hon + "h1,h2" + start + "qA,qB" + issize+"2" + qpaste + isqon + issize+"1" + iscnt+"2" ]
  static let pasteAllplusH = [ "#pasteAll+H# " +          hon + "h1,h2" + start + "qA,qB" + issize+"2" + qpaste + qpaste + isqoff + iscnt+"4" ]
  static let paste1Hoff = [ "#paste1-H# " +               hoff + start + "qA,qB" + issize+"2" + qpaste + isqon + issize+"1" ]
  static let pasteAllHoff = [ "#pasteAll-H# " +           hoff + start + "qA,qB" + issize+"2" + qpaste + qpaste + isqoff ]
//  static let queueAgainClearsB = [ "#QQ->-H# " +          hoff + start + "qA,qB" + qpaste + qpaste + isqoff + isbcnt+"2" + start + isbcnt+"0" ]
//  static let queueAfterCancClearsB = [ "#QXQ->-H# " +     hoff + start + "qA,qB" + canc + isqoff + isbcnt+"2" + start + isbcnt+"0" ]
  
  static let pmultAllEmptyH = [ "#pmultAll# " +           hon + start + "qA,qB,qC" + qpall + isqoff + pasted+"qAqBqC" ]
  static let pmult1EmptyH = [ "#pmult# " +                hon + start + "qA,qB,qC" + qpmul+"1" + issize+"2" + pasted+"qA" ]
  static let pmultEmptyH = [ "#pmult# " +                 hon + start + "qA,qB,qC" + qpmul+"2" + issize+"1" + pasted+"qAqB" ]
  static let pmultWSepEmptyH = [ "#pmult+,# " +           hon + start + "qA,qB,qC" + qpmuls+"." + qpmul+"2" + isqon + pasted+"qA.qB" ]
  static let pmultAllplusH = [ "#pmultAll+H# " +          hon + "h1,h2" + start + "qA,qB,qC" + qpall + isqoff + iscnt+"5" + pasted+"qAqBqC" ]
  static let pmultplusH = [ "#pmult+H# " +                hon + "h1,h2" + start + "qA,qB,qC" + qpmul+"2" + issize+"1" + pasted+"qAqB" ]
  static let pmultAllHoff = [ "#pmultAll-H# " +           hoff + start + "qA,qB,qC" + qpall + isqoff + pasted+"qAqBqC" ]
  static let pmultHoff = [ "#pmultH-# " +                 hoff + start + "qA,qB,qC" + qpmul+"2" + issize+"1" + pasted+"qAqB" ]
  
  static let queueFromHThenPaste = [ "#qFromH# " +        hon + "h1,h2,h3" + qfromh+"1" + iscnt+"3" + begcmpq + "h2,h3" + endcmp + qpaste + qpaste + isqoff + iscnt+"3" +
                                                            pasted+"h2h3" + begcmph + "h1,h2,h3" + endcmp ]
  static let queueFromHThenCanc = [ "#q&cancFromH# " +    hon + "h1,h2,h3" + qfromh+"1" + canc + isqoff + iscnt+"3" + begcmph + "h1,h2,h3" + endcmp ]
  static let queueAllFromH = [ "#qAllFromH# " +           hon + "h1,h2,h3" + qfromh+"2" + iscnt+"3" + begcmpq + "h1,h2,h3" + endcmp + qpmul+"3" + pasted+"h1h2h3" ]
  static let queue1FromH = [ "#q1FromH# " +               hon + "h1,h2,h3" + qfromh+"0" + iscnt+"3" + begcmpq + "h3" + endcmp + qpaste + pasted+"h3" + begcmph + "h1,h2,h3" + endcmp ]
  
  static let delFromH = [ "#delFromH# " +                 hon + "h1,h2,h3" + iscnt+"3" + del+"1" + iscnt+"2" + begcmph + "h1,h3" + endcmp ]
  static let delFromHOldest = [ "#delFromH-># " +         hon + "h1,h2,h3" + del+"2" + begcmph + "h2,h3" + endcmp + del+"1" + begcmph + "h3" + endcmp + del+"0" + iscnt+"0" ]
  static let delFromHNewest = [ "#delFromH<-# " +         hon + "h1,h2,h3" + del+"0" + begcmph + "h1,h2" + endcmp + del+"0" + begcmph + "h1" + endcmp + del+"0" + iscnt+"0" ]
  static let delFromHplusQ = [ "#delFromH+Q# " +          hon + "h1,h2,h3" + start + "qA,qB" + issize+"2" + iscnt+"3" + del+"1" + iscnt+"2" + begcmph + "h1,h3" + begcmpq + "qA,qB" + endcmp ]
  static let delFromHplusQOldest = [ "#delFromH+Q-># " +  hon + "h1,h2" + start + "qA" + del+"1" + begcmph + "h2" + endcmp + del+"0" + iscnt+"0" + begcmpq + "qA" + endcmp ]
  static let delFromHplusQNewest = [ "#delFromH+Q<-# " +  hon + "h1,h2" + start + "qA" + del+"0" + begcmph + "h1" + endcmp + del+"0" + iscnt+"0" + begcmpq + "qA" + endcmp ]
  
  static let delFromQEmptyH = [ "#delFromQ# " +           hon + start + "qA,qB,qC" + issize+"3" + qdel+"1" + issize+"2" + begcmpq + "qA,qC" + endcmp ]
  static let delFromQEmptyHOldest = [ "#delFromQ0H-># " + hon + start + "qA,qB,qC" + qdel+"2" + begcmpq + "qB,qC" + endcmp + qdel+"1" + begcmpq + "qC" + endcmp + qdel+"0" + isqoff ]
  static let delFromQEmptyHNewest = [ "#delFromQ0H<-# " + hon + start + "qA,qB,qC" + qdel+"0" + begcmpq + "qA,qB" + endcmp + qdel+"0" + begcmpq + "qA" + endcmp + qdel+"0" + isqoff ]
  static let delFromQplusH = [ "#delFromQ+H# " +          hon + "h1" + start + "qA,qB,qC" + iscnt+"1" + issize+"3" + qdel+"1" + issize+"2" + begcmpq + "qA,qC" + endcmp ]
  static let delFromQplusHOldest = [ "#delFromQ+H#-># " + hon + "h1" + start + "qA,qB,qC" + qdel+"2" + issize+"2" + begcmpq + "qB,qC" + endcmp + qdel+"1" +
                                                            begcmpq + "qC" + endcmp + qdel+"0" + isqoff + iscnt+"1" ]
  static let delFromQplusHNewest = [ "#delFromQ+H<-# " +  hon + "h1" + start + "qA,qB,qC" + qdel+"0" + issize+"2" + begcmpq + "qA,qB" + endcmp + qdel+"0" +
                                                            begcmpq + "qA" + endcmp + qdel+"0" + isqoff + iscnt+"1" ]
  static let delFromQHoff = [ "#delFromQ-H# " +           hoff + start + "qA,qB,qC" + issize+"3" + qdel+"1" + issize+"2" + begcmpq + "qA,qC" + endcmp ]
  static let delFromQHoffOldest = [ "#delFromQ-H-># " +   hoff + start + "qA,qB,qC" + qdel+"2" + begcmpq + "qB,qC" + endcmp + qdel+"1" + begcmpq + "qC" + endcmp + qdel+"0" + isqoff ]
  static let delFromQHoffNewest = [ "#delFromQ-H<-# " +   hoff + start + "qA,qB,qC" + qdel+"0" + begcmpq + "qA,qB" + endcmp + qdel+"0" + begcmpq + "qA" + endcmp + qdel+"0" + isqoff ]
  
  static let undoFromQHoff = [ "#undoFromQ-H# " +         hoff + start + "qA,qB,qC" + issize+"3" + undo + issize+"2" + begcmpq + "qA,qB" + endcmp ]
  static let undoFromQHon = [ "#undoFromQ+H# " +          hon + start + "qA,qB,qC" + issize+"3" + undo + issize+"2" + begcmpq + "qA,qB" + endcmp ]
  static let undoFromH = [ "#undoFromH# " +               hon + "h1,h2,h3" + iscnt+"3" + undo + iscnt+"2" + begcmph + "h1,h2" + endcmp ]
  
  static let clearH = [ "#clearH# " +                     hon + "h1,h2" + clear + iscnt+"0" ]
  static let clearHandQ = [ "#clearH+Q# " +               hon + "h1,h2" + start + "qA,qB" + clear + isqoff + iscnt+"0" ]
  static let clearQnoH = [ "#clearQH0# " +                hon + start + "qA,qB" + clear + isqoff ]
  static let clearQHoff = [ "#clearQH-# " +               hoff + start + "qA,qB" + clear + isqoff ]
  
  // enabling several at a time was sometimes causing coredata exceptions & crashes,
  // is it happning less now or not at all?
  
  @Test("queue simulator", arguments: [ smoke,
                                        //paste1EmptyH, pasteAllEmptyH, paste1plusH, pasteAllplusH, paste1Hoff, pasteAllHoff,
                                        //pmultAllEmptyH, pmult1EmptyH, pmultEmptyH, pmultWSepEmptyH, pmultAllplusH, pmultplusH, pmultAllHoff, pmultHoff,
                                        //queueFromHThenPaste, queueFromHThenCanc, queueAllFromH, queue1FromH, delFromH, delFromHOldest, delFromHNewest,
                                        //delFromHplusQ, delFromHplusQOldest, delFromHplusQNewest, delFromQEmptyH,
                                        //delFromQEmptyHOldest, delFromQEmptyHNewest, delFromQplusH, delFromQplusHOldest, delFromQplusHNewest,
                                        //delFromQHoff, delFromQHoffOldest, delFromQHoffNewest,
                                        //undoFromQHoff, undoFromQHon, undoFromH,
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
        case .hon: history.loadList()
        case .hoff: history.offloadList()
        case .stay: queue.stayOnWhenEmptied = true
        case .nostay: queue.stayOnWhenEmptied = false
          
        case .start: // replicates AppModel.startQueueMode 
          guard !queue.isOn else { print("unexpected second start-queueing token (\(startTokenname) \(start)) [\(n)]"); continue }
          queue.on()
          #expect(queue.isOn, "at start-queueing token (\(startTokenname) \(start)) [\(n)]")
        case .canc: // replicates AppModel.cancelQueueMode
          if !queue.isOn { print("unexpected cancel-queueing token (\(cancTokenname) \(canc)) [\(n)] without previous start-queueing '\(start)'") }
          try queue.off()
          #expect(!queue.isOn, "at cancel-queueing token (\(cancTokenname) \(canc)) [\(n)]")
        case .begdq: // replicates AppModel.startReplay
          guard queue.isOn else { print("unexpected queueing already on at start-dequeueing token (\(begdqTokenname) \(begdq)) [\(n)]"); continue }
          guard queue.size > 0 else { print("unexpected queue non-empty at start-dequeueing token (\(begdqTokenname) \(begdq)) [\(n)]"); continue }
          try queue.replaying()
        
        case .qagain: // replicates AppModel.replayBatch(nil)
          #expect(!queue.isOn, "at replay-last-queue token (\(qagainTokenname) \(qagain)) [\(n)]")
          #expect(!queue.isBatchEmpty, "at replay-last-queue token (\(qagainTokenname) \(qagain)) [\(n)]")
          try queue.replayQueue()
          try queue.replaying()
        case .qfromh: // replicates AppModel.replayFromHistory
          guard let i = value, i >= 0 else { print("unexpected replay-from-history token (\(qfromhTokenname) \(qfromh)) [\(n)] non-+ve-int parameter, instead '\(param ?? "")'"); continue }
          #expect(!queue.isOn, "at replay-from-history token (\(qfromhTokenname) \(qfromh)) [\(n)]")
          #expect(i < history.count, "at replay-from-history token (\(qfromhTokenname) \(qfromh)) [\(n)]")
          try queue.replayClips(history.clipsFromIndex(i))
          try queue.replaying()
        
        case .isqon:
          #expect(queue.isOn, "at is-queue-on token (\(isqonTokenname) \(isqon)) [\(n)]")
        case .isqoff:
          #expect(!queue.isOn, "at is-queue-off token (\(isqoffTokenname) \(isqon)) [\(n)]")
        case .issize:
          guard let sz = value, sz >= 0 else { print("unexpected is-size token (\(issizeTokenname) \(issize)) [\(n)] non-+ve-int parameter, instead '\(param ?? "")'"); continue }
          #expect(queue.isOn, "at is-size token \(issize) [\(n)]")
          guard queue.isOn else { continue }
          #expect(sz == queue.size, "at is-size token (\(issizeTokenname) \(issize)) [\(n)]")
        case .iscnt:
          guard let cnt = value, cnt >= 0 else { print("unexpected is-history-count token (\(iscntTokenname) \(iscnt)) [\(n)] non-+ve-int parameter, instead '\(param ?? "")'"); continue }
          #expect(history.count == cnt, "at is-history-count token (\(iscntTokenname) \(iscnt)) [\(n)]")
        
        case .qcopy: // replicates AppModel.queuedCopy + clipboardChanged 
          guard let param = param, !param.isEmpty else { print("unexpected queued-copy token (\(qcopyTokenname) \(qcopy)) [\(n)] parameter empty"); continue }
          if !queue.isOn {
            queue.on()
          }
          let newcc = ClipContent.create(type: NSPasteboard.PasteboardType.string.rawValue,
                                         value: param.data(using: .utf8))
          let newclip = Clip.create(withContents: [newcc], application: ProcessInfo.processInfo.processName)
          try queue.add(newclip)
        
        case .undo: // replicates AppModel.undoLastCopy
          if !queue.isEmpty {
            try queue.remove(atIndex: 0)
          } else {
            guard let clip = history.first else { print("kinda fishy, was this intentional? no first history item at undo-copy token (\(undoTokenname) \(undo)) [\(n)]"); return }
            history.remove(clip)
          }
        
        case .paste:
          // tell clipboard to paste
          await withCheckedContinuation { continuation in
            clipboard.invokeApplicationPaste(then: continuation.resume)
          }
        case .qpaste: // replicates AppModel.queuedPaste
          guard queue.isOn else { print("unexpected queueing not on at queued-paste token (\(qpasteTokenname) \(qpaste)) [\(n)]"); continue }
          guard queue.size > 0 else { print("unexpected queue not be empty at queued-paste token (\(qpasteTokenname) \(qpaste)) [\(n)]"); continue }
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
        case .adv: // replicates AppModel.advanceQueue
          #expect(queue.isOn, "at advance-in-queue token (\(advTokenname) \(adv)) [\(n)]")
          guard queue.isOn else { continue }
          #expect(queue.size > 0, "at advance-in-queue token (\(advTokenname) \(adv)) [\(n)]")
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
            #expect(queue.isOn, "at queued-paste-all token (\(qpallTokenname) \(qpall)) [\(n)]")
            guard queue.isOn else { continue }
            guard queue.size > 0 else { print("kinda fishy, was this intentional? queue size is 0 at queued-paste-all token (\(qpallTokenname) \(qpall)) [\(n)]"); continue }
            num = queue.size
            sep = ""
          } else {
            guard let n = value, n >= 0 else { print("unexpected queued-paste-multiple token (\(qpmulTokenname) \(qpmul)) [\(n)] non-+ve-int parameter, instead '\(param ?? "")'"); continue }
            #expect(queue.isOn, "at queued-paste-multiple token (\(qpmulTokenname) \(qpmul)) [\(n)]")
            guard queue.isOn else { continue }
            #expect(n <= queue.size, "at queued-paste-multiple token (\(qpmulTokenname) \(qpmul)) [\(n)]")
            guard queue.size > 0 else { print("kinda fishy, was this intentional? queue size is 0 at queued-paste-multiple token (\(qpmulTokenname) \(qpmul)) [\(n)]"); continue }
            num = n
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
            guard num > 0 && cnt < num else {
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
          guard let param = param, !param.isEmpty else { print("unexpected paste-multiple-separator token (\(qpmulsTokenname) \(qpmuls)) [\(n)] parameter empty"); continue }
          queuedPasteMultipleSeparator = param
        
        case .del: // replicates AppModel.deleteHistoryClip 
          guard let i = value, i >= 0 else { print("unexpected delete-item token (\(delTokenname) \(del)) [\(n)] non-+ve-int parameter, instead '\(param ?? "")'"); continue }
          #expect(i < history.count, "at delete-item token (\(delTokenname) \(del)) [\(n)]")
          guard i < history.count else { continue }
          lastDeleted = history.all[i].text ?? ""
          history.remove(atIndex: i)
        case .qdel: // replicates AppModel.deleteQueueClip
          guard let i = value, i >= 0 else { print("unexpected delete-queue-item token (\(qdelTokenname) \(qdel)) [\(n)] non-+ve-int parameter, instead '\(param ?? "")'"); continue }
          #expect(queue.isOn, "at delete-queue-item token (\(qdelTokenname) \(qdel)) [\(n)]")
          guard queue.isOn else { continue }
          #expect(i < queue.size, "at delete-queue-item token (\(qdelTokenname) \(qdel)) [\(n)]")
          guard i < queue.size else { continue }
          lastDeleted = queue.clips[i].text ?? ""
          try queue.remove(atIndex: i)
        case .deleted:
          guard let param = param, !param.isEmpty else { print("unexpected match-deleted token (\(deletedTokenname) \(deleted)) [\(n)] parameter empty"); continue }
          guard let last = lastDeleted else { print("unexpected match-deleted token (\(deletedTokenname) \(deleted)) [\(n)] when no record of a delete"); continue }
          #expect(param == last)
        
        case .clear: // replicates AppModel.deleteClips
          try queue.clear()
          history.clearHistory()
          #expect(queue.size == 0, "at clear-history token \(clear) [\(n)]")
          #expect(history.count == 0, "at clear-history token \(clear) [\(n)]")
        
        case .isclip:
          guard let param = param, !param.isEmpty else { print("unexpected is-clip token (\(isclipTokenname) \(isclip)) [\(n)] parameter empty"); continue }
          let txt = clipboard.currentText
          #expect(txt != nil, "empty clipboard at is-clip token (\(isclipTokenname) \(isclip)) [\(n)]")
          guard let txt = txt else { continue }
          #expect(param == txt)
          
        case .pasted:
          guard let param = param, !param.isEmpty else { print("unexpected match-all-pasted token (\(pastedTokenname) \(pasted)) [\(n)] parameter empty"); continue }
          #expect(param == clipboard.accumulatedTextBuffer)
        
        case .begcmph:
          #expect(history.count > 0, "at being-history-compare token (\(begcmphTokenname) \(begcmph)) [\(n)]")
          historyMatchIndex = history.count - 1
          queueMatchIndex = nil
          compareToEnd = true
        case .begcmphi:
          guard let i = value, i >= 0 else { print("unexpected being-history-compare token (\(begcmphiTokenname) \(begcmphi)) [\(n)] non-+ve-int parameter, instead '\(param ?? "")'"); continue }
          #expect(i < history.count, "at being-history-compare token (\(begcmphiTokenname) \(begcmphi)) [\(n)]") 
          historyMatchIndex = i
          queueMatchIndex = nil
          compareToEnd = false
        case .begcmpq:
          #expect(queue.size > 0, "at being-queue-compare token (\(begcmpqTokenname) \(begcmpq)) [\(n)]")
          queueMatchIndex = queue.size - 1
          historyMatchIndex = nil
          compareToEnd = true
        case .begcmpqi:
          guard let i = value, i >= 0 else { print("unexpected being-queue-compare token (\(begcmpqiTokenname) \(begcmpqi)) [\(n)] non-+ve-int parameter, instead '\(param ?? "")'"); continue }
          #expect(i < queue.size, "at being-queue-compare token (\(begcmpqiTokenname) \(begcmpqi)' [\(n)]") 
          queueMatchIndex = i
          historyMatchIndex = nil
          compareToEnd = true
        case .endcmp:
          if let i = historyMatchIndex {
            if compareToEnd {
              #expect(i == -1, "\(i+1) more history items not compareed at end-compare token (\(endcmpTokenname) \(endcmp)) [\(n)] ")
            }
            historyMatchIndex = nil
          } else if let i = queueMatchIndex {
            if compareToEnd {
              #expect(i == -1, "\(i+1) more queue items not compareed at end-compare token (\(endcmpTokenname) \(endcmp)) [\(n)] ")
            }
            queueMatchIndex = nil
          } else {
            print("unexpected end-compare token (\(endcmpTokenname) \(endcmp)) [\(n)] without previous begin-xx-compare")
            continue
          }
        
        case .other:
          if let i = historyMatchIndex {
            #expect(history.count > 0, "expected history non-empty and '\(str)' next [\(n)]")
            #expect(i >= 0, "expected more history items with '\(str)' next  [\(n)]")
            guard i >= 0, history.count > 0 else { continue } // don't decrement index past -1
            let clip = history.all[i]
            #expect(clip.isText, "at history index \(i) [\(n)]")
            if let cliptxt = clip.text {
              #expect(cliptxt == str, "at history index \(i) [\(n)]")
            }
            historyMatchIndex = i - 1
            
          } else if let i = queueMatchIndex {
            #expect(queue.size > 0, "expected queue non-empty and '\(str)' next [\(n)]")
            #expect(i >= 0, "expected more queue items with '\(str)' next  [\(n)]")
            guard i >= 0, i < queue.size else { continue } // don't decrement index past -1
            let clip = queue.clips[i]
            #expect(clip.isText, "at queue index \(i) [\(n)]")
            if let cliptxt = clip.text {
              #expect(cliptxt == str, "at queue index \(i) [\(n)]")
            }
            queueMatchIndex = i - 1
            
          } else { // replicates AppModel.clipboardChanged
            let newcc = ClipContent.create(type: NSPasteboard.PasteboardType.string.rawValue,
                                           value: str.data(using: .utf8))
            let newclip = Clip.create(withContents: [newcc], application: ProcessInfo.processInfo.processName)
            if queue.isOn {
              try queue.add(newclip)
            } else {
              history.add(newclip)
            }
          }
        
        case .dump:
          print(queue.dump)
        } // switch op
        
        if logQueueAfterEveryOp {
          if op != .dump { print("after '\(str)': \(queue.dump)") }
          if logClipObjPointers && history.count > 0 { print("\(history.ptrs)") }
        }
      } // loop over tokens in str
      
    } // loop over str
    
    if logQueueAfterRun && !logQueueAfterEveryOp {
      print("after run: \(queue.dump)")
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
var qagain =    QueueSims.Token.qagain.rawValue
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
var qdel =      QueueSims.Token.qdel.rawValue
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
var begcmph =   QueueSims.Token.begcmph.rawValue
var begcmphi =  QueueSims.Token.begcmphi.rawValue
var begcmpq =   QueueSims.Token.begcmpq.rawValue
var begcmpqi =  QueueSims.Token.begcmpqi.rawValue
var endcmp =    QueueSims.Token.endcmp.rawValue
var dump =      QueueSims.Token.dump.rawValue

var startTokenname =      "start"
var cancTokenname =       "canc"
var begdqTokenname =      "begdq"
var qcopyTokenname =      "qcopy"
var undoTokenname =       "undo"
var qagainTokenname =     "qagain"
var qfromhTokenname =     "qfromh"
var pasteTokenname =      "paste"
var qpasteTokenname =     "qpaste"
var advTokenname =        "adv"
var qpallTokenname =      "qpall"
var qpmulTokenname =      "qpmul"
var qpmulsTokenname =     "qpmuls"
var autoronTokenname =    "autoron"
var autoroffTokenname =   "autoroff"
var delTokenname =        "del"
var qdelTokenname =       "qdel"
var clearTokenname =      "clear"
var hoffTokenname =       "hoff"
var honTokenname =        "hon"
var stayTokenname =       "stay"
var nostayTokenname =     "nostay"
var isqonTokenname =      "isqon"
var isqoffTokenname =     "isqoff"
var issizeTokenname =     "issize"
var iscntTokenname =      "iscnt"
var isclipTokenname =     "isclip"
var pastedTokenname =     "pasted"
var deletedTokenname =    "deleted"
var begcmphTokenname =    "begcmph"
var begcmphiTokenname =   "begcmphi"
var begcmpqTokenname =    "begcmpq"
var begcmpqiTokenname =   "begcmpqi"
var endcmpTokenname =     "endcmp"
var dumpTokenname =       "dump"

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

// swiftlint:enable function_body_length
// swiftlint:enable cyclomatic_complexity
// swiftlint:enable file_length
