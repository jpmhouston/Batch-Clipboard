//
//  Clip.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-07-10.
//  Portions Copyright © 2025 Bananameter Labs. All rights reserved.
//
//  Based on HistoryItem.swift from the Maccy project
//  Portions Copyright © 2024 Alexey Rodionov. All rights reserved.
//

import AppKit
import CoreData
import Sauce
import os.log

@objc(HistoryItem)
class Clip: NSManagedObject {
  
  @NSManaged public var application: String?
  @NSManaged public var firstCopiedAt: Date!
  @NSManaged public var lastCopiedAt: Date!
  @NSManaged public var numberOfCopies: Int
  @NSManaged public var title: String?
  @NSManaged public var contents: NSSet?
  @NSManaged public var batches: NSSet?
  @NSManaged public var history: HistoryList?
  
  var fileURLs: [URL] {
    guard !universalClipboardText else {
      return []
    }
    
    return allContentData(filePasteboardTypes)
      .compactMap { URL(dataRepresentation: $0, relativeTo: nil, isAbsolute: true) }
  }
  
  var htmlData: Data? { contentData(htmlPasteboardTypes) }
  var html: NSAttributedString? {
    guard let data = htmlData else {
      return nil
    }
    
    return NSAttributedString(html: data, documentAttributes: nil)
  }
  
  var image: NSImage? {
    var data: Data?
    data = contentData(imagePasteboardTypes)
    if data == nil, universalClipboardImage, let url = fileURLs.first {
      data = try? Data(contentsOf: url)
    }
    
    guard let data = data else {
      return nil
    }
    
    return NSImage(data: data)
  }
  
  var rtfData: Data? { contentData(rtfPasteboardTypes) }
  var rtf: NSAttributedString? {
    guard let data = rtfData else {
      return nil
    }
    
    return NSAttributedString(rtf: data, documentAttributes: nil)
  }
  
  var text: String? {
    guard let data = contentData(textPasteboardTypes) else {
      return nil
    }
    
    return String(data: data, encoding: .utf8)
  }
  
  var modified: Int? {
    guard let data = contentData([.modified]),
          let modified = String(data: data, encoding: .utf8) else {
      return nil
    }
    
    return Int(modified)
  }
  
  var value: String {
    return calculateValue()
  }
  
  var parentConnectionsEmpty: Bool { history == nil && (batches == nil || batches!.count == 0) }
  
  var fromSelf: Bool { hasContentData([.fromSelf]) || hasContentData([.fromMaccy]) }
  var universalClipboard: Bool { hasContentData([.universalClipboard]) }
  
  private let filePasteboardTypes: [NSPasteboard.PasteboardType] = [.fileURL]
  private let htmlPasteboardTypes: [NSPasteboard.PasteboardType] = [.html]
  private let imagePasteboardTypes: [NSPasteboard.PasteboardType] = [.tiff, .png, .jpeg]
  private let rtfPasteboardTypes: [NSPasteboard.PasteboardType] = [.rtf]
  private let textPasteboardTypes: [NSPasteboard.PasteboardType] = [.string]
  
  private var universalClipboardImage: Bool { universalClipboard && fileURLs.first?.pathExtension == "jpeg" }
  private var universalClipboardText: Bool {
    universalClipboard &&
    hasContentData(htmlPasteboardTypes + imagePasteboardTypes + rtfPasteboardTypes + textPasteboardTypes)
  }
  
  // MARK: -
  
  static let sortByFirstCopiedAt = NSSortDescriptor(key: #keyPath(Clip.firstCopiedAt), ascending: false)
  
  // TODO: are these computed properties better as a throwing load() functions?
  
  static var all: [Clip] { loadAll() }
  
  static func == (lhs: Clip, rhs: Clip) -> Bool {
    return lhs.getContents().count == rhs.getContents().count && lhs.contentsEqual(rhs)
  }
  
  static func create(withContents contents: any Collection<ClipContent>, application: String? = nil) -> Clip {
    let clip = Clip(context: CoreDataManager.shared.context)
    
    clip.application = application
    clip.firstCopiedAt = Date()
    clip.lastCopiedAt = clip.firstCopiedAt
    clip.numberOfCopies = 1
    clip.addContents(contents)
    
    clip.title = clip.generateTitle()
    
    CoreDataManager.shared.saveContext()
    return clip
  }
  
  // MARK: -
  
  @discardableResult
  static func loadAll() -> [Clip] {
    let fetchRequest = NSFetchRequest<Clip>(entityName: "HistoryItem")
    fetchRequest.sortDescriptors = [Clip.sortByFirstCopiedAt]
    do {
      //return try CoreDataManager.shared.context.fetch(fetchRequest)
      // documentation says deleted entities not fetched but saw it happen in unit tests, leave this in until that's solved
      let fetched = try CoreDataManager.shared.context.fetch(fetchRequest)
      return fetched.filter { !$0.isDeleted } 
    } catch {
      os_log(.default, "unhandled error fetching all clips %@", error.localizedDescription)
      return []
    }
  }
  
  static func deleteAll() {
    let fetchRequest = NSFetchRequest<Clip>(entityName: "HistoryItem")
    do {
      let clips = try CoreDataManager.shared.context.fetch(fetchRequest)
      clips.forEach { clip in
        clip.clearContents()
        CoreDataManager.shared.context.delete(clip)
      }
    } catch {
      os_log(.default, "unhandled error deleting clips %@", error.localizedDescription)
    }
  }
  
  // MARK: -
  
  #if MACCY_DUPLICATE_HANDLING
  func supersedes(_ clip: Clip) -> Bool {
    contentsEqual(clip)
  }
  #endif
  
  func contentsEqual(_ otherClip: Clip) -> Bool {
    return otherClip.getContents().filter { otherContent in
      otherContent.type.isExcluded(from: [
        NSPasteboard.PasteboardType.modified.rawValue,
        NSPasteboard.PasteboardType.fromMaccy.rawValue,
        NSPasteboard.PasteboardType.fromSelf.rawValue
      ])
    }
    .allSatisfy { content in
      getContents().contains { $0 == content }
    }
  }
  
  func addContents(_ contents: any Collection<ClipContent>) {
    contents.forEach(addToContents(_:))
  }
  
  func getContents() -> Set<ClipContent> {
    (contents as? Set<ClipContent>) ?? Set()
  }
  
  func getContentsArray() -> [ClipContent] {
    (contents?.allObjects as? [ClipContent]) ?? []
  }
  
  func getBatches() -> Set<Batch> {
    (batches as? Set<Batch>) ?? Set()
  }
  
  func getBatchesArray() -> [Batch] {
    (batches?.allObjects as? [Batch]) ?? []
  }
  
  func clearContents() {
    getContents().forEach(deleteContentItem(_:))
  }
  
  @objc(addContentsObject:)
  @NSManaged public func addToContents(_ value: ClipContent)
  
  @objc(removeContentsObject:)
  @NSManaged public func removeFromContents(_ value: ClipContent)
  
  // MARK: -
  
  func generateTitle() -> String {
    var title = ""
    
    guard image == nil else {
      return title
    }
    
    if !fileURLs.isEmpty {
      title = fileURLs
        .compactMap { $0.absoluteString.removingPercentEncoding }
        .joined(separator: "\n")
    } else if let text = text {
      title = text
    } else if title.isEmpty, let rtf = rtf {
      title = rtf.string
    } else if title.isEmpty, let html = html {
      title = html.string
    }
    
    if UserDefaults.standard.showSpecialSymbols {
      if let range = title.range(of: "^ +", options: .regularExpression) {
        title = title.replacingOccurrences(of: " ", with: "·", range: range)
      }
      if let range = title.range(of: " +$", options: .regularExpression) {
        title = title.replacingOccurrences(of: " ", with: "·", range: range)
      }
      title = title
        .replacingOccurrences(of: "\n", with: "⏎")
        .replacingOccurrences(of: "\t", with: "⇥")
    } else {
      title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    return title.shortened(to: UserDefaults.standard.maxTitleLength)
  }
  
  private func contentData(_ types: [NSPasteboard.PasteboardType]) -> Data? {
    let contents = getContents()
    let content = contents.first {
      types.contains(NSPasteboard.PasteboardType($0.type))
    }
    
    return content?.value
  }
  
  private func hasContentData(_ types: [NSPasteboard.PasteboardType]) -> Bool {
    let contents = getContents()
    return contents.contains {
      types.contains(NSPasteboard.PasteboardType($0.type))
    }
  }
  
  private func allContentData(_ types: [NSPasteboard.PasteboardType]) -> [Data] {
    let contents = getContents()
    return contents
      .filter { types.contains(NSPasteboard.PasteboardType($0.type)) }
      .compactMap { $0.value }
  }
  
  var types: [NSPasteboard.PasteboardType] {
    let contents = getContents()
    return contents.map { NSPasteboard.PasteboardType($0.type) }
  }
  
  var isImage: Bool { image != nil }
  var isFile: Bool { !fileURLs.isEmpty }
  var isRTF: Bool { rtf != nil }
  var isHTML: Bool { html != nil }
  var isText: Bool { text != nil }
  
  private func calculateValue() -> String {
    if isImage {
      return ""
    } else if isFile {
      return fileURLs
        .compactMap { $0.absoluteString.removingPercentEncoding }
        .joined(separator: "\n")
    } else if isText {
      return  text ?? ""
    } else if isRTF {
      return rtf?.string ?? ""
    } else if isHTML {
      return html?.string ?? ""
    }
    return ""
  }
  
  private func deleteContentItem(_ content: ClipContent) {
    // coredata has some relationshipdelete rules, it seems none of them are like reference counting
    // to do this automatically: members of contents that belong to only this clip get deleted too
    removeFromContents(content)
    if content.parentConnectionsEmpty {
      CoreDataManager.shared.context.delete(content)
    } 
  }
  
  // MARK: -
    
  override var debugDescription: String {
    debugContentsDescription()
  }
  
  var desc: String { debugContentsDescription() }
  var dump: String { debugContentsDescription(ofLength: 0) }
  
  // had these named `debugDescription(....)` which is apparently fine to call
  // from `self` but other callers seem to be disambiguating different, accessing
  // the property `debugDescription` and then trying to call it as a function
  func debugContentsDescription(ofLength length: Int? = nil) -> String {
    Self.debugContentsDescription(getContentsArray(), ofLength: length)
  }
  
  static func debugContentsDescription(_ contents: any Collection<ClipContent>, ofLength length: Int? = nil) -> String {
    let pairs = contents.compactMap {
      if let t=$0.type, let v=$0.value { (NSPasteboard.PasteboardType(t), v) } else { nil }
    }
    return debugContentsDescription(forKeys: pairs.map(\.0), values: pairs.map(\.1), ofLength: length)
  }
//  static func debugContentsDescription(_ contents: [ClipContent], ofLength length: Int? = nil) -> String {
//    let pairs = contents.compactMap {
//      if let t=$0.type, let v=$0.value { (NSPasteboard.PasteboardType(t),v) } else { nil }
//    }
//    return debugContentsDescription(forKeys: pairs.map(\.0), values: pairs.map(\.1), ofLength: length)
//  }
  
  static func debugContentsDescription(for pairs: [(NSPasteboard.PasteboardType, Data)], ofLength length: Int? = nil) -> String {
    return debugContentsDescription(forKeys: pairs.map(\.0), values: pairs.map(\.1), ofLength: length)
  }
  
  // swiftlint:disable comma
  static func debugContentsDescription(forKeys keys: [NSPasteboard.PasteboardType], values: [Data], ofLength length: Int? = nil) -> String {
    let len = length ?? 16 // length <= 0 means unlimited length string, length nil means pick this default length
    var desc: String
    if keys.count != values.count {
      desc = "(bad)"
    } else if keys.isEmpty {
      desc = len.isWithin(range: 1 ..< 7) ? "_" : "(empty)"
    } else if keys.includes([.tiff, .png, .jpeg]) {
      desc = len.isWithin(range: 1 ..< 5) ? "img" : "image"
    } else if keys.contains(.fileURL) {
      let n = keys.filter({$0 == .fileURL}).count
      desc = len.isWithin(range: 1 ..< 6) ? "f\(n)" : "\(n) files"
    } else if let i = keys.firstIndex(of: .rtf) {
      let s = NSAttributedString(rtf: values[i], documentAttributes: nil)?.string
      if let s = s {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        desc = len.isWithin(range: 1 ..< 5) ? "r" + String(t.prefix(len)) :
          "rtf " + (len.isWithin(range: 5 ..< max(5, t.count)) ? String(t.prefix(len)) : t)
      } else {
        desc = "rtf?"
      }
    } else if let i = keys.firstIndex(of: .html) {
      let s = NSAttributedString(html: values[i], documentAttributes: nil)?.string
      if let s = s {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        desc = len.isWithin(range: 1 ..< 6) ? "h" + String(t.prefix(len)) :
          "html " + (len.isWithin(range: 6 ..< max(6,t.count)) ? String(t.prefix(len)) : t)
      } else {
        desc = "html?"
      }
    } else if let i = keys.firstIndex(of: .string) {
      let s = String(data: values[i], encoding: .utf8)
      if let s = s { // s?..trimmingCharacters(in: .whitespacesAndNewlines)
        desc = len.isWithin(range: 1 ..< max(1,s.count)) ? String(s.prefix(len)) : s
      } else {
        desc = "str?"
      }
    } else {
      desc = "?"
    }
    if keys.contains(.universalClipboard) {
      desc += "*"
    }
    return desc
  }
  // swiftlint:enable comma
  
}
