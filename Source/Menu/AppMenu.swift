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
  
  private var maxClipMenuItems: Int { max(AppModel.effectiveMaxClips, queue.size) }
  private var maxVisibleHistoryClips: Int {
    showsExpandedMenu && showsFullExpansion ? maxClipMenuItems - queue.size : max(AppModel.effectiveMaxVisibleClips  - queue.size, 0)
  }
  
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
  private var useNaturalOrder = false
  private var isFiltered = false
  private var isVisible = false
  
  private var disableDeleteTimer: DispatchSourceTimer?
  private var promoteExtrasBadge: NSObject?
  private var queueHeadBadge: NSObject?
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
  private var firstQueueItem: NSMenuItem? { safeItem(at: firstQueueItemIndex) } // result might be postQueueSeparatorItem
  private var firstQueueItemIndex: Int? { safeIndex(of: preQueueItem)?.advanced(by: 1) }
  private var postQueueItemIndex: Int? { safeIndex(of: postQueueItem) }
  private var queueClipsCount: Int { queueItemCount / historyItemGroupCount }
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
  private var historyClipsCount: Int { historyItemCount / historyItemGroupCount }
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
    updateMenuItemStates()
  }
  
  func menuWillOpen(_ menu: NSMenu) {
    isVisible = true
    
    useNaturalOrder = !UserDefaults.standard.keepHistory // TODO: make this work, maybe add UserDefaults.standard.naturalOrder
    
    // potentially revert expanded mode flag initially set from an option-click on the menu icon
    if showsExpandedMenu && (useNaturalOrder || !AppModel.allowExpandedHistory || historyItemCount == 0) {
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
    
    // ensure the menu includes the entire queue, even if that exceeds the
    // user's desired maximum to show in the menu
    let maximumMenuClips = max(AppModel.effectiveMaxClips, queue.size)
    
    let clips = Array<Clip>(history.all.prefix(maximumMenuClips))
    guard clips.count >= queue.size else {
      fatalError("queue size \(queue.size) bigger than the number of stored clips \(clips.count)")
    }
    
    guard var queueInsertIndex = postQueueItemIndex else {
      fatalError("can't find the place to insert queue menu items")
    }
    for clip in clips.prefix(queue.size) {
      let menuItems = buildHistoryItemAlternates(clip)
      safeInsertItems(menuItems, at: queueInsertIndex)
      queueInsertIndex += menuItems.count
    }
    
    if UserDefaults.standard.keepHistory {
      guard var historyInsertIndex = postHistoryItemIndex else {
        fatalError("can't find the place to insert history menu items")
      }
      for clip in clips.suffix(from: queue.size) {
        let menuItems = buildHistoryItemAlternates(clip)
        safeInsertItems(menuItems, at: historyInsertIndex)
        historyInsertIndex += menuItems.count
      }
    }
    
    guard var batchInsertIndex = postBatchesItemIndex else {
      fatalError("can't find the place to insert batch menu items")
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
      fatalError("can't find anchors for for clip item \(clipIndex), \(leadingAchorIndex),\(trailingAchorIndex) don't both have views")
    }
    return (leadingAchor, trailingAchor)
  }
  
  private func clearQueueItems() {
    guard let fromIndex = firstQueueItemIndex, let toIndex = postQueueItemIndex else {
      return
    }
    safeRemoveItems(at: fromIndex ..< toIndex)
  }
  
  private func clearHistoryItems() {
    guard let fromIndex = firstHistoryItemIndex, let toIndex = postHistoryItemIndex else {
      return
    }
    safeRemoveItems(at: fromIndex ..< toIndex)
  }
  
  private func clearBatchItems() {
    guard let fromIndex = firstBatchItemIndex, let toIndex = postBatchesItemIndex else {
      return
    }
    safeRemoveItems(at: fromIndex ..< toIndex)
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
      fatalError("can't locate the queue menu items section")
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
      fatalError("can't locate the history menu items section")
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
  
  private func updateMenuItemStates() {
    updateDisabledStaticItems()
    updateStaticItemVisibility()
    updateDynamicClipItemVisibility()
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
    let haveBatchItems = showsSavedBatches && batchItemCount > 0
    
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
    let showBatchSection = showsSavedBatches && batchItemCount > 0
    
    // Queue section
    if let first = firstQueueItemIndex, let end = postQueueItemIndex, first <= end {
      if !showQueueSection && first != end {
        fatalError("queue is empty but there still exists some queue menu items")
      }
      for index in first ..< end {
        makeClipItem(at: index, visible: showQueueSection, badgeless: true)
      }
      
      // badge the last item, which is the head of the queue 
      if first < end, #available(macOS 14, *) {
        if queueHeadBadge == nil {
          queueHeadBadge = NSMenuItemBadge(string: NSLocalizedString("first_replay_item_badge", comment: ""))
        }
        
        if let lastQueueItem = safeItem(at: end - historyItemGroupCount) {
          lastQueueItem.badge = queueHeadBadge as? NSMenuItemBadge
        }
        // TODO: for useNaturalOrder I think instead we want this
//        if useNaturalOrder, let firstQueueItem = safeItem(at: first) {
//          firstQueueItem.badge = queueHeadBadge as? NSMenuItemBadge
//        } else if let lastQueueItem = safeItem(at: end - historyItemGroupCount) {
//          lastQueueItem.badge = queueHeadBadge as? NSMenuItemBadge
//        }
      }
      postQueueSeparatorItem?.isVisible = showQueueSection
      
    } else {
      fatalError("can't locate the queue menu items section")
    }
    
    // History section, starting with the filter field
    let maxVisibleHistoryClips = !showHistorySection ? 0 :
      max((showsFullExpansion ? AppModel.effectiveMaxClips : AppModel.effectiveMaxVisibleClips) - queue.size, 0)
    
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
    if let first = firstHistoryItemIndex, let end = postHistoryItemIndex, first <= end {
      let endVisible = first + maxVisibleHistoryClips * historyItemGroupCount
      for index in first ..< end {
        makeClipItem(at: index, visible: showHistorySection && index < endVisible, badgeless: true)
      }
      postHistorySeparatorItem?.isVisible = showHistorySection
    } else {
      fatalError("can't locate the history menu items section")
    }
    
    // Batches section
    if let first = firstBatchItemIndex, let end = postBatchesItemIndex, first <= end {
      for index in first ..< end {
        makeClipItem(at: index, visible: showBatchSection)
      }
      postBatchesSeparatorItem?.isVisible = showBatchSection
    } else {
      fatalError("can't locate the batches menu items section")
    }
  }
  
  private func trimClips() {
    // remove history menu items bottom up to sync with history storage which
    // may have trimmed off the end of its clips to keep within the maximum allowed
    let clips = history.all
    if clips.count >= queueClipsCount + historyClipsCount {
      return
    }
    let lastClip = clips.last
    
    guard var historyVisitIndex = postHistoryItemIndex, let firstHistoryIndex = firstHistoryItemIndex else {
      fatalError("can't locate the history menu items section")
    }
    while historyVisitIndex > firstHistoryIndex {
      historyVisitIndex -= historyItemGroupCount
      guard let menuItemClip = (safeItem(at: historyVisitIndex) as? ClipMenuItem)?.clip else {
        fatalError("menu item at \(historyVisitIndex) is invalid or not a clip menu item: \(String(describing: item(at: historyVisitIndex)))")
      }
      if menuItemClip === lastClip {
        return
      }
      // these history menu items don't match the last clip, remove 'em
      safeRemoveItems(at: historyVisitIndex, count: historyItemGroupCount)
    }
    
    // had this here for some reason, was i intending to trim the queue items as well?
    // TODO: think again about what this might have been for
//    guard var queueVisitIndex = postQueueItemIndex, let firstQueueIndex = firstQueueItemIndex else {
//      fatalError("can't locate the queue menu items section")
//      return
//    }
//    while queueVisitIndex > firstQueueIndex {
//      queueVisitIndex -= historyItemGroupCount
//      guard let menuItemClip = (safeItem(at: historyVisitIndex) as? ClipMenuItem)?.clip else {
//        fatalError("menu item at \(historyVisitIndex) is invalid or not a clip menu item: \(String(describing: item(at: historyVisitIndex)))")
//        return
//      }
//      // looks like i wanted to do something here with menuItemClip
//    }
  }
  
  // MARK: - sync up menu when history and queue changed
  // Whem some of these functions called, global state such as the history and queue
  // are likely to have already been changed and so calling them should be avoided
  // in most cases.
  // Values `index` passed into these functions mean index of clips within the queue
  // or the history excluding the queue, not menu item index.
  
  func addedClipToQueue(_ clip: Clip) {
    guard let index = firstQueueItemIndex else {
      fatalError("can't locate the queue menu items section")
    }
    
    let queueWasEmpty = queueItemCount == 0
    let menuItems = buildHistoryItemAlternates(clip)
    safeInsertItems(menuItems, at: index)
    
    if queueWasEmpty {
      updateMenuItemStates()
    }
    trimClips()
    
    sanityCheckClipMenuItems()
  }
  
  func addedClipToHistory(_ clip: Clip) {
    guard queueItemCount == 0 else {
      return
    }
    guard let index = firstHistoryItemIndex else {
      fatalError("can't locate the queue menu items section")
    }
    
    let historyWasEmpty = historyItemCount == 0
    let menuItems = buildHistoryItemAlternates(clip)
    safeInsertItems(menuItems, at:index)
    
    if historyWasEmpty {
      updateMenuItemStates()
    }
    trimClips()
    
    sanityCheckClipMenuItems()
  }
  
  func pushedClipsOnQueue(_ count: Int) {
    guard count <= historyClipsCount else {
      return
    }
    guard let queueDestIndex = postQueueItemIndex, let historySrcIndex = firstHistoryItemIndex,
          let postHistoryIndex = postHistoryItemIndex else {
      fatalError("can't locate the queue and history menu items sections")
    }
    guard postHistoryIndex > historySrcIndex else {
      fatalError("called to move from first in history to end of queue sections but history empty, \(historySrcIndex)..<\(postHistoryIndex)")
    }
    
//    let queueWasEmpty = queueItemCount == 0
//    let historyWasEmpty = historyItemCount == 0
    saveMoveItems(at: historySrcIndex, count: count * historyItemGroupCount, to: queueDestIndex)
    
//    let queueNowEmpty = queueItemCount == 0
//    let historyNowEmpty = historyItemCount == 0
//    if queueWasEmpty != queueNowEmpty || historyWasEmpty != historyNowEmpty {
//      updateMenuItemStates()
//    }
    
    sanityCheckClipMenuItems()
  }
  
  func poppedClipsOffQueue(_ count: Int) {
    guard count > 0 && count <= queueClipsCount else {
      return
    }
    guard let postQueueIndex = postQueueItemIndex, let firstHistoryIndex = firstHistoryItemIndex else {
      fatalError("can't locate the queue and history menu items sections")
    }
    
//    let queueWasEmpty = queueItemCount == 0
//    let historyWasEmpty = historyItemCount == 0
    saveMoveItems(at: postQueueIndex - count * historyItemGroupCount, count: count * historyItemGroupCount, to: firstHistoryIndex) 
    
//    let queueNowEmpty = queueItemCount == 0
//    let historyNowEmpty = historyItemCount == 0
//    if queueWasEmpty != queueNowEmpty || historyWasEmpty != historyNowEmpty {
//      updateMenuItemStates()
//    }
    
    sanityCheckClipMenuItems()
  }
  
  func poppedClipOffQueue() {
    poppedClipsOffQueue(1)
  }
  
  func cancelledQueue(_ count: Int) {
    poppedClipsOffQueue(count)
  }
  
  func startedQueueFromHistory(_ headIndex: Int) {
    guard queueItemCount == 0 && headIndex > 0 && headIndex < historyClipsCount else {
      return
    }
    
    // since queue is empty, `index` is relative to the history clips
    // and so the number of the clip up to and including it is that index plus 1 
    pushedClipsOnQueue(headIndex + 1)
    
//    updateMenuItemStates()
    
    sanityCheckClipMenuItems()
  }
  
  // of these sync functions only the 2 deletedClip ones need to take care with the 
  // highlighed item, because only when deleting does the menu stay open afterwards
  // (also likewise needs to update item visiblity if the last item in its section
  // is the one deleted, to avoid leaving an unwanted separator menu item showing)
  
  func deletedClipFromQueue(_ index: Int) {
    let clipItemsCount = queueClipsCount
    guard index >= 0 && index < queueClipsCount else {
      return
    }
    let wasLastClip = index == clipItemsCount - 1
    
    guard let firstQueueIndex = firstQueueItemIndex else {
      fatalError("can't locate the queue menu items section")
    }
    
    // TODO: just remove this i think, not needed after all
//    guard let clip = (safeItem(at: index) as? ClipMenuItem)?.clip else {
//      fatalError("menu item at \(index) is invalid or not a clip menu item: \(String(describing: item(at: index)))")
//    }
//    let highlightedQueueIndex = queueIndexHighlighted()
    
    safeRemoveItems(at: firstQueueIndex + index * historyItemGroupCount, count: historyItemGroupCount)
    
    if queueItemCount == 0 {
      updateMenuItemStates() // transform many manu item to account for queue now empty
      
      highlight(nil)
    } else if !wasLastClip { 
      if let item = safeItem(at: firstQueueIndex + index * historyItemGroupCount) {
        highlight(item)
      }
    } else if index > 0 && wasLastClip {
      // after deleting the selected last queued item, highlight the previous item,
      // the new last one in the queue
      if let item = safeItem(at: firstQueueIndex + (index - 1) * historyItemGroupCount) {
        highlight(item)
      }
    }
    
    sanityCheckClipMenuItems()
  }
  
  func deletedClipFromHistory(_ index: Int) {
    guard index >= 0 && index < historyClipsCount else {
      return
    }
    let expectedNumVisibleHistoryClips =
    max((showsFullExpansion ? AppModel.effectiveMaxClips : AppModel.effectiveMaxVisibleClips) - queue.size, 0)
    let wasLastClip = index == expectedNumVisibleHistoryClips - 1
    
    guard let firstHistoryIndex = firstHistoryItemIndex else {
      fatalError("can't locate the history menu items section")
    }
    
    // TODO: just remove this i think, not needed after all
    //    guard let clip = (safeItem(at: index) as? ClipMenuItem)?.clip else {
    //      fatalError("menu item at \(index) is invalid or not a clip menu item: \(String(describing: item(at: index)))")
    //    }
    //    let highlightedHistoryIndex = historyIndexHighlighted()
    
    safeRemoveItems(at: firstHistoryIndex + index * historyItemGroupCount, count: historyItemGroupCount)
    
    if historyItemCount == 0 {
      updateDynamicClipItemVisibility() // removes the now unwanted separator 
      
      highlight(nil)
    } else if !wasLastClip { 
      // after deleting the selected last history item, normally highlight the next item
      if let item = safeItem(at: firstHistoryIndex + index * historyItemGroupCount) {
        highlight(item)
      }
    } else if index > 0 && wasLastClip {
      // after deleting the selected last history item, next highlight the previous item,
      // the new last one in history
      // TODO: maybe sanity check that the expected number of history clips are visible
      if let item = safeItem(at: firstHistoryIndex + (index - 1) * historyItemGroupCount) {
        highlight(item)
      }
    }
    
    sanityCheckClipMenuItems()
  }
  
  private func queueIndexHighlighted() -> Int? {
    guard let item = lastHighlightedMenuItem as? ClipMenuItem, let index = safeIndex(of: item) else {
      return nil
    }
    guard let firstQueueIndex = firstQueueItemIndex, let postQueueIndex = postQueueItemIndex,
          firstQueueIndex <= postQueueIndex else {
      fatalError("can't locate the queue menu items section")
    }
    if index < firstQueueIndex || index >= postQueueIndex {
      return nil
    }
    return (index - firstQueueIndex) / historyItemGroupCount
  }
  
  private func historyIndexHighlighted() -> Int? {
    guard let item = lastHighlightedMenuItem as? ClipMenuItem, let index = safeIndex(of: item) else {
      return nil
    }
    guard let firstHistoryIndex = firstHistoryItemIndex, let postHistoryIndex = postHistoryItemIndex,
          firstHistoryIndex <= postHistoryIndex else {
      fatalError("can't locate the history menu items section")
    }
    if index < firstHistoryIndex || index >= postHistoryIndex {
      return nil
    }
    return (index - firstHistoryIndex) / historyItemGroupCount
  }
  
  func deletedHistory() {
    // means queue and history
    guard let firstHistoryIndex = firstHistoryItemIndex, let postHistoryIndex = postHistoryItemIndex,
          let firstQueueIndex = firstQueueItemIndex, let postQueueIndex = postQueueItemIndex else {
      fatalError("can't locate the queue and history menu items sections")
    }
    
    safeRemoveItems(at: firstHistoryIndex ..< postHistoryIndex)
    safeRemoveItems(at: firstQueueIndex ..< postQueueIndex)
    
//    updateDynamicClipItemVisibility()
    
    sanityCheckClipMenuItems()
  }
  
  func addedBatch(_ batch: Batch) {
//    let sortedBatches = history.batches
//    guard let insertionIndex = sortedBatches.firstIndex(where: { $0 == batch }) else {
//      return
//    }
//    
//    let menuItem = buildBatchItem(batch)
//    // ...
//    appendBatchMenuItem(menuItem)
    // TODO: finish addedBatch
  }
  
  func deletedBatch(_ batch: Batch) {
    // TODO: finish deletedBatch
  }
  
  func assignedShortcut(toBatch batch: Batch) {
    // TODO: finish assignedShortcut
  }
  
  // MARK: - helpers for filter field view
  
  func updateFilter(filter: String) {
    // may be larger than user's desired maximum because always includes everything queued
    let maximumMenuClips = max(AppModel.effectiveMaxClips, queue.size)
    
    let clips = Array<Clip>(history.all.prefix(maximumMenuClips).suffix(from: queue.size))
    guard !clips.isEmpty, let firstMenuIndex = firstHistoryItemIndex else {
      return
    }
    guard historyClipsCount == clips.count, let firstItem = firstHistoryItem as? ClipMenuItem, firstItem.clip == clips.first else {
      fatalError("clips and clip menu items are not in sync, \(historyClipsCount) vs \(clips.count), " +
            "first clip \"\(clips.first?.title ?? "")\" vs \((firstHistoryItem as? ClipMenuItem)?.title ?? String(describing: firstHistoryItem))")
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
          makeClipItem(at: index, visible: found)
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
  
  // MARK: - utility functions
  
  private func makeClipItem(at index: Int, visible: Bool, badgeless: Bool = false) {
    guard let menuItem = item(at: index) as? ClipMenuItem else {
      return
    }
    
    makeClipItem(menuItem, visible: visible)
    
    if badgeless, #available(macOS 14, *) {
      menuItem.badge = nil
    }
  }
  
  private func makeClipItem(_ menuItem: ClipMenuItem, visible: Bool) {
    // any of our clip menu items with a keyEquivalentModifierMask set are alternatess,
    // they need special case for making hidden or visible
    if menuItem.keyEquivalentModifierMask.isEmpty {
      menuItem.isVisible = visible
    } else {
      menuItem.isVisibleAlternate = visible
    }
  }
  
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
    
    sanityCheckClipMenuItemIndex(index, forInserting: true)
    
    insertItem(newItem, at: index)
  }
  
  private func safeInsertItems(_ newItems: [NSMenuItem], at index: Int) {
    guard index <= items.count else {
      return
    }
    
    sanityCheckClipMenuItemIndex(index, forInserting: true)
    
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
    
    sanityCheckClipMenuItemIndex(index(of: deleteItem))
    
    removeItem(deleteItem)
  }
  
  private func safeRemoveItems(_ deleteItems: [NSMenuItem]) {
    for deleteItem in deleteItems {
      guard items.contains(deleteItem) else {
        return
      }
      
      sanityCheckClipMenuItemIndex(index(of: deleteItem))
      
      removeItem(deleteItem)
    }
  }
  
  private func safeRemoveItem(at index: Int) {
    guard index <= items.count else {
      return
    }
    
    sanityCheckClipMenuItemIndex(index)
    
    removeItem(at: index)
  }
  
  private func safeRemoveItems(at index: Int, count: Int) {
    guard count > 0 else {
      return
    }
    safeRemoveItems(at: index ..< index + count)
  }
  
  private func safeRemoveItems(at range: Range<Int>) {
    guard !range.isEmpty else {
      return
    }
    
    sanityCheckClipMenuItemIndex(range.lowerBound)
    sanityCheckClipMenuItemIndex(range.upperBound - 1)
    
    for index in range.reversed() {
      sanityCheckClipMenuItemIndex(index)
      
      removeItem(at: index)
    }
  }
  
  func saveMoveItems(at index: Int, count: Int, to destIndex: Int) {
    guard count > 0 && index != destIndex else {
      return
    }
    guard index >= 0 && index < items.count && destIndex >= 0 && destIndex < items.count else {
      return
    }
    
    sanityCheckClipMenuItemIndex(index)
    sanityCheckClipMenuItemIndex(index + count - 1)
    sanityCheckClipMenuItemIndex(destIndex, forInserting: true)
    
    if index < destIndex {
      guard destIndex >= index + count else {
        return // would be no change, see (*) below
      }
      for _ in 0 ..< count {
        guard let item = item(at: index) else { return } // shouldn't fail since we sanity checked above
        removeItem(item)
        insertItem(item, at: destIndex - 1)
        // -1 because removing before inserting shifts the index by 1
        //
        // a b c d e   "b c" @ 1 -> 4   remove   a c d e    add at   a c d b e   remove   a d b e    add again   a d b c e
        // 0 1 2 3 4   ie "a d b c e"   from 1   0 1 2 3 4   3=4-1   0 1 2 3 4   from 1   0 1 2 3 4   at 3=4-1   0 1 2 3 4
        //
        // note: "b c" @ 1 -> 2 obviously no change, but also 3:  a b c d e   a c d e   a c b d e   a b d e   a b c d e
        // (*) that's why this guard above skipping when idx < dest < idx+count
      }
    } else {
      for n in 0 ..< count {
        guard let item = item(at: index + n) else { return } // shouldn't fail since we sanity checked above
        removeItem(item)
        insertItem(item, at: destIndex + n)
        // more obvious counting when moving backwards (up), and no overlap problem
        // a b c d e   "c d" @ 2 -> 1   rmv fr  a b d e    add at   a c b d e   rmv fr  a c b e     add at   a c d b e
        // 0 1 2 3 4   ie "a c d b e"   2=2+0   0 1 2 3 4   1+0=1   0 1 2 3 4   3=2+1   0 1 2 3 4    1+1=2   0 1 2 3 4
      }
    }
  }
  
  func saveMoveItems(at range: Range<Int>, to destIndex: Int) {
    guard range.lowerBound < range.upperBound else {
      return
    }
    saveMoveItems(at: range.lowerBound, count: range.upperBound - range.lowerBound, to: destIndex)
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
  
  private func sanityCheckClipMenuItemIndex(_ i: Int, forInserting inserting: Bool = false) {
    guard let firstQueueIndex = firstQueueItemIndex, let postQueueIndex = postQueueItemIndex else {
      fatalError("cannot locate queue section")
    }
    guard let firstHistoryIndex = firstHistoryItemIndex, let postHistoryIndex = postHistoryItemIndex else {
      fatalError("cannot locate history section")
    }
    if item(at: i) == nil { // never called to add to very end of the menu, so no need to add `inserting==false`
      fatalError("menu index to be changed is out of bounds with respect to the entire menu")
    }
    if i < firstQueueIndex {
      fatalError("menu index to be changed preceeds the queue section")
    }
    if i > (inserting ? postQueueIndex : postQueueIndex - 1) && i < firstHistoryIndex {
      fatalError("menu index to be changed is inbetween queue and history sections")
    }
    if i > (inserting ? postHistoryIndex : postHistoryIndex - 1) {
      fatalError("menu index to be changed follows the history section")
    }
    // TODO: update for adding batch items
  }
  
  private func sanityCheckClipMenuItems() {
    guard let firstQueueIndex = firstQueueItemIndex, let postQueueIndex = postQueueItemIndex else {
      fatalError("cannot locate queue section")
    }
    guard let firstHistoryIndex = firstHistoryItemIndex, let postHistoryIndex = postHistoryItemIndex else {
      fatalError("cannot locate history section")
    }
    //guard let firstBatchIndex = firstBatchItemIndex, let postBatchIndex = postBatchesItemIndex else {
    //  fatalError("cannot locate batch section")
    //}
    for index in firstQueueIndex ..< postQueueIndex {
      sanityCheckClipMenuItem(at: index, forSectionStartingAt: firstQueueIndex)
    }
    for index in firstHistoryIndex ..< postHistoryIndex {
      sanityCheckClipMenuItem(at: index, forSectionStartingAt: firstQueueIndex)
    }
  }
  
  func sanityCheckClipMenuItem(at index: Int, forSectionStartingAt from: Int) {
    let suggestedCommandMap = #"map{($0.isHidden ?"H ":"  ") + ($0.isSeparatorItem ?"---":$0.title+($0 is ClipMenuItem ?"  VS  "+(($0 as! ClipMenuItem).clip?.title ?? "?"):""))}"#
    let suggestedCommand = "p items[\(from)...\(index)].\(suggestedCommandMap)"
    guard let item = item(at: index) as? ClipMenuItem else {
      fatalError("menu item at \(index) not a ClipMenuItem, try: \(suggestedCommand)")
    }
    guard let clip = item.clip else {
      fatalError("menu item at \(index) has a nil clip")
    }
    guard !clip.isFault else {
      //os_log(.debug, "menu item at %d has clip with isFault set, not sure its a problem? %@", index, item.title)
      return
    }
    guard let clipTitle = clip.title else {
      fatalError("menu item at \(index) has clip with a nil title")
    }
    guard clipTitle == item.title else {
      fatalError("menu item at \(index) has the wrong title, try: \(suggestedCommand)")
    }
  }
  
  // This used to be called in an `add` function, presumable when adding to the
  // menu while it's opened persistently like a window.
  // We might need to call it when deleting menu items because this is now the only
  //  situation that we're changing the menu items while the menu stats open.
  private func ensuringEventModeIsTrackIfVisible(dispatchLater: Bool = false, block: @escaping () -> Void) {
    lazy var inEventTrackingMode = RunLoop.current != RunLoop.main || RunLoop.current.currentMode != .eventTracking
    if isVisible && (dispatchLater || inEventTrackingMode) {
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
