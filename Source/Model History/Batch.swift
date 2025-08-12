//
//  Batch.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2025-07-15.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//

import AppKit
import CoreData
import KeyboardShortcuts
import Sauce
import os.log

@objc(Batch)
class Batch: NSManagedObject {
  
  @NSManaged public var index: String?
  @NSManaged public var shortcut: Data?
  @NSManaged public var fullname: String?
  @NSManaged public var title: String?
  @NSManaged public var clips: NSOrderedSet?
  
  // like history clips are in backwards order, most recent first
  var first: Clip? { clips?.firstObject as? Clip }
  var last: Clip? { clips?.lastObject as? Clip }
  var mostRecent: Clip? { first }
  var lastToPaste: Clip? { first }
  var leastRecent: Clip? { last }
  var firstToPaste: Clip? { last }
  var count: Int { clips?.count ?? 0 }
  var isEmpty: Bool { clips?.count ?? 0 == 0 }
  
  // MARK: -
  
  static let sortByIndex = NSSortDescriptor(key: #keyPath(Batch.index), ascending: true,
                                            selector: #selector(NSString.localizedStandardCompare(_:)))
  static let sortReverseByIndex = NSSortDescriptor(key: #keyPath(Batch.index), ascending: false,
                                                   selector: #selector(NSString.localizedStandardCompare(_:)))
  
  // TODO: are these computed properties better as a throwing load() functions?
  
  static var saved: [Batch] {
    let fetchRequest = NSFetchRequest<Batch>(entityName: "Batch")
    fetchRequest.sortDescriptors = [Batch.sortByIndex]
    fetchRequest.predicate = NSPredicate(format: "fullname != nil")
    do {
      return try CoreDataManager.shared.context.fetch(fetchRequest)
    } catch {
      os_log(.default, "unhandled error fetching named batches %@", error.localizedDescription)
      return []
    }
  }
  
  static var current: Batch? {
    let fetchRequest = NSFetchRequest<Batch>(entityName: "Batch")
    fetchRequest.sortDescriptors = [Batch.sortByIndex]
    fetchRequest.predicate = NSPredicate(format: "fullname == nil")
    fetchRequest.fetchBatchSize = 1
    do {
      return try CoreDataManager.shared.context.fetch(fetchRequest).first
    } catch {
      os_log(.default, "unhandled error fetching current (un-named) batch %@", error.localizedDescription)
      return nil
    }
  }
  
  static func deleteAll() {
    let fetchRequest = NSFetchRequest<Batch>(entityName: "Batch")
    do {
      let batches = try CoreDataManager.shared.context.fetch(fetchRequest)
      batches.forEach {
        CoreDataManager.shared.context.delete($0)
      }
    } catch {
      os_log(.default, "unhandled error deleting batches %@", error.localizedDescription)
    }
  }
  
  // swiftlint:disable nsobject_prefer_isequal
  // i'm guessing we'd similarly get this error if tried having `-isEqual` instead of `==`:
  //   Class 'Batch' for entity 'Batch' has an illegal override of NSManagedObject -isEqual
  static func == (lhs: Batch, rhs: Batch) -> Bool {
    return lhs.index == rhs.index && lhs.title == rhs.title
  }
  // swiftlint:enable nsobject_prefer_isequal
  
  static func createUnnamed(withClips clips: any Collection<Clip> = []) -> Batch {
    let batch = Batch(context: CoreDataManager.shared.context)
    
    batch.addExistingClips(clips)
    
    CoreDataManager.shared.saveContext()
    return batch
  }
  
  static func create(withName name: String?, index: String? = nil, shortcut: KeyboardShortcuts.Shortcut,
                     clips: any Collection<Clip> = []) -> Batch {
    return create(withName: name, index: index, shortcut: shortcutData(forKeyShortcut: shortcut), clips: clips)
  }
  
  static func create(withName name: String?, index: String? = nil, shortcut: Data? = nil,
                     clips: any Collection<Clip> = []) -> Batch {
    let batch = Batch(context: CoreDataManager.shared.context)
    
    batch.fullname = name
    batch.index = index ?? batch.nextIndex() // TODO: sanitize input index str?
    batch.shortcut = shortcut
    batch.addExistingClips(clips)
    
    batch.makeTruncatedTitle()
    
    CoreDataManager.shared.saveContext()
    return batch
  }
  
  @discardableResult
  func makeTruncatedTitle() -> String {
    var newTitle = ""
    if let fullname = fullname {
      newTitle = fullname.shortened(to: UserDefaults.standard.maxTitleLength)
    }
    title = newTitle
    return newTitle
  }
  
  // MARK: -
  
  var keyShortcut: KeyboardShortcuts.Shortcut? {
    get { Self.keyShortcut(forData: shortcut) }
    set { shortcut = Self.shortcutData(forKeyShortcut: newValue) }
  }
  
  private static func keyShortcut(forData shortcutData: Data?) -> KeyboardShortcuts.Shortcut? {
    if let shortcutData = shortcutData {
      try? JSONDecoder().decode(KeyboardShortcuts.Shortcut.self, from: shortcutData)
    } else {
      nil
    }
  }
  
  private static func shortcutData(forKeyShortcut keyShortcut: KeyboardShortcuts.Shortcut?) -> Data? {
    if let keyShortcut = keyShortcut {
      try? JSONEncoder().encode(keyShortcut)
    } else {
      nil
    }
  }
  
  func setName(to newName: String) {
    // note, doesn't check for uniqueness among all Batch entities
    fullname = newName
    makeTruncatedTitle()
    CoreDataManager.shared.saveContext()
  }
  
  func getClips() -> Set<Clip> {
    (clips?.set as? Set<Clip>) ?? Set()
  }
  
  func getClipsArray() -> [Clip] {
    (clips?.array as? [Clip]) ?? []
  }
  
  func clipAtIndex(_ index: Int) -> Clip? {
    // currently requiring caller to sanity check for index out of bounds
    clips?.object(at: index) as? Clip
  }
  
  // dont need this wrapper function after all, caller can just use `Batch.create()` 
//  func duplicate(withTitle title: String, index: String? = nil, shortcut: Data? = nil) -> Batch {
//    return Batch.create(withTitle: title, index: index, shortcut: shortcut, clips: getClipsArray())
//  }
  
  func addClip(_ clip: Clip) {
    insertIntoClips(clip, at: 0)
    CoreDataManager.shared.saveContext()
  }
  
  func removeClip(_ clip: Clip) {
    removeFromClips(clip)
    CoreDataManager.shared.saveContext()
  }
  
  func clear() {
    guard let clips = clips else {
      return
    } 
    removeFromClips(clips)
    CoreDataManager.shared.saveContext()
  }
  
  func copyClips(from source: Batch) {
    guard self != source, let sourceClipSet = source.clips else {
      return
    }
    clear()
    if sourceClipSet.count == 0 {
      return
    }
    // simply copy in same order, don't have to deliberately insert at index 0 because
    // we know just emptied it of all previous clips 
    addToClips(sourceClipSet)
    CoreDataManager.shared.saveContext()
  }
  
  func addExistingClips(_ sourceClips: any Collection<Clip>) {
    if sourceClips.isEmpty {
      return
    }
    // copy in same order but into index 0 not at the end
    let indexes = NSIndexSet(indexesIn: NSRange(location: 0, length: sourceClips.count))
    if let sourceClipsArray = sourceClips as? Array<Clip> { // yes lamer than polymorphism but also d.r.y.
      insertIntoClips(sourceClipsArray, at: indexes)
    } else {
      insertIntoClips(Array(sourceClips), at: indexes)
    }
    CoreDataManager.shared.saveContext()
  }
  
  // MARK: -
  
  @objc(insertObject:inClipsAtIndex:)
  @NSManaged public func insertIntoClips(_ value: Clip, at idx: Int)

  @objc(removeObjectFromClipsAtIndex:)
  @NSManaged public func removeFromClips(at idx: Int)

  @objc(insertClips:atIndexes:)
  @NSManaged public func insertIntoClips(_ values: [Clip], at indexes: NSIndexSet)

  @objc(removeClipsAtIndexes:)
  @NSManaged public func removeFromClips(at indexes: NSIndexSet)

  @objc(replaceObjectInClipsAtIndex:withObject:)
  @NSManaged public func replaceClips(at idx: Int, with value: Clip)

  @objc(replaceClipsAtIndexes:withClips:)
  @NSManaged public func replaceClips(at indexes: NSIndexSet, with values: [Clip])

  @objc(addClipsObject:)
  @NSManaged public func addToClips(_ value: Clip)

  @objc(removeClipsObject:)
  @NSManaged public func removeFromClips(_ value: Clip)

  @objc(addClips:)
  @NSManaged public func addToClips(_ values: NSOrderedSet)

  @objc(removeClips:)
  @NSManaged public func removeFromClips(_ values: NSOrderedSet)
  
  // MARK: -
  
  private func nextIndex() -> String {
    guard let last = lastIndex(), let lastNum = Int(last) else {
      return "\(maxDigit + 1)"
    }
    return "\(lastNum + 1)"
  }
  
  private func lastIndex() -> String? {
    let fetchRequest = NSFetchRequest<Batch>(entityName: "Batch")
    fetchRequest.sortDescriptors = [Batch.sortReverseByIndex]
    fetchRequest.fetchBatchSize = 1
    do {
      if let last = try CoreDataManager.shared.context.fetch(fetchRequest).first {
        if let num = majorComponentValue(for: last.index) {
          return "\(num + 1)"
        } else {
          return nil
        }
      } else {
        return nil
      }
    } catch {
      os_log(.default, "unhandled error deleting implicit batch %@", error.localizedDescription)
      return nil
    }
  }
  
  // managing the index string TODO: move these functions elsewhere
  
  enum IndexStringStyle { case dottedDecimal, decimalFraction }
  private let style = IndexStringStyle.decimalFraction
  
  private static let minMaxDigits = (0, 9) // except for leading digit, it's max is unbounded
  private let minDigit = Batch.minMaxDigits.0
  private let maxDigit = Batch.minMaxDigits.1
  private let midDigit = (Batch.minMaxDigits.1 - Batch.minMaxDigits.0 + 1) / 2
  
  private func majorComponentValue(for indexStr: String?) -> Int? {
    guard let indexStr = indexStr else { return nil }
    if let div = indexStr.firstIndex(of: ".") {
      return Int(indexStr[..<div])
    } else {
      return Int(indexStr)
    }
  }
  
  private func parseComponentValues(from indexStr: String?) -> [Int] {
    guard let indexStr = indexStr, !indexStr.isEmpty else {
      return []
    }
    if let div = indexStr.firstIndex(of: ".") {
        let majorstr = indexStr[..<div] 
        let major = Int(majorstr) ?? 0
        let minorstr = indexStr[indexStr.index(after: div)...]
        var minorcomponents = switch style {
        case .dottedDecimal: minorstr.components(separatedBy: ".").map { Int($0) }
        case .decimalFraction: minorstr.map { $0.wholeNumberValue }
        }
        if let badidx = minorcomponents.firstIndex(where: { $0 == nil }) {
            minorcomponents.removeSubrange(badidx...)
        }
        return [major] + minorcomponents.map { $0! }
    } else if let major = Int(indexStr) {
        return [major]
    } else {
        return []
    }
  }

  private func buildIndexString(fromComponentValues components: [Int]) -> String {
      switch style {
      case .dottedDecimal:
          return components.map { String($0)}.joined(separator: ".")
      case .decimalFraction:
          guard let first = components.first else { return "" }
          guard components.count > 1 else { return String(first) }
          return String(first) + "." + components[1...].map { String($0)}.joined()
      }
  }
  
  private func indexStringInbetween(_ indexStrA: String?, and indexStrB: String?) -> String {
    let aValues = parseComponentValues(from: indexStrA)
    let bValues = parseComponentValues(from: indexStrB)
    let n = max(aValues.count, bValues.count)
    enum Mode { case done, match(at:Int), inetween(at:Int,Int,Int) }
    var mode: Mode = .match(at: 0)
    var newValues: [Int] = []
    for i in 0 ..< n {
      let a = (i >= aValues.count) ? minDigit : min(maxDigit, max(minDigit, aValues[i]))
      let b = (i >= bValues.count) ? minDigit : min(maxDigit, max(minDigit, bValues[i]))
      // all conditional cases below falltrough to exit loop, continue to iterate again
      switch mode {
      case .match(_):
        // matched up until now
        if a < b {
          if b - a > 1 {
            mode = .inetween(at: i, a+1, b-1)
          } else {
            newValues.insert(a, at: i)
            mode = .inetween(at: i+1, minDigit, maxDigit)
            continue
          }
          
        } else if a == b { // note: this shouldn't be the last iteration
          newValues.insert(a, at: i)
          mode = .match(at: i+1)
          continue
          
        } else { // a > b, only get here in edge cases, find a value following a  
          if i == 0 {
            newValues.insert(a + 1, at: i) // for the first digit, disregarding maxDigit
            mode = .done
          } else if a < maxDigit {
            mode = .inetween(at: i, a+1, maxDigit)
          } else {
            newValues.insert(a, at: i)
            mode = .inetween(at: i+1, minDigit, maxDigit)
            continue
          }
        }
        
        // last iter constrained between adjacent digits (ignore case's last 2 params, only used when loop exits) 
      case let .inetween(at: betweenindex, _, _):
        if betweenindex != i { print("confused 1"); break }
        if aValues[i-i] < maxDigit {
          // including previous digit X, wamt to end up between X.a .. (X+1).b
          if maxDigit - a >= b - minDigit {
            // wnat this digit between a..9
            if a < maxDigit {
              mode = .inetween(at: i, a+1, maxDigit)
            } else {
              newValues.insert(a, at: i)
              mode = .inetween(at: i+1, minDigit, maxDigit)
              continue
            }
          } else {
            // wnat prev digit incremented, this digit between 0..b
            if i == 0 { print("confused 2"); break
            } else {
              newValues[i-1] += 1
            }
            // we know: val[i-1] < maxValue
            // we know: da < db because `da >= db` failed above, and so db > 0
            if b == 0 { print("confused 3"); break
            } else {
              mode = .inetween(at: i, minDigit, b-1)
            }
          }
        } else {
          // degenerate case, want this digit between a..9
          if a < maxDigit {
            mode = .inetween(at: i, a+1, maxDigit)
          } else {
            newValues.insert(a, at: i)
            mode = .inetween(at: i+1, minDigit, maxDigit)
            continue
          }
        }
      default:
        break
      }
      break // exiting swtich without continue mean to exit loop
    }
    // finialize after ending loop in one of these modes
    switch mode {
    case .match(let i):
      newValues.insert(midDigit, at: i)
    case let .inetween(at: i, a,b): // a to b inclusive
      let d = b - a + 1
      newValues.insert(a + d / 2, at: i)
    default:
      break
    }
    return newValues.map { String($0)}.joined(separator: ".")
  }
  
  // MARK: -
  
  override var debugDescription: String {
    debugBatchDescription()
  }
  
  var desc: String { debugBatchDescription() }
  var dump: String { debugBatchDescription(ofLength: 0) }
  
  func debugBatchDescription(ofLength length: Int? = nil) -> String {
    let t = title.map { "'\($0)'" } ?? "no name"
    let clips = getClips()
    guard !clips.isEmpty else {
      return "\(t), no clips"
    }
    let c = clips.count
    if let len = length {
      let temp = "'' \(c): "
      let rem = temp.count - len
      let tmin = 6 // min characters for title
      let itemmin = 8 // min characters for each item
      if rem <= tmin {
        return "'\(t.prefix(max(len - 2, 4)))'" // if asked for len<6 return len 6 anyway
      } else if rem <= tmin + itemmin || c == 0 {
        return "'\(t.prefix(len - rem + 2))' \(c)" // +2 because not using the ': ' in the template str
      } else if rem < tmin + c * itemmin + c * 2 - 2 {
        let n = (rem - tmin + 2) / c * (itemmin + 2) // +2 in denom. for each ', ', but that's 1 extra so +2 in numer. to compensate    
        let cstr = clips.map({ $0.debugContentsDescription(ofLength: itemmin) }).prefix(n).joined(separator: ", ")
        return "'\(t.prefix(rem - cstr.count))' \(c): \(cstr)"
      } else {
        let dlen = rem / (c + 1) // 1 division for each item plus another for the title
        let cstr = clips.map({ $0.debugContentsDescription(ofLength: dlen) }).joined(separator: ", ")
        return "'\(t.prefix(rem - cstr.count))' \(c): \(cstr)"
      }
    } else if c > 0 {
      return "\(t) \(c): " + clips.map({ $0.debugContentsDescription(ofLength: 0) }).joined(separator: ", ")
    } else {
      return "\(t) \(c)"
    }
  }
  
}
