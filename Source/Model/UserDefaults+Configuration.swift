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
    static let showHistoryFilter = "showHistoryFilter"
    static let ignoreEvents = "ignoreEvents"
    static let ignoreOnlyNextEvent = "ignoreOnlyNextEvent"
    static let ignoreAllAppsExceptListed = "ignoreAllAppsExceptListed"
    static let ignoredApps = "ignoredApps"
    static let ignoredPasteboardTypes = "ignoredPasteboardTypes"
    static let imageMaxHeight = "imageMaxHeight"
    static let lastReviewRequestedAt = "lastReviewRequestedAt"
    static let maxMenuItems = "maxMenuItems"
    static let maxTitleLength = "maxMenuItemLength"
    static let numberOfUsages = "numberOfUsages"
    static let previewDelay = "previewDelay"
    static let searchMode = "searchMode"
    static let showSpecialSymbols = "showSpecialSymbols"
    static let historySize = "historySize"
    static let suppressClearAlert = "suppressClearAlert"
    static let suppressDeleteBatchAlert = "suppressDeleteBatchAlert" 
    static let ignoreRegexp = "ignoreRegexp"
    static let highlightMatch = "highlightMatch"
    static let completedIntro = "completedIntro"
    static let promoteExtras = "promoteExtras"
    static let promoteExtrasExpires = "promoteExtrasExpires"
    static let promoteExtrasExpiration = "promoteExtrasExpiration"
    static let keepHistory = "keepHistory"
    static let keepHistoryChoicePending = "keepHistoryChoicePending"
    static let saveClipsAcrossDisabledHistory = "saveClipsAcrossDisabledHistory"
    static let supressSaveClipsAlert = "supressSaveClipsAlert"
    static let supressUseHistoryAlert = "supressUseHistoryAlert"
    static let showInStatusBar = "showInStatusBar"
    static let legacyFocusTechnique = "legacyFocus"
    static let showAdvancedPasteMenuItems = "showAdvancedPasteMenuItems"
    
    // maccy had a few like this, perhaps something to continue doing?
//    static var showInStatusBar: String {
//      ProcessInfo.processInfo.arguments.contains("ui-testing") ? "showInStatusBarUITests" : "showInStatusBar"
//    }
  }
  
  public struct Values {
    static let clipboardCheckInterval = 0.5
    static let enabledPasteboardTypes: [String] = [ "public.rtf", "public.utf8-plain-text", "public.file-url", "public.tiff", "public.png", "public.html" ]
    static let ignoredPasteboardTypes: [String] = [ "net.antelle.keeweb", "com.agilebits.onepassword", "com.typeit4me.clipping", "Pasteboard generator type", "de.petermaurer.TransientPasteboardType" ]
    static let ignoredApps: [String] = []
    static let ignoreRegexp: [String] = []
    static let imageMaxHeight = 40.0
    static let maxMenuItems = 20
    static let maxTitleLength = 50
    static let previewDelay = 1500
    static let searchMode = "exact"
    static let showInStatusBar = true
    static let showSpecialSymbols = true
    static let historySize = 100
    static let highlightMatch = "bold"
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
  
  @objc dynamic public var enabledPasteboardTypes: Set<NSPasteboard.PasteboardType> {
    get {
      let types = array(forKey: Keys.enabledPasteboardTypes) as? [String] ?? []
      return Set(types.map({ NSPasteboard.PasteboardType($0) }))
    }
    set { set(Array(newValue.map({ $0.rawValue })), forKey: Keys.enabledPasteboardTypes) }
  }
  // these functions prevent duplicate observations, not exactly sure how it works 
  @objc dynamic public class func automaticallyNotifiesObserversOfEnabledPasteboardTypes() -> Bool { false }
  
  public var hideSearch: Bool {
    get { bool(forKey: Keys.hideSearch) }
    set { set(newValue, forKey: Keys.hideSearch) }
  }
  
  @objc dynamic public var showHistoryFilter: Bool {
    get { bool(forKey: Keys.showHistoryFilter) }
    set {
      set(newValue, forKey: Keys.showHistoryFilter)
      if object(forKey: Keys.hideSearch) != nil {   // if user upgraded and had a preference in the old flag
        set(!newValue, forKey: Keys.hideSearch)     // keep on maintaining that old flag in perpetuity
      }
    }
  }
  @objc dynamic public class func automaticallyNotifiesObserversOfShowHistoryFilter() -> Bool { false }
  
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
  
  public var lastReviewRequestedAt: Date {
    get {
      let int = Int64(integer(forKey: Keys.lastReviewRequestedAt))
      return Date(timeIntervalSince1970: TimeInterval(integerLiteral: int))
    }
    set { set(Int(newValue.timeIntervalSince1970), forKey: Keys.lastReviewRequestedAt) }
  }
  
  @objc dynamic public var imageMaxHeight: Int {
    get { integer(forKey: Keys.imageMaxHeight) }
    set { set(newValue, forKey: Keys.imageMaxHeight) }
  }
  @objc dynamic public class func automaticallyNotifiesObserversOfImageMaxHeight() -> Bool { false }
  
  @objc dynamic public var maxMenuItems: Int {
    get { integer(forKey: Keys.maxMenuItems) }
    set { set(newValue, forKey: Keys.maxMenuItems) }
  }
  @objc dynamic public class func automaticallyNotifiesObserversOfMaxMenuItems() -> Bool { false }
  
  @objc dynamic public var maxTitleLength: Int {
    get { integer(forKey: Keys.maxTitleLength) }
    set { set(newValue, forKey: Keys.maxTitleLength) }
  }
  @objc dynamic public class func automaticallyNotifiesObserversOfMaxTitleLength() -> Bool { false }
  
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
  
  @objc dynamic public var historySize: Int {
    get { integer(forKey: Keys.historySize) }
    set { set(newValue, forKey: Keys.historySize) }
  }
  @objc dynamic public class func automaticallyNotifiesObserversOfHistorySize() -> Bool { false }
  
  public var suppressClearAlert: Bool {
    get { bool(forKey: Keys.suppressClearAlert) }
    set { set(newValue, forKey: Keys.suppressClearAlert) }
  }
  
  public var suppressDeleteBatchAlert: Bool {
    get { bool(forKey: Keys.suppressDeleteBatchAlert) }
    set { set(newValue, forKey: Keys.suppressDeleteBatchAlert) }
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
  
  public var keepHistoryChoicePending: Bool {
    get { bool(forKey: Keys.keepHistoryChoicePending) }
    set { set(newValue, forKey: Keys.keepHistoryChoicePending) }
  }
  
  public var saveClipsAcrossDisabledHistory: Bool {
    get { bool(forKey: Keys.saveClipsAcrossDisabledHistory) }
    set { set(newValue, forKey: Keys.saveClipsAcrossDisabledHistory) }
  }
  
  public var supressSaveClipsAlert: Bool {
    get { bool(forKey: Keys.supressSaveClipsAlert) }
    set { set(newValue, forKey: Keys.supressSaveClipsAlert) }
  }
  
  public var supressUseHistoryAlert: Bool {
    get { bool(forKey: Keys.supressUseHistoryAlert) }
    set { set(newValue, forKey: Keys.supressUseHistoryAlert) }
  }
  
  @objc dynamic public var legacyFocusTechnique: Bool {
    get { bool(forKey: Keys.legacyFocusTechnique) }
    set { set(newValue, forKey: Keys.legacyFocusTechnique) }
  }
  @objc dynamic public class func automaticallyNotifiesObserversOfLegacyFocusTechnique() -> Bool { false }
  
  public var showAdvancedPasteMenuItems: Bool {
    get { bool(forKey: Keys.showAdvancedPasteMenuItems) }
    set { set(newValue, forKey: Keys.showAdvancedPasteMenuItems) }
  }
  
}
