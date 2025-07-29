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
//  Originally was a custom menu for supporting "search-as-you-type"
//  based on https://github.com/mikekazakov/MGKMenuWithFilter.
//  Now it's more controller than view, possibly a problem.
//

// swiftlint:disable file_length
import AppKit
import os.log

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
  private var useHistory = true
  private var useNaturalOrder = false
  private var useDirectMenu = false
  private var isFiltered = false
  private var isVisible = false
  
  private var promoteExtrasBadge: NSObject?
  private var queueHeadBadge: NSObject?
  private var cacheUndoCopyItemShortcut = ""
  private var historyHeaderView: FilterFieldView? { filterFieldItem?.view as? FilterFieldView }
  private var filterFieldViewCache: FilterFieldView?
  private var menuWindow: NSWindow? { NSApp.menuWindow }
  
  #if DELETE_MENUITEM_DETECTS_ITS_SHORTCUT
  private var disableDeleteTimer: DispatchSourceTimer?
  private var lastHighlightedClipItem: ClipMenuItem?
  #endif
  
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
  @IBOutlet weak var queueHeadingItem: NSMenuItem?
  @IBOutlet weak var historyHeadingItem: NSMenuItem?
  @IBOutlet weak var batchesHeadingItem: NSMenuItem?
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
      fatalError("menu resource file missing")
    }
    var nibObjects: NSArray? = []
    guard nib.instantiate(withOwner: owner, topLevelObjects: &nibObjects),
          let menu = nibObjects?.compactMap({ $0 as? Self }).first else {
      fatalError("menu resources missing.")
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
    noteItem?.title = ""
    filterFieldItem?.title = ""
    keyDetectorItem?.title = ""
    queueHeadingItem?.title = ""
    historyHeadingItem?.title = ""
    batchesHeadingItem?.title = ""
    
    if usePopoverAnchors {
      insertTopAnchorItems()
    }
    preQueueItem = topQueueAnchorItem ?? queueHeadingItem ?? leadingSeparatorItem
    preHistoryItem = topHistoryAnchorItem ?? keyDetectorItem
    preBatchesItem = batchesHeadingItem ?? postHistorySeparatorItem
    
    addDebugItems()
  }
  
  func prepareForPopup() {
    // used when menu opens via MenuController & ProxyMenu
    updateStaticItemShortcuts()
    updateMenuItemStates()
  }
  
  func menuBarShouldOpen() -> Bool {
    // used when menu opens directly from the MenuBarIcon, not MenuController & ProxyMenu
    guard let event = NSApp.currentEvent else {
      os_log(.debug, "NSApp.currentEvent is nil when intercepting statusbaritem click, just letting menu open")
      updateStaticItemShortcuts()
      updateMenuItemStates()
      return true
    }
    
    let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    #if DEBUG
    // testing affordance
    if AppDelegate.shouldFakeAppInteraction && modifierFlags.contains(.capsLock) {
      putPasteRecordOnClipboard()
      return false
    }
    #endif
    
    // control-option-click to toggle saving clipboard items to history
    // control-option-shift-click to set skip saving only the next clipboard item
    if useHistory || queue.isOn {
      if modifierFlags.contains(.control) && modifierFlags.contains(.option) {
        UserDefaults.standard.ignoreEvents = !UserDefaults.standard.ignoreEvents
        
        if !modifierFlags.contains(.shift) && UserDefaults.standard.ignoreEvents {
          UserDefaults.standard.ignoreOnlyNextEvent = true
        }
        return false
      }
    }
    
    // control-click or right-click to toggle queue mode on
    if !AppModel.busy {
      if modifierFlags.contains(.control) && !modifierFlags.contains(.option) {
        performQueueModeToggle()
        return false
      }
      if modifierFlags.isEmpty && (event.type == .rightMouseDown || event.type == .rightMouseUp) {
        performQueueModeToggle()
        return false
      }
    }
    
    // option-click open expanded menu that includes history items
    if modifierFlags.contains(.option) && useHistory && AppModel.allowExpandedHistory && historyItemCount > 0 {
      showsExpandedMenu = true
      showsFullExpansion = modifierFlags.contains(.shift)
    } else {
      showsExpandedMenu = false
    }
    
    prepareForPopup()
    return true
  }
  
  #if DEBUG
  func putPasteRecordOnClipboard() {
    queue.putPasteRecordOnClipboard()
  }
  #endif
  
  func menuWillOpen(_ menu: NSMenu) {
    isVisible = true
    
    if !useDirectMenu {
      // potentially revert expanded mode flag initially set from an option-click on the menu icon
      if showsExpandedMenu && (!useHistory || !AppModel.allowExpandedHistory || historyItemCount == 0) {
        showsExpandedMenu = false
      }
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
    
    #if DELETE_MENUITEM_DETECTS_ITS_SHORTCUT
    // forget the outstanding deferred disable of the delete item
    disableDeleteTimer?.cancel()
    disableDeleteTimer = nil
    #endif
    
    if let clipItem = item as? ClipMenuItem {
      deleteItem?.isEnabled = !AppModel.busy
      #if DELETE_MENUITEM_DETECTS_ITS_SHORTCUT
      lastHighlightedClipItem = clipItem
      #endif
      
      previewController.showPopover(for: clipItem, anchors: clipItemAnchors(for: clipItem))
    } else {
    
      #if DELETE_MENUITEM_DETECTS_ITS_SHORTCUT
      // used to do this when command-delete was being left to be picked by AppKit
      // as a shortcut for the `deleteItem`, now that we intercept this keypress
      // directly this isn't needed
      if item == nil || item == deleteItem {
        // called with nil when cursor is over a disabled item, a separator, or is
        // away from any menu items
        // when cmd-delete hit, this is first called with nil and then with the
        // delete menu item itself, for both of these we must not (immediately) disable
        // the delete menu or unset lastHighlightedItem or else deleting won't work
        disableDeleteTimer = DispatchSource.scheduledTimerForRunningOnMainQueue(afterDelay: 0.5) { [weak self] in
          self?.deleteItem?.isEnabled = false
          //self?.lastHighlightedClipItem = nil
          self?.disableDeleteTimer = nil
        }
        return
      }
      #endif
      
      deleteItem?.isEnabled = false
      #if DELETE_MENUITEM_DETECTS_ITS_SHORTCUT
      lastHighlightedClipItem = nil
      #endif
    }
  }
  
  // MARK: - build dynamic clip menu items
  
  private func insertTopAnchorItems() {
    // Anchor items are used in older versions of the OS as nearly empty items containing views
    // who's view frames are used to as bounds for mouse tracking to open the preview popups.
    // Menu item groups for each clip include a trailing anchor item, one preceding all queue items
    // and history items are needed to as the leading fencepost IYKWIM
    guard let protoAnchorItem = protoAnchorItem,
          let preQueueIndex = safeIndex(of: queueHeadingItem ?? leadingSeparatorItem),
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
    
    useHistory = UserDefaults.standard.keepHistory
    useNaturalOrder = !useHistory // TODO: maybe add UserDefaults.standard.naturalOrder
    
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
    let queueClips = clips.prefix(queue.size)
    if useNaturalOrder {
      for clip in queueClips.reversed() {
        let menuItems = buildHistoryItemAlternates(clip)
        safeInsertItems(menuItems, at: queueInsertIndex)
        queueInsertIndex += menuItems.count
      }
    } else {
      for clip in queueClips {
        let menuItems = buildHistoryItemAlternates(clip)
        safeInsertItems(menuItems, at: queueInsertIndex)
        queueInsertIndex += menuItems.count
      }
    }
    
    if useHistory {
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
//    guard let fromIndex = firstBatchItemIndex, let toIndex = postBatchesItemIndex else {
//      return
//    }
//    
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
    let useHistory = UserDefaults.standard.keepHistory
    let haveQueueItems = !queue.isEmpty
    let haveHistoryItems = showsExpandedMenu // never set when historyItemCount == 0 or keepHistory false
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
    
    // Delete & clear item visibility
    deleteItem?.isVisible = haveQueueItems || haveHistoryItems || haveBatchItems
    clearItem?.isVisible = useHistory && (haveQueueItems || haveHistoryItems) // always hide if history off, even if a queue   
  }
  
  private func updateDynamicClipItemVisibility() {
    // visibility of each of the 3 sections of clip items, plus their titles and trailing separators
    let showQueueSection = !queue.isEmpty 
    let showHistorySection = showsExpandedMenu
    let showBatchSection = showsSavedBatches && batchItemCount > 0
    
    // Queue section
    if let first = firstQueueItemIndex, let end = postQueueItemIndex, first <= end {
      if !showQueueSection && first != end {
        fatalError("queue is empty but there still exists some queue menu items")
      }
      for index in first ..< end {
        setClipItemVisibility(at: index, visible: showQueueSection, badgeless: true)
      }
      
      // badge the last item, which is the head of the queue 
      if first < end, #available(macOS 14, *) {
        if queueHeadBadge == nil {
          queueHeadBadge = NSMenuItemBadge(string: NSLocalizedString("first_replay_item_badge", comment: ""))
        }
        
        if useNaturalOrder, let firstQueueItem = safeItem(at: first) {
          firstQueueItem.badge = queueHeadBadge as? NSMenuItemBadge
        } else if let lastQueueItem = safeItem(at: end - historyItemGroupCount) {
          lastQueueItem.badge = queueHeadBadge as? NSMenuItemBadge
        }
      }
      
      queueHeadingItem?.isVisible = showQueueSection
      postQueueSeparatorItem?.isVisible = showQueueSection
    } else {
      fatalError("can't locate the queue menu items section")
    }
    
    // History section, starting with the filter field
    if useHistory {
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
          setClipItemVisibility(at: index, visible: showHistorySection && index < endVisible, badgeless: true)
        }
        
        historyHeadingItem?.isVisible = showHistorySection
        postHistorySeparatorItem?.isVisible = showHistorySection
        
      } else {
        fatalError("can't locate the history menu items section")
      }
    } else {
      historyHeadingItem?.isVisible = false
      postHistorySeparatorItem?.isVisible = false
    }
    
    // Batches section
    if let first = firstBatchItemIndex, let end = postBatchesItemIndex, first <= end {
      for index in first ..< end {
        setClipItemVisibility(at: index, visible: showBatchSection)
      }
      
      batchesHeadingItem?.isVisible = showBatchSection
      postBatchesSeparatorItem?.isVisible = showBatchSection
    } else {
      fatalError("can't locate the batches menu items section")
    }
  }
  
  private func trimClipMenuItems() {
    // remove history menu items bottom up to sync with history storage which
    // may have trimmed off the end of its clips to keep within the maximum allowed
    guard useHistory else {
      return
    }
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
  }
  
  // MARK: - more public functions
  
  func highlightedClipMenuItem() -> ClipMenuItem? {
    return highlightedClipItem()
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
  
  // MARK: - public functions to sync menu to model changes
  // Whem some of these functions called, global state such as the history and queue
  // are likely to have already been changed and so calling them should be avoided
  // in most cases.
  
  func addedClipToQueue(_ clip: Clip) {
    let index: Int
    if useNaturalOrder {
      guard let postIndex = postQueueItemIndex else {
        fatalError("can't locate the queue menu items section")
      }
      index = postIndex
    } else {
      guard let firstIndex = firstQueueItemIndex else {
        fatalError("can't locate the queue menu items section")
      }
      index = firstIndex
    }
    
    let menuItems = buildHistoryItemAlternates(clip)
    safeInsertItems(menuItems, at: index)
    
    trimClipMenuItems()
    
    sanityCheckClipMenuItems()
  }
  
  func addedClipToHistory(_ clip: Clip) {
    guard !useHistory else {
      os_log(.debug, "didn't expect to add history menu item when history disabled")
      return
    }
    if useNaturalOrder {
      os_log(.debug, "didn't expect to add history menu item when using natural order")
    }
    guard queueItemCount == 0 else {
      os_log(.debug, "didn't expect to add history menu item when queue not empty")
      sanityCheckClipMenuItems()
      return
    }
    guard let index = firstHistoryItemIndex else {
      fatalError("can't locate the queue menu items section")
    }
    
    let menuItems = buildHistoryItemAlternates(clip)
    safeInsertItems(menuItems, at:index)
    
    trimClipMenuItems()
    
    sanityCheckClipMenuItems()
  }
  
  func pushedClipsOnQueue(_ count: Int) {
    guard !useHistory else {
      os_log(.debug, "didn't expect to move history menu items to the queue section when history disabled")
      return
    }
    guard count <= historyClipsCount else {
      os_log(.debug, "didn't expect to move %d history menu items to the queue section when only %d exist",
             count, historyClipsCount)
      sanityCheckClipMenuItems()
      return
    }
    guard let queueDestIndex = postQueueItemIndex, let historySrcIndex = firstHistoryItemIndex,
          let postHistoryIndex = postHistoryItemIndex else {
      fatalError("can't locate the queue and history menu items sections")
    }
    guard postHistoryIndex > historySrcIndex else {
      fatalError("called to move from first in history to end of queue sections but history empty, \(historySrcIndex)..<\(postHistoryIndex)")
    }
    
    saveMoveItems(at: historySrcIndex, count: count * historyItemGroupCount, to: queueDestIndex)
    
    sanityCheckClipMenuItems()
  }
  
  func poppedClipsOffQueue(_ count: Int) {
    guard count > 0 else {
      return
    }
    guard count <= queueClipsCount else {
      os_log(.debug, "didn't expect to pop %d queue menu items out of that section when only %d exist",
             count, queueClipsCount)
      sanityCheckClipMenuItems()
      return
    }
    
    if !useHistory && useNaturalOrder {
      guard let firstQueueIndex = firstQueueItemIndex else {
        fatalError("can't locate the queue menu items section")
      }
      
      safeRemoveItems(at: firstQueueIndex, count: count * historyItemGroupCount)
      
    } else if !useHistory && !useNaturalOrder {
      guard let postQueueIndex = postQueueItemIndex else {
        fatalError("can't locate the queue menu items section")
      }
      
      safeRemoveItems(at: postQueueIndex - count * historyItemGroupCount, count: count * historyItemGroupCount)
      
    } else {
      guard let postQueueIndex = postQueueItemIndex, let firstHistoryIndex = firstHistoryItemIndex else {
        fatalError("can't locate the queue and history menu items sections")
      }
      
      saveMoveItems(at: postQueueIndex - count * historyItemGroupCount, count: count * historyItemGroupCount, to: firstHistoryIndex) 
    }
    
    sanityCheckClipMenuItems()
  }
  
  func poppedClipOffQueue() {
    poppedClipsOffQueue(1)
  }
  
  func cancelledQueue(_ count: Int) {
    poppedClipsOffQueue(count)
  }
  
  func startedQueueFromHistory(_ headHistoryPosition: Int) {
    guard !useHistory else {
      os_log(.debug, "didn't expect to start queue from history menu items when history disabled")
      return
    }
    guard queueItemCount == 0 else {
      os_log(.debug, "didn't expect to start queue from history menu items when queue not currently empty")
      sanityCheckClipMenuItems()
      return
    }
    
    // since queue is empty, `positon` is relative to the history clips
    // and so the number of the clip up to and including it is that index plus 1 
    pushedClipsOnQueue(headHistoryPosition + 1)
    
    sanityCheckClipMenuItems()
  }
  
  // of these sync functions only the 2 deletedClip ones need to take care with the 
  // highlighed item, because only when deleting does the menu stay open afterwards
  // (also likewise needs to update item visiblity if the last item in its section
  // is the one deleted, to avoid leaving an unwanted separator menu item showing)
  
  func deletedClipFromQueue(_ queuePosition: Int) {
    let clipsCount = queueClipsCount
    guard queuePosition >= 0 && queuePosition < clipsCount else {
      os_log(.debug, "didn't expect queue index %d to exceed range of queue menu items, 0..<%d", queuePosition, clipsCount)
      sanityCheckClipMenuItems()
      return
    }
    guard let firstQueueIndex = firstQueueItemIndex else {
      fatalError("can't locate the queue menu items section")
    }
    
    let menuOrderPosition = useNaturalOrder ? clipsCount - queuePosition - 1 : queuePosition
    let index = firstQueueIndex + menuOrderPosition * historyItemGroupCount
    guard let clipMenuItem = safeItem(at: index) as? ClipMenuItem else {
      fatalError("can't get menu item for queue index \(queuePosition) at menu index \(index)")
    }
    
    let wasLastInSection = menuOrderPosition == clipsCount - 1 // lowest in the menu
    let wasHighlighed = clipMenuItem == highlightedClipMenuItem()
    
    safeRemoveItems(at: index, count: historyItemGroupCount)
    
    if wasHighlighed {
      if queueItemCount == 0 {
        updateMenuItemStates() // transform many manu item to account for queue now empty
        
        highlight(nil)
      } else if !wasLastInSection { 
        if let item = safeItem(at: index) {
          highlight(item)
        }
      } else if menuOrderPosition > 0 && wasLastInSection {
        // after deleting the selected last queued item, highlight the previous item,
        // the new last one in the queue
        if let item = safeItem(at: firstQueueIndex + (menuOrderPosition - 1) * historyItemGroupCount) {
          highlight(item)
        }
      }
    }
    
    sanityCheckClipMenuItems()
  }
  
  func deletedClipFromHistory(_ historyPosition: Int) {
    guard historyPosition >= 0 && historyPosition < historyClipsCount else {
      os_log(.debug, "didn't expect history index %d to exceed range of history menu items, 0..<%d", historyPosition, historyClipsCount)
      sanityCheckClipMenuItems()
      return
    }
    guard let firstHistoryIndex = firstHistoryItemIndex else {
      fatalError("can't locate the history menu items section")
    }
    
    let index = firstHistoryIndex + historyPosition * historyItemGroupCount
    guard let clipMenuItem = safeItem(at: index) as? ClipMenuItem else {
      fatalError("can't get menu item for history index \(historyPosition) at menu index \(index)")
    }
    
    let expectedNumVisibleHistoryClips =
      max((showsFullExpansion ? AppModel.effectiveMaxClips : AppModel.effectiveMaxVisibleClips) - queue.size, 0)
    let wasLastInSection = historyPosition == expectedNumVisibleHistoryClips - 1
    let wasHighlighed = clipMenuItem == highlightedClipMenuItem()
    
    safeRemoveItems(at: index, count: historyItemGroupCount)
    
    if wasHighlighed {
      if historyItemCount == 0 {
        updateDynamicClipItemVisibility() // removes the now unwanted separator 
        
        highlight(nil)
      } else if !wasLastInSection { 
        // after deleting the selected last history item, normally highlight the next item
        if let item = safeItem(at: index) {
          highlight(item)
        }
      } else if historyPosition > 0 && wasLastInSection {
        // after deleting the selected last history item, next highlight the previous item,
        // the new last one in history
        // TODO: maybe sanity check that the expected number of history clips are visible
        if let item = safeItem(at: firstHistoryIndex + (historyPosition - 1) * historyItemGroupCount) {
          highlight(item)
        }
      }
    }
    
    sanityCheckClipMenuItems()
  }
  
  func deletedHistory() {
    // means queue and history
    guard let firstHistoryIndex = firstHistoryItemIndex, let postHistoryIndex = postHistoryItemIndex,
          let firstQueueIndex = firstQueueItemIndex, let postQueueIndex = postQueueItemIndex else {
      fatalError("can't locate the queue and history menu items sections")
    }
    
    safeRemoveItems(at: firstHistoryIndex ..< postHistoryIndex)
    safeRemoveItems(at: firstQueueIndex ..< postQueueIndex)
    
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
          setClipItemVisibility(at: index, visible: found)
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
  
  // MARK: - highlighted menu item complications
  
  private func highlightedClipItem() -> ClipMenuItem? {
    #if DELETE_MENUITEM_DETECTS_ITS_SHORTCUT
    guard let item = lastHighlightedClipItem as? ClipMenuItem else {
      return nil
    }
    #else
    guard let item = highlightedItem as? ClipMenuItem else {
      return nil
    }
    #endif
    
    // When deleting mulitple items by holding the removal keys
    // we sometimes get into a race condition with menu updating indices.
    // https://github.com/p0deje/Maccy/issues/628
    guard index(of: item) >= 0 else {
      return nil
    }
    
    return item
  }
  
  private func highlightNext(_ menuItems: [NSMenuItem]) -> Bool {
    let highlightableItems = self.highlightableItems(menuItems)
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
  
  private func highlightableItems(_ menuItems: [NSMenuItem]) -> [NSMenuItem] {
    return menuItems.filter {
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
    // We need to first highlight a menu item somewhere near the top of the menu to
    // force menu redrawing (was using the search menu item, but its now sometimes gone)
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
  // In these functions `index` means menu item index
  
  private func setClipItemVisibility(at index: Int, visible: Bool, badgeless: Bool = false) {
    guard let menuItem = item(at: index) as? ClipMenuItem else {
      return
    }
    
    setClipItemVisibility(menuItem, visible: visible)
    
    if badgeless, #available(macOS 14, *) {
      menuItem.badge = nil
    }
  }
  
  private func setClipItemVisibility(_ menuItem: ClipMenuItem, visible: Bool) {
    // any of our clip menu items with a keyEquivalentModifierMask set are alternatess,
    // they need special case for making hidden or visible
    if menuItem.keyEquivalentModifierMask.isEmpty {
      menuItem.isVisible = visible
    } else {
      menuItem.isVisibleAlternate = visible
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
    guard clipTitle == item.title || (clipTitle == "" && item.title == " ") else {
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
    #if DEBUG && false
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

// An isVisible property makes logic more clear than with the isHidden property,
// eliminating many double negatives
// `isVisibleAlternate` is for making an alternate menu items visible, it isolates
// some differences between macOS 14 and earlier
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
