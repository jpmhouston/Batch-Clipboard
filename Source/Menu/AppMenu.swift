//
//  AppMenu
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-03-20.
//  Portions Copyright © 2025 Bananameter Labs. All rights reserved.
//
//  Based on Menu.swift from Maccy
//  Portions Copyright © 2024 Alexey Rodionov. All rights reserved.
//

// swiftlint:disable file_length
import AppKit
import os.log

// Custom menu supporting "search-as-you-type" based on https://github.com/mikekazakov/MGKMenuWithFilter.
// swiftlint:disable type_body_length
class AppMenu: NSMenu, NSMenuDelegate {
  private var history: History!
  private var queue: ClipboardQueue!
  private let previewController = PreviewPopoverController()
  private let search = Searcher()
  
  static let menuWidth = 300
  static let popoverGap = 5.0
  static let minNumMenuItems = 5 // things get weird if the effective menu size is 0
  private var historyItemGroupCount: Int { usePopoverAnchors ? 3 : 2 } // an optional anchor, keep in sync with buildHistoryItemAlternates
  private var batchItemGroupCount: Int { usePopoverAnchors ? 2 : 1 } // an optional anchor, keep in sync with buildHistoryItemAlternates
  
//  private var effectiveMaxClips: Int {
//    if AppModel.allowDictinctStorageSize { UserDefaults.standard.size } else { UserDefaults.standard.maxMenuItems }
//  }
//  private var effectiveMaxVisibleClips: Int {
//    if AppModel.allowDictinctStorageSize && UserDefaults.standard.maxMenuItems == 0 { UserDefaults.standard.size } else { UserDefaults.standard.maxMenuItems } 
//  }
  private var maxClipMenuItems: Int { max(AppModel.effectiveMaxClips, queue.size) }
  private var maxVisibleHistoryClips: Int {
    showsExpandedMenu && showsFullExpansion ? maxClipMenuItems - queue.size : max(AppModel.effectiveMaxVisibleClips  - queue.size, 0)
  }
//  private var maxHistoryClips: Int {
//    let numMenuItemsSetting = max(Self.minNumMenuItems, UserDefaults.standard.maxMenuItems == 0 ?
//                                  UserDefaults.standard.size : UserDefaults.standard.maxMenuItems)
//    let numItemsStoredSetting = max(Self.minNumMenuItems, UserDefaults.standard.size)
//    return if !AppModel.allowDictinctStorageSize {
//      numMenuItemsSetting
//    } else if showsExpandedMenu && showsFullExpansion {
//      max(numMenuItemsSetting, numItemsStoredSetting)
//    } else {
//      min(numMenuItemsSetting, numItemsStoredSetting)
//    }
//  }
  
  private var usePopoverAnchors: Bool {
    // note: hardcoding false to exercise using anchors on >=sonoma won't work currently
    // would require changes in PreviewPopoverController
    if #unavailable(macOS 14) { true } else { false }
  }
  private var removeViewToHideMenuItem: Bool {
    if #unavailable(macOS 14) { true } else { false }
  }
  private var showsExpandedMenu = false
  private var showsFullExpansion = false
  private var showsFilterField = false
  private var showsSavedBatches = false
  private var isFiltered = false
  private var isVisible = false
  
  private var disableDeleteTimer: DispatchSourceTimer?
  private var promoteExtrasBadge: NSObject?
  private var cacheUndoCopyItemShortcut = ""
  private var historyHeaderView: FilterFieldView? { filterFieldItem?.view as? FilterFieldView }
  private var filterFieldViewCache: FilterFieldView?
  private var menuWindow: NSWindow? { NSApp.menuWindow }
  
  private var lastHighlightedMenuItem: NSMenuItem?
  private var previewPopover: NSPopover?
  private var protoCopyItem: ClipMenuItem?
  private var protoReplayItem: ClipMenuItem?
  private var protoAnchorItem: NSMenuItem?
  
  private var topQueueAnchorItem: NSMenuItem?
  private var preQueueItem: NSMenuItem?
  private var postQueueItem: NSMenuItem? { postQueueSeparatorItem }
//  private var firstQueueItem: NSMenuItem? {
//    guard let index = firstQueueItemIndex else { return nil }
//    return item(at: index) // result might be postQueueSeparatorItem
//  }
//  private var firstQueueItemIndex: Int? {
//    guard let preIndex = safeIndex(of: preQueueItem) else { return nil }
//    return preIndex + 1 // result might be the index of postQueueSeparatorItem
//  }
  private var firstQueueItem: NSMenuItem? { safeItem(at: firstQueueItemIndex) } // result might be postQueueSeparatorItem
  private var firstQueueItemIndex: Int? { safeIndex(of: preQueueItem)?.advanced(by: 1) }
  private var postQueueItemIndex: Int? { safeIndex(of: postQueueItem) }
  private var queueItemCount: Int {
    guard let firstIndex = firstQueueItemIndex, let postIndex = postQueueItemIndex else { return 0 }
    return postIndex - firstIndex
  }
  private var topHistoryAnchorItem: NSMenuItem?
  private var preHistoryItem: NSMenuItem?
  private var postHistoryItem: NSMenuItem? { postHistorySeparatorItem }
  private var firstHistoryItem: NSMenuItem? { safeItem(at: firstHistoryItemIndex) } // result might be postHistorySeparatorItem
  private var firstHistoryItemIndex: Int? { safeIndex(of: preHistoryItem)?.advanced(by: 1) }
  private var postHistoryItemIndex: Int? { safeIndex(of: postHistoryItem) }
  private var historyItemCount: Int {
    guard let firstIndex = firstHistoryItemIndex, let postIndex = postHistoryItemIndex else { return 0 }
    return postIndex - firstIndex
  }
  private var preBatchesItem: NSMenuItem?
  private var postBatchesItem: NSMenuItem? { postBatchesSeparatorItem }
  private var firstBatchItem: NSMenuItem? { safeItem(at: firstBatchItemIndex) } // result might be postBatchesSeparatorItem
  private var firstBatchItemIndex: Int? { safeIndex(of: preBatchesItem)?.advanced(by: 1) }
  private var postBatchesItemIndex: Int? { safeIndex(of: postBatchesItem) }
  private var batchItemCount: Int {
    guard let firstIndex = firstBatchItemIndex, let postIndex = postBatchesItemIndex else { return 0 }
    return postIndex - firstIndex
  }
  
  @IBOutlet weak var queueStartItem: NSMenuItem?
  @IBOutlet weak var queueStopItem: NSMenuItem?
  @IBOutlet weak var queueReplayItem: NSMenuItem?
  @IBOutlet weak var queuedCopyItem: NSMenuItem?
  @IBOutlet weak var queuedPasteItem: NSMenuItem?
  @IBOutlet weak var queueAdvanceItem: NSMenuItem?
  @IBOutlet weak var queuedPasteMultipleItem: NSMenuItem?
  @IBOutlet weak var queuedPasteAllItem: NSMenuItem?
  @IBOutlet weak var noteItem: NSMenuItem?
  @IBOutlet weak var prototypeCopyItem: NSMenuItem?
  @IBOutlet weak var prototypeReplayItem: NSMenuItem?
  @IBOutlet weak var prototypeAnchorItem: NSMenuItem?
  @IBOutlet weak var filterFieldItem: NSMenuItem?
  @IBOutlet weak var keyDetectorItem: NSMenuItem?
  @IBOutlet weak var leadingSeparatorItem: NSMenuItem?
  @IBOutlet weak var postQueueSeparatorItem: NSMenuItem?
  @IBOutlet weak var postHistorySeparatorItem: NSMenuItem?
  @IBOutlet weak var postBatchesSeparatorItem: NSMenuItem?
  @IBOutlet weak var deleteItem: NSMenuItem?
  @IBOutlet weak var clearItem: NSMenuItem?
  @IBOutlet weak var undoCopyItem: NSMenuItem?
  
  // MARK: - lifecycle, overrides, delegate methods
  
  static func load(withHistory history: History, queue: ClipboardQueue, owner: Any) -> Self {
    // somewhat unconventional, perhaps in part because most of this code belongs in a controller class?
    // we already have a MenuController however its used for some other things
    // although since there's no such thing as a NSMenuController would have to do custom loading from nib anyway :shrug:
    guard let nib = NSNib(nibNamed: "AppMenu", bundle: nil) else {
      fatalError("Menu resources missing")
    }
    var nibObjects: NSArray? = NSArray()
    nib.instantiate(withOwner: owner, topLevelObjects: &nibObjects)
    guard let menu = nibObjects?.compactMap({ $0 as? Self }).first else {
      fatalError("Menu resources missing")
    }
    
    menu.history = history
    menu.queue = queue
    return menu
  }
  
  override func awakeFromNib() {
    self.delegate = self
    self.autoenablesItems = false
    
    self.minimumWidth = CGFloat(Self.menuWidth)
    
    // save aside the prototype history menu items and remove them from the menu
    if let prototypeCopyItem = prototypeCopyItem as? ClipMenuItem {
      protoCopyItem = prototypeCopyItem
      removeItem(prototypeCopyItem)
      protoCopyItem?.title = ""
    }
    if let prototypeReplayItem = prototypeReplayItem as? ClipMenuItem {
      protoReplayItem = prototypeReplayItem
      removeItem(prototypeReplayItem)
      protoReplayItem?.title = ""
    }
    if let prototypeAnchorItem = prototypeAnchorItem {
      protoAnchorItem = prototypeAnchorItem
      removeItem(prototypeAnchorItem)
      protoAnchorItem?.title = ""
    }
    
    // strip these placeholder item titles, only to identify them in interface builder
    filterFieldItem?.title = ""
    keyDetectorItem?.title = ""
    
    if usePopoverAnchors {
      insertTopAnchorItems()
    }
    preQueueItem = topQueueAnchorItem ?? leadingSeparatorItem
    preHistoryItem = topHistoryAnchorItem ?? keyDetectorItem
    preBatchesItem = postHistorySeparatorItem
    
    addDebugItems()
  }
  
  func prepareForPopup() {
    updateStaticItemShortcuts()
    updateDisabledStaticItems()
    updateStaticItemVisibility()
    updateDynamicClipItemVisibility()
  }
  
  func menuWillOpen(_ menu: NSMenu) {
    isVisible = true
    
    // potentially revert expanded mode flag initially set from an option-click on the menu icon
    if showsExpandedMenu && !(AppModel.allowExpandedHistory && historyItemCount > 0) {
      showsExpandedMenu = false
    }
    
    if showsExpandedMenu && AppModel.allowHistorySearch && !UserDefaults.standard.hideSearch,
       let field = historyHeaderView?.queryField
    {
      field.refusesFirstResponder = false
      field.window?.makeFirstResponder(field)
      showsFilterField = true
    } else {
      showsFilterField = false
    }
    
    if !showsExpandedMenu && AppModel.allowSavedBatches && queue.isEmpty {
      showsSavedBatches = true
    } else {
      showsSavedBatches = false
    }
    
    previewController.menuWillOpen()
  }
  
  func menuDidClose(_ menu: NSMenu) {
    isVisible = false
    showsExpandedMenu = false
    
    isFiltered = false
    if showsFilterField {
      // not sure why this is in a dispatch to the main thread, some timing thing i'm guessing
      DispatchQueue.main.async { 
        self.historyHeaderView?.setQuery("", throttle: false)
        self.historyHeaderView?.queryField.refusesFirstResponder = true
      }
    }
    
    previewController.menuDidClose()
  }
  
  func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
    previewController.cancelPopover()
    
    // forget the outstanding deferred disable of the delete item
    disableDeleteTimer?.cancel()
    disableDeleteTimer = nil
    
    if let historyItem = item as? ClipMenuItem {
      deleteItem?.isEnabled = !AppModel.busy
      lastHighlightedMenuItem = historyItem
      
      previewController.showPopover(for: historyItem, anchors: clipItemAnchors(for: historyItem))
      
    } else if item == nil || item == deleteItem {
      // called with nil when cursor is over a disabled item, a separator, or is
      // away from any menu items
      // when cmd-delete hit, this is first called with nil and then with the
      // delete menu item itself, for both of these we must not (immediately) disable
      // the delete menu or unset lastHighlightedItem or else deleting won't work
      nop()
      disableDeleteTimer = DispatchSource.scheduledTimerForRunningOnMainQueue(afterDelay: 0.5) { [weak self] in
        self?.deleteItem?.isEnabled = false
        self?.lastHighlightedMenuItem = nil
        self?.disableDeleteTimer = nil
      }
    } else {
      deleteItem?.isEnabled = false
      lastHighlightedMenuItem = nil
    }
  }
  
  // MARK: - adding / removing dynamic clip menu items
  
  private func insertTopAnchorItems() {
    // Anchor items are used in older versions of the OS as nearly empty items containing views
    // who's view frames are used to as bounds for mouse tracking to open the preview popups.
    // Menu item groups for each clip include a trailing anchor item, one preceding all queue items
    // and history items are needed to as the leading fencepost IYKWIM
    guard let protoAnchorItem = protoAnchorItem,
          let preQueueIndex = safeIndex(of: leadingSeparatorItem),
          let preHistoryIndex = safeIndex(of: keyDetectorItem) else {
      return
    }
    
    guard let topQueueAnchorItem = protoAnchorItem.copy() as? NSMenuItem else {
      return
    } 
    insertItem(topQueueAnchorItem, at: preQueueIndex + 1)
    
    guard let topHistoryAnchorItem = protoAnchorItem.copy() as? NSMenuItem else {
      return
    }
    insertItem(topHistoryAnchorItem, at: preHistoryIndex + 1)
  }
  
  func buildDynamicItems() {
    clearQueueItems()
    clearHistoryItems()
    clearBatchItems()
    
    let clips = Array<Clip>(history.all.prefix(maxClipMenuItems))
    guard clips.count >= queue.size else {
      print("yikes, queue size \(queue.size) bigger than the number of stored clips \(clips.count)")
      return
    }
    
    guard var queueInsertIndex = postQueueItemIndex else {
      print("yikes, can't find the place to insert queue menu items")
      return
    }
    for clip in clips.prefix(queue.size) {
      let menuItems = buildHistoryItemAlternates(clip)
      safeInsertItems(menuItems, at: queueInsertIndex)
      queueInsertIndex += menuItems.count
    }
    
    if UserDefaults.standard.keepHistory {
      guard var historyInsertIndex = postHistoryItemIndex else {
        print("yikes, can't find the place to insert history menu items")
        return
      }
      for clip in clips.suffix(from: queue.size) {
        let menuItems = buildHistoryItemAlternates(clip)
        safeInsertItems(menuItems, at: historyInsertIndex)
        historyInsertIndex += menuItems.count
      }
    }
    
    guard var batchInsertIndex = postBatchesItemIndex else {
      print("yikes, can't find the place to insert batch menu items")
      return
    }
    for batch in history.batches {
      let menuItem = buildBatchItem(batch)
      safeInsertItem(menuItem, at: batchInsertIndex)
      batchInsertIndex += 1
    }
  }
  
  private func buildHistoryItemAlternates(_ clip: Clip) -> [NSMenuItem] {
    guard let protoCopyItem = protoCopyItem, let protoReplayItem = protoReplayItem,
          let protoAnchorItem = protoAnchorItem else {
      return []
    }
    
    let menuItems: [NSMenuItem]
    if !usePopoverAnchors {
      menuItems = [
        (protoCopyItem.copy() as! ClipMenuItem).configured(withClip: clip, num: 1, of: 2),
        (protoReplayItem.copy() as! ClipMenuItem).configured(withClip: clip, num: 2, of: 2)
      ]
    } else {
      menuItems = [
        (protoCopyItem.copy() as! ClipMenuItem).configured(withClip: clip, num: 1, of: 3),
        (protoReplayItem.copy() as! ClipMenuItem).configured(withClip: clip, num: 2, of: 3),
        (protoAnchorItem.copy() as! NSMenuItem)
      ]
    }
    
    assert(menuItems.count == historyItemGroupCount)
    
    return menuItems
  }
  
  private func buildBatchItem(_ batch: Batch) -> NSMenuItem {
    // TODO: this
    NSMenuItem()
  }
  
  private func clipItemAnchors(for clipItem: ClipMenuItem) -> (NSView, NSView)? {
    guard usePopoverAnchors else {
      return nil
    }
    let clipIndex = index(of: clipItem) 
    let leadingAchorIndex = clipIndex - clipItem.groupIndex
    let trailingAchorIndex = clipIndex - clipItem.groupIndex + clipItem.groupCount + 1
    guard let leadingAchorItem = item(at: leadingAchorIndex), let trailingAchorItem = item(at: trailingAchorIndex) else {
      return nil // not likely
    }
    guard let leadingAchor = leadingAchorItem.view, let trailingAchor = trailingAchorItem.view else {
      print("yikes, can't find anchors for for clip item \(clipIndex), \(leadingAchorIndex),\(trailingAchorIndex) don't both have views")
      return nil
    }
    return (leadingAchor, trailingAchor)
  }
  
  private func clearQueueItems() {
    guard let fromIndex = firstQueueItemIndex, let toIndex = postQueueItemIndex else {
      return
    }
    safeRemoveItem(from: fromIndex, to: toIndex)
  }
  
  private func clearHistoryItems() {
    guard let fromIndex = firstHistoryItemIndex, let toIndex = postHistoryItemIndex else {
      return
    }
    safeRemoveItem(from: fromIndex, to: toIndex)
  }
  
  private func clearBatchItems() {
    guard let fromIndex = firstBatchItemIndex, let toIndex = postBatchesItemIndex else {
      return
    }
    safeRemoveItem(from: fromIndex, to: toIndex)
  }
  
  func iterateOverClipMenuItems(_ closure: (ClipMenuItem)->Void) {
    if let firstQueueIndex = firstQueueItemIndex, let postQueueIndex = postQueueItemIndex,
        firstQueueIndex <= postQueueIndex
    { 
      for index in firstQueueIndex ..< postQueueIndex {
        if let menuItem = item(at: index) as? ClipMenuItem { 
          closure(menuItem)
        }
      }
    } else {
      print("yikes, can't locate the queue menu items section")
    }
    
    if let firstHistoryIndex = firstHistoryItemIndex, let postHistoryIndex = postHistoryItemIndex,
        firstHistoryIndex <= postHistoryIndex
    { 
      for index in firstHistoryIndex ..< postHistoryIndex {
        if let menuItem = item(at: index) as? ClipMenuItem { 
          closure(menuItem)
        }
      }
    } else {
      print("yikes, can't locate the history menu items section")
    }
    
    // TODO: also submenus items in each batch 
  }
  
  // MARK: - update disabled / hidden menu items
  
  private func updateStaticItemShortcuts() {
    // need explicit dispatch to main queue because setShortcut's MainActor declaration
    //DispatchQueue.main.async { [weak self] in
    //  guard let self = self else { return }
    MainActor.assumeIsolated {
      queueStartItem?.setShortcut(for: .queueStart)
      queuedCopyItem?.setShortcut(for: .queuedCopy)
      queuedPasteItem?.setShortcut(for: .queuedPaste)
      
      // might have a start/stop hotkey at some point, something like:
      //if !queue.isOn {
      //  queueStartItem?.setShortcut(for: .queueStartStop)
      //  queueStopItem?.setShortcut(for: nil)
      //} else {
      //  queueStartItem?.setShortcut(for: nil)
      //  queueStopItem?.setShortcut(for: .queueStartStop)
      //}
    }
  }
  
  private func updateDisabledStaticItems() {
    let notBusy = !AppModel.busy
    queueStartItem?.isEnabled = notBusy && !queue.isOn // although expect to be hidden if invalid
    queueReplayItem?.isEnabled = notBusy && queue.isOn && !queue.isReplaying
    queueStopItem?.isEnabled = notBusy && queue.isOn
    queuedCopyItem?.isEnabled = notBusy
    queuedPasteItem?.isEnabled = notBusy && !queue.isEmpty
    queuedPasteMultipleItem?.isEnabled = notBusy && !queue.isEmpty
    queuedPasteAllItem?.isEnabled = notBusy && !queue.isEmpty
    queueAdvanceItem?.isEnabled = notBusy && !queue.isEmpty

    clearItem?.isEnabled = notBusy
    undoCopyItem?.isEnabled = notBusy
    
    deleteItem?.isEnabled = false // until programmatically enabled later as items are highlighted
  }
  
  private func updateStaticItemVisibility() {
    let badgedMenuItemsSupported = if #available(macOS 14, *) { true } else { false }
    let promoteExtras = AppModel.allowPurchases && UserDefaults.standard.promoteExtras && badgedMenuItemsSupported
    if promoteExtras && promoteExtrasBadge == nil, #available(macOS 14, *) {
      promoteExtrasBadge = NSMenuItemBadge(string: NSLocalizedString("promoteextras_menu_badge", comment: ""))
    }
    let haveQueueItems = !queue.isEmpty
    let haveHistoryItems = showsExpandedMenu && historyItemCount > 0
    let haveBatchItems = AppModel.allowSavedBatches && batchItemCount > 0
    
    // Switch visibility of start vs replay menu item
    queueStartItem?.isVisible = !queue.isOn || queue.isReplaying // when on and replaying, show this though expect it will be disabled
    queueReplayItem?.isVisible = !queue.isEmpty && !queue.isReplaying
    
    // Show cancel & advance menu items only when allowed?
    //queueStopItem?.isVisible = queue.isOn
    //queueAdvanceItem?.isVisible = !queue.isEmpty
    
    // Bonus features to hide when not purchased
    queuedPasteAllItem?.isVisible = AppModel.allowPasteMultiple || promoteExtras
    queuedPasteMultipleItem?.isVisibleAlternate = AppModel.allowPasteMultiple || promoteExtras
    if !AppModel.allowPasteMultiple && promoteExtras, #available(macOS 14, *), let bedge = promoteExtrasBadge as? NSMenuItemBadge {
      queuedPasteAllItem?.badge = bedge
      queuedPasteMultipleItem?.badge = bedge
      // important: if we add key equivalents to these items, must save those here
      // and clear the shortcut when adding badge, like the undo item below
    }
    undoCopyItem?.isVisible = AppModel.allowUndoCopy || promoteExtras
    if !AppModel.allowUndoCopy && promoteExtras, #available(macOS 14, *), let bedge = promoteExtrasBadge as? NSMenuItemBadge {
      undoCopyItem?.badge = bedge
      cacheUndoCopyItemShortcut = undoCopyItem?.keyEquivalent ?? ""
      undoCopyItem?.keyEquivalent = ""
    } else if (undoCopyItem?.keyEquivalent.isEmpty ?? false) && !cacheUndoCopyItemShortcut.isEmpty {
      undoCopyItem?.keyEquivalent = cacheUndoCopyItemShortcut
      cacheUndoCopyItemShortcut = ""
    }
    
    // Delete item visibility
    deleteItem?.isVisible = haveQueueItems || haveHistoryItems || haveBatchItems
    clearItem?.isVisible = haveQueueItems || haveHistoryItems
  }
  
  private func updateDynamicClipItemVisibility() {
    let showQueueSection = !queue.isEmpty
    let showHistorySection = showsExpandedMenu && historyItemCount > 0
    let showBatchItems = AppModel.allowSavedBatches && !showsExpandedMenu && batchItemCount > 0
    
    // Queue section
    if let from = firstQueueItemIndex, let to = postQueueItemIndex, from <= to {
      if !showQueueSection && queueItemCount > 0 {
        print("yikes, queue is empty but there still exists some queue menu items")
      }
      for index in from ..< to {
        makeVisible(showQueueSection, clipMenuItemAt: index)
      }
      postQueueSeparatorItem?.isVisible = showQueueSection
    } else {
      print("yikes, can't locate the queue menu items section")
    }
    
    // History section, starting with the filter field
    let showFilterField = showsFilterField && showHistorySection
    if !removeViewToHideMenuItem {
      filterFieldItem?.isVisible = showFilterField
    } else if let filterFieldItem = filterFieldItem {
      // hiding items with views not working well in macOS <= 14! remove view when hiding
      if !showFilterField && filterFieldItem.view != nil {
        filterFieldViewCache = filterFieldItem.view as? FilterFieldView
        filterFieldItem.view = nil
      } else if showFilterField && filterFieldItem.view == nil {
        filterFieldItem.view = filterFieldViewCache
        filterFieldViewCache = nil
      }
    }
    if let from = firstHistoryItemIndex, let to = postHistoryItemIndex, from <= to {
      let endVisible = from + maxVisibleHistoryClips * historyItemGroupCount
      for index in from ..< to {
        makeVisible(showHistorySection && index < endVisible, clipMenuItemAt: index)
      }
      postHistorySeparatorItem?.isVisible = showHistorySection
    } else {
      print("yikes, can't locate the history menu items section")
    }
    
    // Batches section
    if let from = firstBatchItemIndex, let to = postBatchesItemIndex, from <= to {
      //if showBatchItems
      for index in from ..< to {
        makeVisible(showBatchItems, clipMenuItemAt: index)
      }
      postBatchesSeparatorItem?.isVisible = showBatchItems
    } else {
      print("yikes, can't locate the batches menu items section")
    }
  }
  
  // MARK: - sync up menu when history and queue changed
  
  func addedClipToQueue(_ clip: Clip) {
    // TODO: this
    // potentially remove last history menu items
  }
  
  func addedClipToHistory(_ clip: Clip) {
    // TODO: this
  }
  
  func poppedClipOffQueue() {
    // TODO: this
  }
  
  func poppedClipsOffQueue(_ count: Int) {
    // TODO: this
  }
  
  func cancelledQueue() {
    // TODO: this
  }
  
  func startedQueueFromHistory(atClip headClip: Clip) {
    // TODO: this
  }
  
  func deletedClipFromQueue(_ clip: Clip) {
    // TODO: this, refer to old delete(position:)
  }
  
  //  @discardableResult
  //  func delete(position: Int) -> String? {
  //    guard position >= 0 && position < clips.count else {
  //      return nil
  //    }
  //    
  //    let clip = clips[position]
  //    let value = clip.value
  //    let wasHighlighted = clip.item == lastHighlightedItem?.clipItem
  //    
  //    // remove menu items, history item, this class's indexing item
  //    clip.menuItems.forEach(safeRemoveItem)
  //    history.remove(clip.item)
  //    clips.remove(at: position)
  //    
  //    // clean up head of queue item
  //    if clip == headOfQueueClip {
  //      setHeadOfQueueClipItem(position > 0 ? clips[position - 1] : nil)
  //      
  //      // after deleting the selected last-queued item, highlight the previous item (new last one in queue)
  //      // instead of letting the system highlight the next one
  //      if wasHighlighted && position > 0 {
  //        let prevItem = clips[position - 1].menuItems[0]
  //        highlight(prevItem)
  //        lastHighlightedItem = prevItem
  //      }
  //    }
  //    
  //    return value
  //  }
  
  func deletedClipFromHistory(_ clip: Clip) {
    // TODO: this
  }
    
  func deletedHistory() {
    // TODO: this
  }
  
  func addedBatch(_ batch: Batch) {
    let sortedBatches = history.batches
    guard let insertionIndex = sortedBatches.firstIndex(where: { $0 == batch }) else {
      return
    }
    
    let menuItem = buildBatchItem(batch)
    // TODO: finish this
    // ...
    //appendBatchMenuItem(menuItem)
  }
  
  func deletedBatch(_ batch: Batch) {
    // TODO: this
  }
  
  func assignedShortcut(toBatch batch: Batch) {
    // TODO: this
  }
  
//  func add(_ clip: Clip) {
//    let sortedClips = history.all
//    guard let clipIndex = sortedClips.firstIndex(where: { $0 == clip }) else {
//      print("yikes, called with clip not stored in history \"\(clip.title?.prefix(8) ?? "?")\"")
//      return
//    }
//    
//    guard let z = topHistoryAnchorItem ?? keyDetectorItem, let zerothHistoryIndex = safeIndex(of: z) else {
//      return
//    }
//    let insertionIndex = zerothHistoryIndex + clipIndex * historyItemGroupCount
//    
//    let menuItems = buildHistoryItemAlternates(clip)
//    guard let menuItem = menuItems.first else {
//      return
//    }
//    let clip = ClipRecord(
//      value: menuItem.value,
//      item: clip,
//      menuItems: menuItems
//    )
//    clips.insert(clip, at: insertionIndex)
//    
//    let firstHistoryMenuItemIndex = index(of: zerothHistoryHeaderItem) + 1
//    let menuItemInsertionIndex = firstHistoryMenuItemIndex + self.historyMenuItemsGroupCount * insertionIndex
//    if let historyEndItem = trailingSeparatorItem {
//      let sanityCheckIndex = index(of: historyEndItem)
//      if menuItemInsertionIndex != sanityCheckIndex {
//        print("yikes, inserting menu items for clip \"\(clip.title ?? "?")\", insertion index \(menuItemInsertionIndex) doesn't match that appendHistoryMenuItem would have used \(sanityCheckIndex)")
//      }
//    } else {
//      print("yikes, inserting menu items for clip \"\(clip.title ?? "?")\", cannot compare insertion index \(menuItemInsertionIndex) because boundary menu item appendHistoryMenuItem would have used is nil")
//    }
//    
//    ensuringInEventModeIfVisible {
////      for menuItem in menuItems {
////        self.appendHistoryMenuItem(menuItem)
////      }
//      var index = menuItemInsertionIndex
//      for menuItem in menuItems {
//        self.safeInsertItem(menuItem, at: index)
//        index += 1
//      }
//      
//      // i wish there was an explanation why clearRemovedItems should be called here
//      self.clearRemovedItems()
//    }
//  }
  
//  func clearHistoryItems() {
//    for clipRecord in clips {
//      clipRecord.menuItems.forEach(safeRemoveItem)
//      
//      if let removeIndex = clips.firstIndex(of: clipRecord) {
//        clips.remove(at: removeIndex)
//      }
//    }
//    
//    if let item = headOfQueueClip, clips.contains(item) {
//      headOfQueueClip = nil
//    }
//    
//    clearAllHistoryMenuItems()
//    headOfQueueClip = nil
//  }
  
//  func updateHeadOfQueue(index: Int?) {
//    headOfQueueClip?.menuItems.forEach { $0.isHeadOfQueue = false }
//    if let index = index, index >= 0, index < clips.count {
//      setHeadOfQueueClipItem(clips[index])
//    } else {
//      setHeadOfQueueClipItem(nil)
//    }
//  }
//  
//  func setHeadOfQueueClipItem(_ clipRecord: ClipRecord?) {
//    headOfQueueClip = clipRecord
//    clipRecord?.menuItems.forEach { $0.isHeadOfQueue = true }
//  }
  
  // MARK: - helpers for filter field view
  
  func updateFilter(filter: String) {
    let clips = Array<Clip>(history.all.prefix(maxClipMenuItems).suffix(from: queue.size))
    guard !clips.isEmpty, let firstMenuIndex = firstHistoryItemIndex else {
      return
    }
    guard historyItemCount == clips.count, let firstItem = firstHistoryItem as? ClipMenuItem, firstItem.clip == clips.first else {
      print("yikes, clips and clip menu items are not in sync, \(historyItemCount) vs \(clips.count), " +
            "first clip \"\(clips.first?.title ?? "")\" vs \((firstHistoryItem as? ClipMenuItem)?.title ?? String(describing: firstHistoryItem))")
      return
    }
    
    let results = search.search(string: filter, within: clips)
    
    var firstResultMenuItem: ClipMenuItem? = nil
    
    // Make visible only the clip menu items corresponding to the results: for each result, scan the
    // next group of menu items and hide them until a match to the result is found/
    // This presumes the results and the menu items are in the same order, and wouldn't work otherwise.
    var menuIndex = firstMenuIndex
    for result in results {
      var found = false
      while !found && menuIndex < firstMenuIndex {
        guard let menuItem = item(at: menuIndex) as? ClipMenuItem, let menuItemClip = menuItem.clip else {
          break
        }
        found = menuItemClip === result.object
        if found && firstResultMenuItem == nil {
          firstResultMenuItem = menuItem
        }
        for index in menuIndex ..< menuIndex + historyItemGroupCount {
          makeVisible(found, clipMenuItemAt: index)
        }
        menuIndex += historyItemGroupCount
      }
    }
    
    isFiltered = results.count < clips.count
    if let firstItem = firstResultMenuItem {
      highlight(firstItem)
    }
  }
  
  func select(_ searchQuery: String) {
    if let item = highlightedItem {
      performActionForItem(at: index(of: item))
    }
    // omit Maccy fallback of copying the search query, i can't make sense of that
    // Maccy does this here, maybe keep?: cancelTrackingWithoutAnimation()
  }
  
  func selectPrevious() {
    if !highlightNext(items.reversed()) {
      highlight(highlightableItems(items).last) // start from the end after reaching the first item
    }
  }
  
  func selectNext() {
    if !highlightNext(items) {
      highlight(highlightableItems(items).first) // start from the beginning after reaching the last item
    }
  }
  
  // MARK: - helpers for model & others
  
  func highlightedClipMenuItem() -> ClipMenuItem? {
    guard let menuItem = lastHighlightedMenuItem as? ClipMenuItem else {
      return nil
    }
    
    // When deleting mulitple items by holding the removal keys
    // we sometimes get into a race condition with menu updating indices.
    // https://github.com/p0deje/Maccy/issues/628
    guard index(of: menuItem) >= 0 else {
      return nil
    }
    
    return menuItem
  }
  
  func resizeImageMenuItems() {
    iterateOverClipMenuItems {
      $0.resizeImage()
    }
  }
  
  func regenerateMenuItemTitles() {
    iterateOverClipMenuItems {
      $0.regenerateTitle()
    }
    update()
  }
  
  func performQueueModeToggle() {
    guard !AppModel.busy else { return }
    
    if !queue.isOn {
      guard let queueStartItem = queueStartItem else { return }
      performActionForItem(at: index(of: queueStartItem))
      
    } else if queue.isOn && queue.isEmpty {
      guard let queueStopItem = queueStopItem else { return }
      performActionForItem(at: index(of: queueStopItem)) // TODO: find out why this usually doesn't work
    }
  }
  
  func enableExpandedMenu(_ enable: Bool, full: Bool = false) {
    showsExpandedMenu = enable // gets set back to false in menuWillOpen or menuDidClose
    showsFullExpansion = full
  }
  
  // MARK: - menu item highlighting
  
  private func highlightNext(_ items: [NSMenuItem]) -> Bool {
    let highlightableItems = self.highlightableItems(items)
    let currentHighlightedItem = highlightedItem ?? highlightableItems.first
    var itemsIterator = highlightableItems.makeIterator()
    while let item = itemsIterator.next() {
      if item == currentHighlightedItem {
        if let itemToHighlight = itemsIterator.next() {
          highlight(itemToHighlight)
          return true
        }
        break
      }
    }
    return false
  }
  
  private func highlightableItems(_ items: [NSMenuItem]) -> [NSMenuItem] {
    return items.filter {
      if $0.isSeparatorItem || !$0.isEnabled || $0.isHidden { return false }
      if $0 is ClipMenuItem && $0.keyEquivalentModifierMask.isEmpty == false { return false }
      return true
    }
  }
  
  private func highlight(_ itemToHighlight: NSMenuItem?) {
    if #available(macOS 14, *) {
      DispatchQueue.main.async { self.highlightItem(itemToHighlight) }
    } else {
      highlightItem(itemToHighlight)
    }
  }
  
  private func highlightItem(_ itemToHighlight: NSMenuItem?) {
    let highlightItemSelector = NSSelectorFromString("highlightItem:")
    // We need to first highlight am menu item somewhere near the top of the menu to
    // force menu redrawing  (was using the search menu item, but its now sometimes gone)
    // when it has more items that can fit into the screen height and scrolling items
    // are added to the top and bottom of menu.
    perform(highlightItemSelector, with: queuedCopyItem)
    if let item = itemToHighlight, !item.isHighlighted, items.contains(item) {
      perform(highlightItemSelector, with: item)
    } else {
      // un-highlight the copy menu item we just highlighted
      perform(highlightItemSelector, with: nil)
    }
  }
  
  // rethink if something like these functinos are needed now:
//  private func rebuildItemsAsNeeded() {
//    let availableHistoryCount = clips.count
//    let presentItemsCount = historyMenuItems.count / historyMenuItemsGroupCount
//    
//    let maxItems = queue.isOn ? max(maxMenuItems, queue.size) : maxMenuItems
//    
//    let maxAvailableItems = maxItems <= 0 || maxItems > availableHistoryCount ? availableHistoryCount : maxItems
//    if presentItemsCount < maxAvailableItems {
//      appendItemsUntilLimit(maxAvailableItems)
//    } else if presentItemsCount > maxAvailableItems {
//      removeItemsOverLimit(maxItems)
//    }
//  }
//  
//  private func removeItemsOverLimit(_ limit: Int) {
//    var count = historyMenuItems.count / historyMenuItemsGroupCount
//    for clipRecord in clips.reversed() {
//      if count <= limit {
//        return
//      }
//      
//      // if menu doesn't contains this item, skip it
//      let menuItems = clipRecord.menuItems.filter({ historyMenuItems.contains($0) })
//      if menuItems.isEmpty {
//        continue
//      }
//      
//      menuItems.forEach(safeRemoveItem)
//      count -= 1
//    }
//  }
//  
//  private func appendItemsUntilLimit(_ limit: Int) {
//    var count = historyMenuItems.count / historyMenuItemsGroupCount
//    for clipRecord in clips {
//      if count >= limit {
//        return
//      }
//      
//      // if menu contains this item already, skip it
//      let menuItems = clipRecord.menuItems.filter({ !historyMenuItems.contains($0) })
//      if menuItems.isEmpty {
//        continue
//      }
//      
//      menuItems.forEach(appendHistoryMenuItem)
//      if clipRecord == headOfQueueClip {
//        menuItems.forEach { $0.isHeadOfQueue = true }
//      }
//      count += 1
//    }
//  }
  
//  private func clearRemovedItems() {
//    let currentHistoryItems = history.all
//    for clipRecord in clips {
//      if let historyItem = clipRecord.item, !currentHistoryItems.contains(historyItem) {
//        clipRecord.menuItems.forEach(safeRemoveItem)
//        
//        if let removeIndex = clips.firstIndex(of: clipRecord) {
//          clips.remove(at: removeIndex)
//        }
//        
//        if let item = headOfQueueClip, item == clipRecord {
//          headOfQueueClip = nil
//        }
//      }
//    }
//  }
  
//  private func updateMenuItemVisibility() {
//    guard let historyHeaderItem = filterFieldItem, let trailingSeparatorItem = trailingSeparatorItem else {
//      return
//    }
//    let badgedMenuItemsSupported = if #available(macOS 14, *) { true } else { false }
//    let promoteExtras = AppModel.allowPurchases && UserDefaults.standard.promoteExtras && badgedMenuItemsSupported
//    if promoteExtras && promoteExtrasBadge == nil, #available(macOS 14, *) {
//      promoteExtrasBadge = NSMenuItemBadge(string: NSLocalizedString("promoteextras_menu_badge", comment: ""))
//    }
//    
//    let haveHistoryItems = !queue.isEmpty || (showsExpandedMenu && !clips.isEmpty)
//    
//    // Switch visibility of start vs replay menu item
//    queueStartItem?.isVisible = !queue.isOn || queue.isReplaying // when on and replaying, show this though expect it will be disabled
//    queueReplayItem?.isVisible = !queue.isEmpty && !queue.isReplaying
//    
//    // Show cancel & advance menu items only when allowed?
//    //queueStopItem?.isVisible = queue.isOn
//    //queueAdvanceItem?.isVisible = !queue.isEmpty
//    
//    // Bonus features to hide when not purchased
//    queuedPasteAllItem?.isVisible = AppModel.allowPasteMultiple || promoteExtras
//    queuedPasteMultipleItem?.isVisibleAlternate = AppModel.allowPasteMultiple || promoteExtras
//    if !AppModel.allowPasteMultiple && promoteExtras, #available(macOS 14, *), let bedge = promoteExtrasBadge as? NSMenuItemBadge {
//      queuedPasteAllItem?.badge = bedge
//      queuedPasteMultipleItem?.badge = bedge
//      // important: if we add key equivalents to these items, must save those here
//      // and clear the shortcut when adding badge, like the undo item below
//    }
//    undoCopyItem?.isVisible = AppModel.allowUndoCopy || promoteExtras
//    if !AppModel.allowUndoCopy && promoteExtras, #available(macOS 14, *), let bedge = promoteExtrasBadge as? NSMenuItemBadge {
//      undoCopyItem?.badge = bedge
//      cacheUndoCopyItemShortcut = undoCopyItem?.keyEquivalent ?? ""
//      undoCopyItem?.keyEquivalent = ""
//    } else if (undoCopyItem?.keyEquivalent.isEmpty ?? false) && !cacheUndoCopyItemShortcut.isEmpty {
//      undoCopyItem?.keyEquivalent = cacheUndoCopyItemShortcut
//      cacheUndoCopyItemShortcut = ""
//    }
//    
//    // Delete item visibility
//    deleteItem?.isVisible = haveHistoryItems
//    clearItem?.isVisible = haveHistoryItems
//    
//    // Visiblity of the history header and trailing separator
//    // (the expanded menu means the search header and all of the history items)
//    // hiding items with views not working well in macOS <= 14! remove view when hiding
//    if removeViewToHideMenuItem {
//      if !showsFilterField && historyHeaderItem.view != nil {
//        historyHeaderViewCache = historyHeaderItem.view as? FilterFieldView
//        historyHeaderItem.view = nil
//      } else if showsFilterField && historyHeaderItem.view == nil {
//        historyHeaderItem.view = historyHeaderViewCache
//        historyHeaderViewCache = nil
//      }
//    }
//    historyHeaderItem.isVisible = showsFilterField
//    trailingSeparatorItem.isVisible = showsSearchHeader || haveHistoryItems
//    
//    // Show or hide the desired history items
//    let zerothHistoryHeaderItem = topHistoryAnchorItem ?? historyHeaderItem
//    let firstHistoryMenuItemIndex = index(of: zerothHistoryHeaderItem) + 1
//    let endHistoryMenuItemIndex = index(of: trailingSeparatorItem)
//    var remainingHistoryMenuItemIndex = firstHistoryMenuItemIndex
//    
//    // First queue items to always show when not filtering by a search term
//    if !queue.isEmpty && !isFiltered {
//      let endQueuedItemIndex = firstHistoryMenuItemIndex + historyItemGroupCount * queue.size
//      
//      for index in firstHistoryMenuItemIndex ..< endQueuedItemIndex {
//        makeVisible(true, clipMenuItemAt: index)
//      }
//      
//      remainingHistoryMenuItemIndex = endQueuedItemIndex
//    }
//    
//    if remainingHistoryMenuItemIndex > endHistoryMenuItemIndex {
//      os_log(.default, "range fail %d ..< %d, has topanchor: %d, first %d, end %d, remaining %d which might eq first + queue size %d * %d",
//             remainingHistoryMenuItemIndex, endHistoryMenuItemIndex,
//             topHistoryAnchorItem != nil ? 1 : 0, firstHistoryMenuItemIndex, endHistoryMenuItemIndex,
//             remainingHistoryMenuItemIndex, queue.size, historyItemGroupCount)
//      remainingHistoryMenuItemIndex = endHistoryMenuItemIndex
//    }
//    
//    // Remaining history items hidden unless showing the expanded menu
//    for index in remainingHistoryMenuItemIndex ..< endHistoryMenuItemIndex {
//      makeVisible(showsExpandedMenu, clipMenuItemAt: index)
//    }
//  }
  
  // MARK: - utility functions
  
  private func makeVisible(_ visible: Bool, clipMenuItemAt index: Int) {
    guard let menuItem = item(at: index) else {
      return
    }
    if menuItem is ClipMenuItem {
      // any of our clip menu items with a keyEquivalentModifierMask set are alternatess,
      // they need special case for making hidden or visible
      if menuItem.keyEquivalentModifierMask.isEmpty {
        menuItem.isVisible = visible
      } else {
        menuItem.isVisibleAlternate = visible
      }
    } else {
      // expect this to be used on ClipMenuItem, anchors, maybe separators and for those
      // this is ok, but wouldn't be if given some other NSMenuItem that's an alternate
      menuItem.isVisible = visible
    }
  }
  
  private func safeInsertItem(_ newItem: NSMenuItem, at index: Int) {
    guard !items.contains(newItem), index <= items.count else {
      return
    }
    
    sanityCheckIndexClipMenuItemIndex(index, forInserting: true)
    
    insertItem(newItem, at: index)
  }
  
  private func safeInsertItems(_ newItems: [NSMenuItem], at index: Int) {
    guard index <= items.count else {
      return
    }
    
    sanityCheckIndexClipMenuItemIndex(index, forInserting: true)
    
    var incrementIndex = index
    for newItem in newItems {
      guard !items.contains(newItem) else {
        continue
      }
      
      insertItem(newItem, at: incrementIndex)
      incrementIndex += 1
    }
  }
  
  private func safeRemoveItem(_ deleteItem: NSMenuItem) {
    guard items.contains(deleteItem) else {
      return
    }
    
    sanityCheckIndexClipMenuItemIndex(index(of: deleteItem))
    
    removeItem(deleteItem)
  }
  
  private func safeRemoveItems(_ deleteItems: [NSMenuItem]) {
    for deleteItem in deleteItems {
      guard items.contains(deleteItem) else {
        return
      }
      
      sanityCheckIndexClipMenuItemIndex(index(of: deleteItem))
      
      removeItem(deleteItem)
    }
  }
  
  private func safeRemoveItem(at index: Int) {
    guard index <= items.count else {
      return
    }
    
    sanityCheckIndexClipMenuItemIndex(index)
    
    removeItem(at: index)
  }
  
  private func safeRemoveItem(from fromIndex: Int, to toIndex: Int) {
    guard fromIndex <= toIndex && toIndex <= items.count else {
      return
    }
    
    for index in fromIndex ..< toIndex {
      sanityCheckIndexClipMenuItemIndex(index)
      
      removeItem(at: index)
    }
  }
  
  private func safeIndex(of item: NSMenuItem?) -> Int? {
    guard let item = item else {
      return nil
    }
    let index = index(of: item)
    guard index >= 0 else {
      return nil
    }
    return index
  }
  
  private func safeItem(at index: Int?) -> NSMenuItem? {
    guard let index = index else {
      return nil
    }
    return item(at: index)
  }  
  
  private func sanityCheckIndexClipMenuItemIndex(_ i: Int, forInserting inserting: Bool = false) {
    guard item(at: i) != nil else { // never add clip item to very end, so don't have to add `inserting==false`
      fatalError("sanityCheckIndex failure 1")
    }
    guard let firstQueueIndex = firstQueueItemIndex, let postQueueIndex = postQueueItemIndex,
          let firstHistoryIndex = firstHistoryItemIndex, let postHistoryIndex = postHistoryItemIndex else {
      fatalError("sanityCheckIndex failure 2")
    }
    if i < firstQueueIndex {
      fatalError("sanityCheckIndex failure 3")
    }
    if i > (inserting ? postQueueIndex : postQueueIndex - 1) && i < firstHistoryIndex {
      fatalError("sanityCheckIndex failure 4")
    }
    if i > (inserting ? postHistoryIndex : postHistoryIndex - 1) {
      fatalError("sanityCheckIndex failure 5")
    }
  }
  
  private func ensuringInEventModeIfVisible(dispatchLater: Bool = false, block: @escaping () -> Void) {
    if isVisible && (
      dispatchLater ||
      RunLoop.current != RunLoop.main ||
      RunLoop.current.currentMode != .eventTracking)
    {
      RunLoop.main.perform(inModes: [.eventTracking], block: block)
    } else {
      block()
    }
  }
  
  func addDebugItems() {
    #if DEBUG
    if AppDelegate.allowTestWindow {
      let endIndex = items.count
      let showWindowItem = NSMenuItem(title: "Show Test Window", action: #selector(AppDelegate.showTestWindow(_:)), keyEquivalent: "")
      let hideWindowItem = NSMenuItem(title: "Hide Test Window", action: #selector(AppDelegate.hideTestWindow(_:)), keyEquivalent: "")
      insertItem(NSMenuItem.separator(), at: endIndex)
      insertItem(showWindowItem, at: endIndex + 1)
      insertItem(hideWindowItem, at: endIndex + 2)
    }
    #endif
  }
  
}
// swiftlint:enable type_body_length

// MARK: -

// an isVisible property makes logic more clear than with the isHidden property,
// eliminating many double negatives
// isVisibleAlternate is for making an alternate menu items visible, it isolates
// some differences between macOS14 and earlier
extension NSMenuItem {
  var isVisible: Bool {
    get {
      !isHidden
    }
    set {
      isHidden = !newValue
    }
  }
  var isVisibleAlternate: Bool {
    get {
      if #unavailable(macOS 14) {
        isAlternate && !isHidden
      } else {
        isAlternate
      }
    }
    set {
      isAlternate = newValue
      isHidden = !newValue
    }
  }
}
// swiftlint:enable file_length
