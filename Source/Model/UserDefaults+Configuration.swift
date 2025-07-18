//
//  UserDefaults+Configuration.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-03-21.
//  Portions Copyright © 2025 Bananameter Labs. All rights reserved.
//
//  Based on UserDefaults+Configuration.swift from the Maccy project
//  Portions Copyright © 2024 Alexey Rodionov. All rights reserved.
//

// There may still be Maccy settings in here that are no longer used and yet to be deleted

import AppKit

extension UserDefaults {
  public struct Keys {
    static let avoidTakingFocus = "avoidTakingFocus"
    static let clearOnQuit = "clearOnQuit"
    static let clearSystemClipboard = "clearSystemClipboard"
    static let clipboardCheckInterval = "clipboardCheckInterval"
    static let enabledPasteboardTypes = "enabledPasteboardTypes"
    static let hideSearch = "hideSearch"
    static let ignoreEvents = "ignoreEvents"
    static let ignoreOnlyNextEvent = "ignoreOnlyNextEvent"
    static let ignoreAllAppsExceptListed = "ignoreAllAppsExceptListed"
    static let ignoredApps = "ignoredApps"
    static let ignoredPasteboardTypes = "ignoredPasteboardTypes"
    static let imageMaxHeight = "imageMaxHeight"
    static let lastReviewRequestedAt = "lastReviewRequestedAt"
    static let maxMenuItems = "maxMenuItems"
    static let maxMenuItemLength = "maxMenuItemLength"
    static let numberOfUsages = "numberOfUsages"
    static let previewDelay = "previewDelay"
    static let searchMode = "searchMode"
    static let showSpecialSymbols = "showSpecialSymbols"
    static let size = "historySize"
    static let suppressClearAlert = "suppressClearAlert"
    static let ignoreRegexp = "ignoreRegexp"
    static let highlightMatch = "highlightMatch"
    static let completedIntro = "completedIntro"
    static let promoteExtras = "promoteExtras"
    static let promoteExtrasExpires = "promoteExtrasExpires"
    static let promoteExtrasExpiration = "promoteExtrasExpiration"
    static let keepHistory = "keepHistory"
    static let saveClipsAcrossDisabledHistory = "saveClipsAcrossDisabledHistory"
    static let supressSaveClipsAlert = "supressSaveClipsAlert"
    
    static var showInStatusBar: String {
      ProcessInfo.processInfo.arguments.contains("ui-testing") ? "showInStatusBarUITests" : "showInStatusBar"
    }
    
    static var storage: String {
      ProcessInfo.processInfo.arguments.contains("ui-testing") ? "historyUITests" : "history"
    }
  }
  
  public struct Values {
    static let clipboardCheckInterval = 0.5
    static let enabledPasteboardTypes: [String] = [ "public.rtf", "public.utf8-plain-text", "public.file-url", "public.tiff", "public.png", "public.html" ]
    static let ignoredPasteboardTypes: [String] = [ "net.antelle.keeweb", "com.agilebits.onepassword", "com.typeit4me.clipping", "Pasteboard generator type", "de.petermaurer.TransientPasteboardType" ]
    static let ignoredApps: [String] = []
    static let ignoreRegexp: [String] = []
    static let imageMaxHeight = 40.0
    static let maxMenuItems = 20
    static let maxMenuItemLength = 50
    static let previewDelay = 1500
    static let searchMode = "exact"
    static let showInStatusBar = true
    static let showSpecialSymbols = true
    static let size = 200
    static let highlightMatch = "bold"
    static let keepHistory = false
  }
  
  public var avoidTakingFocus: Bool {
    get { bool(forKey: Keys.avoidTakingFocus) }
    set { set(newValue, forKey: Keys.avoidTakingFocus) }
  }
  
  public var clearOnQuit: Bool {
    get { bool(forKey: Keys.clearOnQuit) }
    set { set(newValue, forKey: Keys.clearOnQuit) }
  }
  
  public var clearSystemClipboard: Bool {
    get { bool(forKey: Keys.clearSystemClipboard) }
    set { set(newValue, forKey: Keys.clearSystemClipboard) }
  }
  
  @objc dynamic var clipboardCheckInterval: Double {
    get { double(forKey: Keys.clipboardCheckInterval) }
    set { set(newValue, forKey: Keys.clipboardCheckInterval) }
  }
  // this somehow avoids double-fired kvo observations:
  @objc dynamic public class func automaticallyNotifiesObserversOfClipboardCheckInterval() -> Bool { false }
  
  @objc dynamic public var enabledPasteboardTypes: Set<NSPasteboard.PasteboardType> {
    get {
      let types = array(forKey: Keys.enabledPasteboardTypes) as? [String] ?? []
      return Set(types.map({ NSPasteboard.PasteboardType($0) }))
    }
    set { set(Array(newValue.map({ $0.rawValue })), forKey: Keys.enabledPasteboardTypes) }
  }
  @objc dynamic public class func automaticallyNotifiesObserversOfEnabledPasteboardTypes() -> Bool { false }
  
  @objc dynamic public var hideSearch: Bool {
    get { bool(forKey: Keys.hideSearch) }
    set { set(newValue, forKey: Keys.hideSearch) }
  }
  @objc dynamic public class func automaticallyNotifiesObserversOfHideSearch() -> Bool { false }
  
  @objc dynamic public var ignoreEvents: Bool {
    get { bool(forKey: Keys.ignoreEvents) }
    set { set(newValue, forKey: Keys.ignoreEvents) }
  }
  @objc dynamic public class func automaticallyNotifiesObserversOfIgnoreEvents() -> Bool { false }
  
  public var ignoreOnlyNextEvent: Bool {
    get { bool(forKey: Keys.ignoreOnlyNextEvent) }
    set { set(newValue, forKey: Keys.ignoreOnlyNextEvent) }
  }
  
  public var ignoreAllAppsExceptListed: Bool {
    get { bool(forKey: Keys.ignoreAllAppsExceptListed) }
    set { set(newValue, forKey: Keys.ignoreAllAppsExceptListed) }
  }
  
  public var ignoredApps: [String] {
    get { array(forKey: Keys.ignoredApps) as? [String] ?? Values.ignoredApps }
    set { set(newValue, forKey: Keys.ignoredApps) }
  }
  
  public var ignoredPasteboardTypes: Set<String> {
    get { Set(array(forKey: Keys.ignoredPasteboardTypes) as? [String] ?? Values.ignoredPasteboardTypes) }
    set { set(Array(newValue), forKey: Keys.ignoredPasteboardTypes) }
  }
  
  public var ignoreRegexp: [String] {
    get { array(forKey: Keys.ignoreRegexp) as? [String] ?? Values.ignoreRegexp }
    set { set(newValue, forKey: Keys.ignoreRegexp) }
  }
  
  @objc dynamic public var imageMaxHeight: Int {
    get { integer(forKey: Keys.imageMaxHeight) }
    set { set(newValue, forKey: Keys.imageMaxHeight) }
  }
  @objc dynamic public class func automaticallyNotifiesObserversOfImageMaxHeight() -> Bool { false }
  
  public var lastReviewRequestedAt: Date {
    get {
      let int = Int64(integer(forKey: Keys.lastReviewRequestedAt))
      return Date(timeIntervalSince1970: TimeInterval(integerLiteral: int))
    }
    set { set(Int(newValue.timeIntervalSince1970), forKey: Keys.lastReviewRequestedAt) }
  }
  
  @objc dynamic public var maxMenuItems: Int {
    get { integer(forKey: Keys.maxMenuItems) }
    set { set(newValue, forKey: Keys.maxMenuItems) }
  }
  @objc dynamic public class func automaticallyNotifiesObserversOfMaxMenuItems() -> Bool { false }
  
  @objc dynamic public var maxMenuItemLength: Int {
    get { integer(forKey: Keys.maxMenuItemLength) }
    set { set(newValue, forKey: Keys.maxMenuItemLength) }
  }
  @objc dynamic public class func automaticallyNotifiesObserversOfMaxMenuItemLength() -> Bool { false }
  
  public var numberOfUsages: Int {
    get { integer(forKey: Keys.numberOfUsages) }
    set { set(newValue, forKey: Keys.numberOfUsages) }
  }
  
  public var previewDelay: Int {
    get { integer(forKey: Keys.previewDelay) }
    set { set(newValue, forKey: Keys.previewDelay) }
  }
  
  public var searchMode: String {
    get { string(forKey: Keys.searchMode) ?? Values.searchMode }
    set { set(newValue, forKey: Keys.searchMode) }
  }
  
  @objc dynamic public var showInStatusBar: Bool {
    get { ProcessInfo.processInfo.arguments.contains("ui-testing") ? true : bool(forKey: Keys.showInStatusBar) }
    set { set(newValue, forKey: Keys.showInStatusBar) }
  }
  @objc dynamic public class func automaticallyNotifiesObserversOfShowInStatusBar() -> Bool { false }
  
  @objc dynamic var showSpecialSymbols: Bool {
    get { bool(forKey: Keys.showSpecialSymbols) }
    set { set(newValue, forKey: Keys.showSpecialSymbols) }
  }
  @objc dynamic public class func automaticallyNotifiesObserversOfShowSpecialSymbols() -> Bool { false }
  
  @objc dynamic public var size: Int {
    get { integer(forKey: Keys.size) }
    set { set(newValue, forKey: Keys.size) }
  }
  @objc dynamic public class func automaticallyNotifiesObserversOfSize() -> Bool { false }
  
  public var suppressClearAlert: Bool {
    get { bool(forKey: Keys.suppressClearAlert) }
    set { set(newValue, forKey: Keys.suppressClearAlert) }
  }
  
  public var highlightMatches: String {
    get { string(forKey: Keys.highlightMatch) ?? Values.highlightMatch }
    set { set(newValue, forKey: Keys.highlightMatch) }
  }
  
  public var completedIntro: Bool {
    get { bool(forKey: Keys.completedIntro) }
    set { set(newValue, forKey: Keys.completedIntro) }
  }
  
  public var promoteExtras: Bool {
    get { bool(forKey: Keys.promoteExtras) }
    set { set(newValue, forKey: Keys.promoteExtras) }
  }
  
  public var promoteExtrasExpires: Bool {
    get { bool(forKey: Keys.promoteExtrasExpires) }
    set { set(newValue, forKey: Keys.promoteExtrasExpires) }
  }
  
  public var promoteExtrasExpiration: DateComponents? {
    get {
      if let dateData = data(forKey: Keys.promoteExtrasExpiration) {
        do {
          return try JSONDecoder().decode(DateComponents.self, from: dateData)
        } catch {}
      }
      return nil
    }
    set {
      if let dateComponents = newValue {
        do {
          let dateData = try JSONEncoder().encode(dateComponents)
          set(dateData, forKey: Keys.promoteExtrasExpiration)
          return
        } catch {}
      }
      removeObject(forKey: Keys.promoteExtrasExpiration)
    }
  }
  
  @objc dynamic public var keepHistory: Bool {
    get { bool(forKey: Keys.keepHistory) }
    set { set(newValue, forKey: Keys.keepHistory) }
  }
  @objc dynamic public class func automaticallyNotifiesObserversOfKeepHistory() -> Bool { false }
  
  public var saveClipsAcrossDisabledHistory: Bool {
    get { bool(forKey: Keys.saveClipsAcrossDisabledHistory) }
    set { set(newValue, forKey: Keys.saveClipsAcrossDisabledHistory) }
  }
  
  public var supressSaveClipsAlert: Bool {
    get { bool(forKey: Keys.supressSaveClipsAlert) }
    set { set(newValue, forKey: Keys.supressSaveClipsAlert) }
  }
  
}
