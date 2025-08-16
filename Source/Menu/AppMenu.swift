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
import KeyboardShortcuts
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
  private var historyItemGroupCount: Int { usePopoverAnchors ? 3 : 2 } // an optional anchor, keep in sync with buildHistoryItemAndAlternates
  private var batchItemGroupCount: Int { usePopoverAnchors ? 2 : 1 } // an optional anchor, keep in sync with buildHistoryItemAndAlternates
  
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
  private var queueItemsNeedsRebuild = false
  private var historyItemsNeedsRebuild = false
  
  private var cacheUndoCopyItemShortcut = ""
  private var filterFieldView: FilterFieldView? { filterFieldItem?.view as? FilterFieldView }
  private var filterFieldViewCache: FilterFieldView?
  lazy private var promoteExtrasBadge: NSObject? = if #available(macOS 14, *) {
    NSMenuItemBadge(string: NSLocalizedString("promote_extras_menu_badge", comment: "")) } else { nil }
  lazy private var queueHeadBadge: NSObject? = if #available(macOS 14, *) {
    NSMenuItemBadge(string: NSLocalizedString("first_replay_item_badge", comment: "")) } else { nil }
  
  #if DELETE_MENUITEM_DETECTS_ITS_SHORTCUT
  // keep this code around for now, however KeyDetectorView seems to work better
  private var disableDeleteTimer: DispatchSourceTimer?
  private var lastHighlightedClipItem: ClipMenuItem?
  #endif
  
  private var previewPopover: NSPopover?
  private var protoCopyItem: ClipMenuItem?
  private var protoReplayItem: ClipMenuItem?
  private var protoAnchorItem: NSMenuItem?
  private var protoBatchItem: BatchMenuItem?
  
  private var topQueueAnchorItem: NSMenuItem?
  private var preQueueItem: NSMenuItem?
  private var postQueueItem: NSMenuItem? { postQueueSeparatorItem }
  private var firstQueueItem: NSMenuItem? { safeItem(at: firstQueueItemIndex) } // result might be postQueueSeparatorItem
  private var firstQueueItemIndex: Int? { safeIndex(of: preQueueItem)?.advanced(by: 1) }
  private var postQueueItemIndex: Int? { safeIndex(of: postQueueItem) }
  private var queueClipsCount: Int { queueItemCount / batchItemGroupCount }
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
  @IBOutlet weak var replayLastBatchItem: NSMenuItem?
  @IBOutlet weak var saveLastBatchItem: NSMenuItem?
  @IBOutlet weak var saveCurrentBatchItem: NSMenuItem?
  @IBOutlet weak var noteItem: NSMenuItem?
  @IBOutlet weak var queueHeadingItem: NSMenuItem?
  @IBOutlet weak var historyHeadingItem: NSMenuItem?
  @IBOutlet weak var batchesHeadingItem: NSMenuItem?
  @IBOutlet weak var prototypeCopyItem: NSMenuItem?
  @IBOutlet weak var prototypeReplayItem: NSMenuItem?
  @IBOutlet weak var prototypeAnchorItem: NSMenuItem?
  @IBOutlet weak var prototypeBatchItem: NSMenuItem?
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
    
    #if DEBUG
    menu.addDebugItems()
    #endif
    
    return menu
  }
  
  override func awakeFromNib() {
    // Runs during nib instantiation and before self.history & self.queue set in `load` above. 
    // Any setup that depend on those should be in buildDynamicItems or menuWillOpen
    
    self.delegate = self
    self.autoenablesItems = false
    
    self.minimumWidth = CGFloat(Self.menuWidth)
    
    BatchMenuItem.itemGroupCount = batchItemGroupCount
    
    // save aside the anchor prototype and insert into the menu if needed
    if let prototypeAnchorItem = prototypeAnchorItem {
      protoAnchorItem = prototypeAnchorItem
      removeItem(prototypeAnchorItem)
      protoAnchorItem?.title = ""
    }
    if usePopoverAnchors {
      insertTopAnchorItems()
    }
    
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
    // removing the prototype batch item must be *after* calling insertTopAnchorItems
    // because it inserts into the batch item's submenu 
    if let prototypeBatchItem = prototypeBatchItem as? BatchMenuItem {
      protoBatchItem = prototypeBatchItem
      removeItem(prototypeBatchItem)
      protoBatchItem?.title = ""
      protoBatchItem?.submenu?.delegate = self
    }
    
    preQueueItem = topQueueAnchorItem ?? queueHeadingItem
    preHistoryItem = topHistoryAnchorItem ?? filterFieldItem
    preBatchesItem = batchesHeadingItem
    
    // strip these placeholder item titles, they're only to identify them in interface builder
    // contents of most of these are an embedded view instead
    noteItem?.title = ""
    filterFieldItem?.title = ""
    keyDetectorItem?.title = ""
    queueHeadingItem?.title = ""
    historyHeadingItem?.title = ""
    batchesHeadingItem?.title = ""
  }
  
  func prepareForPopup() {
    // used when menu opens via MenuController & ProxyMenu
    // what was done here now moved to menuWillOpen 
  }
  
  func menuBarShouldOpen() -> Bool {
    // used when menu opens directly from the MenuBarIcon, not MenuController & ProxyMenu
    guard let event = NSApp.currentEvent else {
      os_log(.debug, "NSApp.currentEvent is nil when intercepting statusbaritem click, just letting menu open")
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
    
    return true
  }
  
  #if DEBUG
  func putPasteRecordOnClipboard() {
    queue.putPasteRecordOnClipboard()
  }
  #endif
  
  func menuWillOpen(_ menu: NSMenu) {
    guard menu === self else {
      return // ignore batch submenus opening
    }
    
    isVisible = true
    
    prepareToOpen()
    previewController.menuWillOpen()
  }
  
  func prepareToOpen() {
    // flags useHistory & useNaturalOrder are less ephemeral than flags set below, set in buildDynamicItems
    // other flags showsExpandedMenu & showsFullExpansion are already set in menuBarShouldOpen
    
    if showsExpandedMenu && AppModel.allowHistorySearch && !UserDefaults.standard.hideSearch,
       let field = filterFieldView?.queryField
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
    
    updateStaticItemShortcuts()
    updateMenuItemStates()
  }
  
  func menuDidClose(_ menu: NSMenu) {
    isVisible = false
    showsExpandedMenu = false
    
    isFiltered = false
    if showsFilterField {
      // not sure why this is in a dispatch to the main thread, some timing thing i'm guessing
      DispatchQueue.main.async { 
        self.filterFieldView?.setQuery("", throttle: false)
        self.filterFieldView?.queryField.refusesFirstResponder = true
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
      
    } else if let clipItem = item as? BatchMenuItem {
      deleteItem?.isEnabled = !AppModel.busy
      
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
  
  func buildDynamicItems() {
    useHistory = UserDefaults.standard.keepHistory
    useNaturalOrder = !useHistory // TODO: maybe add UserDefaults.standard.naturalOrder
    
    rebuildQueueItems()
    rebuildHistoryItems()
    rebuildBatchItems()
  }
  
  private func insertTopAnchorItems() {
    // Anchor items are used in older versions of the OS as nearly empty items containing views
    // who's view frames are used to as bounds for mouse tracking to open the preview popups.
    // Menu item groups for each clip include a trailing anchor item, one preceding all queue items
    // and history items are needed to as the leading fencepost IYKWIM
    guard let protoAnchorItem = protoAnchorItem,
          let preQueueIndex = safeIndex(of: queueHeadingItem),
          let preHistoryIndex = safeIndex(of: filterFieldItem) else {
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
    
    guard let batchItem = prototypeBatchItem, let batchItemSubmenu = batchItem.menu,
          let topBatchAnchorItem = protoAnchorItem.copy() as? NSMenuItem else {
      return
    }
    batchItemSubmenu.insertItem(topBatchAnchorItem, at: batchItemSubmenu.numberOfItems) 
  }
  
  private func rebuildNecessaryDynamicItemsInBackground() {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return}
      if queueItemsNeedsRebuild {
        rebuildQueueItems()
        queueItemsNeedsRebuild = false
      }
      if historyItemsNeedsRebuild {
        rebuildHistoryItems()
        historyItemsNeedsRebuild = false
      }
    }
  }
  
  private func rebuildQueueItems() {
    clearQueueItems()
    buildQueueItems()
  }
  
  private func buildQueueItems() {
    guard var queueInsertIndex = postQueueItemIndex else {
      fatalError("can't find the place to insert queue menu items")
    }
    
    if useNaturalOrder {
      for clip in queue.clips.reversed() {
        let menuItems = buildBatchItemAndAlternates(forClip: clip)
        safeInsertClipItems(menuItems, at: queueInsertIndex)
        queueInsertIndex += menuItems.count
      }
    } else {
      for clip in queue.clips {
        let menuItems = buildBatchItemAndAlternates(forClip: clip)
        safeInsertClipItems(menuItems, at: queueInsertIndex)
        queueInsertIndex += menuItems.count
      }
    }
  }
  
  private func rebuildHistoryItems() {
    clearHistoryItems()
    buildHistoryItems()
  }
  
  private func buildHistoryItems() {
    if !useHistory {
      return
    }
    
    guard var historyInsertIndex = postHistoryItemIndex else {
      fatalError("can't find the place to insert history menu items")
    }
    
    let historyClips = Array(history.all.prefix(AppModel.effectiveMaxClips))
    
    for clip in historyClips {
      let menuItems = buildHistoryItemAndAlternates(forClip: clip)
      safeInsertClipItems(menuItems, at: historyInsertIndex)
      historyInsertIndex += menuItems.count
    }
  }
  
  private func rebuildBatchItems() {
    clearBatchItems()
    buildBatchItems()
  }
  
  private func buildBatchItems() {
    guard var batchInsertIndex = postBatchesItemIndex else {
      fatalError("can't find the place to insert batch menu items")
    }
    
    for batch in history.batches {
      guard let menuItem = buildBatchParentItem(forBatch: batch) else { continue }
      
      addBatchSubmenuItems(forParentItem: menuItem, fromClips: batch.getClipsArray())
      safeInsertBatchItem(menuItem, at: batchInsertIndex)
      
      batchInsertIndex += 1
    }
  }
  
  private func buildHistoryItemAndAlternates(forClip clip: Clip) -> [NSMenuItem] {
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
  
  private func buildBatchItemAndAlternates(forClip clip: Clip) -> [NSMenuItem] {
    guard let protoCopyItem = protoCopyItem, let protoAnchorItem = protoAnchorItem else {
      return []
    }
    
    let menuItems: [NSMenuItem]
    if !usePopoverAnchors {
      menuItems = [
        (protoCopyItem.copy() as! ClipMenuItem).configured(withClip: clip, num: 1, of: 1),
      ]
    } else {
      menuItems = [
        (protoCopyItem.copy() as! ClipMenuItem).configured(withClip: clip, num: 1, of: 2),
        (protoAnchorItem.copy() as! NSMenuItem)
      ]
    }
    
    assert(menuItems.count == batchItemGroupCount)
    
    return menuItems
  }
  
  private func buildBatchParentItem(forBatch batch: Batch) -> NSMenuItem? {
    guard let protoParentItem = protoBatchItem else {
      return nil
    }
    
    let batchParentItem = (protoParentItem.copy() as! BatchMenuItem).configured(withBatch: batch)
    
    return batchParentItem
  }
  
  private func addBatchSubmenuItems(forParentItem parentBatchItem: NSMenuItem, fromClips clips: [Clip]) {
    guard let batchMenuItem = parentBatchItem as? BatchMenuItem, let submenu = batchMenuItem.submenu else {
      return
    }
    
    if useNaturalOrder {
      for clip in clips.reversed() {
        let menuItems = buildBatchItemAndAlternates(forClip: clip)
        menuItems.forEach {
          submenu.insertItem($0, at: submenu.numberOfItems)
        }
      }
    } else {
      for clip in clips {
        let menuItems = buildBatchItemAndAlternates(forClip: clip)
        menuItems.forEach {
          submenu.insertItem($0, at: submenu.numberOfItems)
        }
      }
    }
    
    // badge the head item right away instead of dynamically just before showing the menu
    // bceause these menu items as more static than the queue items are
    if clips.count > 0, let firstClipIndex = batchMenuItem.firstClipItemIndex, let postClipIndex = batchMenuItem.postClipItemIndex,
       #available(macOS 14, *)
    {
      let headItemGroup = useNaturalOrder ? firstClipIndex : postClipIndex - batchItemGroupCount
      for cnt in 0 ..< batchItemGroupCount {
        if headItemGroup + cnt < submenu.numberOfItems, let headItem = submenu.item(at: headItemGroup + cnt), headItem.isEnabled {
          headItem.badge = queueHeadBadge as? NSMenuItemBadge
        }
      }
    }
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
    guard let firstQueueIndex = firstQueueItemIndex, let postQueueIndex = postQueueItemIndex,
          firstQueueIndex <= postQueueIndex else {
      fatalError("can't locate the queue menu items section")
    }
    safeRemoveClipItems(at: firstQueueIndex ..< postQueueIndex)
  }
  
  private func clearHistoryItems() {
    guard let firstHistoryIndex = firstHistoryItemIndex, let postHistoryIndex = postHistoryItemIndex,
        firstHistoryIndex <= postHistoryIndex else { 
      fatalError("can't locate the history menu items section")
    }
    safeRemoveClipItems(at: firstHistoryIndex ..< postHistoryIndex)
  }
  
  private func clearBatchItems() {
    guard let firstBatchIndex = firstBatchItemIndex, let postBatchesIndex = postBatchesItemIndex,
          firstBatchIndex <= postBatchesIndex else {
      fatalError("can't locate the batch menu items section")
    }
    safeRemoveBatchItems(at: firstBatchIndex ..< postBatchesIndex) // note: these items are roots of submenus
  }

  func iterateOverClipMenuItems(_ closure: (ClipMenuItem)->Void) {
    iterateOverQueueClipMenuItems(closure)
    iterateOverHistoryClipMenuItems(closure)
    iterateOverBatchClipMenuItems(closure)
  }
  
  func iterateOverQueueClipMenuItems<T>(_ closure: (ClipMenuItem)->T) {
    guard let firstQueueIndex = firstQueueItemIndex, let postQueueIndex = postQueueItemIndex,
          firstQueueIndex <= postQueueIndex else {
      fatalError("can't locate the queue menu items section")
    }
    for index in firstQueueIndex ..< postQueueIndex {
      if let menuItem = item(at: index) as? ClipMenuItem {
        let r = closure(menuItem)
        if r as? Bool == false {
          return
        }
      }
    }
  }
  
  func iterateOverHistoryClipMenuItems<T>(_ closure: (ClipMenuItem)->T) {
    guard let firstHistoryIndex = firstHistoryItemIndex, let postHistoryIndex = postHistoryItemIndex,
        firstHistoryIndex <= postHistoryIndex else { 
      fatalError("can't locate the history menu items section")
    }
    for index in firstHistoryIndex ..< postHistoryIndex {
      if let menuItem = item(at: index) as? ClipMenuItem {
        let r = closure(menuItem)
        if r as? Bool == false {
          return
        }
      }
    }
  }
  
  func iterateOverBatchClipMenuItems<T>(_ closure: (ClipMenuItem)->T) {
    guard let firstHistoryIndex = firstHistoryItemIndex, let postHistoryIndex = postHistoryItemIndex,
        firstHistoryIndex <= postHistoryIndex else { 
      fatalError("can't locate the history menu items section")
    }
    for index in firstHistoryIndex ..< postHistoryIndex {
      if let menuItem = item(at: index) as? BatchMenuItem,
         let firstClipIndex = menuItem.firstClipItemIndex, let postClipIndex = menuItem.postClipItemIndex
      {
        for index in firstClipIndex ..< postClipIndex {
          if let submenuItem = menuItem.submenu?.item(at: index) as? ClipMenuItem {
            let r = closure(submenuItem)
            if r as? Bool == false {
              return
            }
          }
        }
      }
    }
  }
  
  func iterateOverBatchParentItems<T>(_ closure: (BatchMenuItem)->T) {
    guard let firstBatchIndex = firstBatchItemIndex, let postBatchesIndex = postBatchesItemIndex,
          firstBatchIndex <= postBatchesIndex else {
      fatalError("can't locate the batch menu items section")
    }
    for index in firstBatchIndex ..< postBatchesIndex {
      if let menuItem = item(at: index) as? BatchMenuItem {
        let r = closure(menuItem)
        if r as? Bool == false {
          return
        }
        // wanted to also exit if T is any Optional equalling .none
        // this compiles but doesn't work: `if case .none = r as Optional<Any>`
      }
    }
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
      replayLastBatchItem?.setShortcut(for: .queueReplay)
      
      // instead of a start hotkey, might instead want a start/stop toggle hotkey, something like:
      //if !queue.isOn {
      //  queueStartItem?.setShortcut(for: .queueStartStop)
      //  queueStopItem?.setShortcut(for: nil)
      //} else {
      //  queueStartItem?.setShortcut(for: nil)
      //  queueStopItem?.setShortcut(for: .queueStartStop)
      //}
    }
  }
  
  private func updateBatchShortcuts() {
    iterateOverBatchParentItems {
      $0.refreshShortcut()
    }
  }
  
  private func updateMenuItemStates() {
    updateDisabledStaticItems()
    updateStaticItemVisibility()
    updateDynamicItemVisibility()
  }
  
  private func updateDisabledStaticItems() {
    let notBusy = !AppModel.busy
    queueStartItem?.isEnabled = notBusy && !queue.isOn // although expect to get hidden if invalid
    queueReplayItem?.isEnabled = notBusy && queue.isOn && !queue.isReplaying
    queueStopItem?.isEnabled = notBusy && queue.isOn
    queuedCopyItem?.isEnabled = notBusy
    queuedPasteItem?.isEnabled = notBusy && !queue.isEmpty
    queuedPasteMultipleItem?.isEnabled = notBusy && !queue.isEmpty
    queuedPasteAllItem?.isEnabled = notBusy && !queue.isEmpty
    queueAdvanceItem?.isEnabled = notBusy && !queue.isEmpty
    let batchFilled = !history.isLastBatchEmpty
    replayLastBatchItem?.isEnabled = notBusy && batchFilled && !queue.isOn // although expect to get hidden if queue on
    saveLastBatchItem?.isEnabled = notBusy && batchFilled && !queue.isOn // this also hidden if not allowed
    saveCurrentBatchItem?.isEnabled = notBusy && batchFilled && queue.isOn // expect to get hidden ^similarly
    
    clearItem?.isEnabled = notBusy
    undoCopyItem?.isEnabled = notBusy
    
    deleteItem?.isEnabled = false // until programmatically enabled later as items are highlighted
  }
  
  private func updateStaticItemVisibility() {
    let badgedMenuItemsSupported = if #available(macOS 14, *) { true } else { false }
    let promoteExtras = AppModel.allowPurchases && UserDefaults.standard.promoteExtras && badgedMenuItemsSupported
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
    
    if !AppModel.allowLastBatch { // last batch off but saved batches on not supported atm
      replayLastBatchItem?.isVisible = false
      saveLastBatchItem?.isVisibleAlternate = false
      saveCurrentBatchItem?.isVisible = false
    } else {
      replayLastBatchItem?.isVisible = !queue.isOn
      saveLastBatchItem?.isVisibleAlternate = !queue.isOn && (AppModel.allowSavedBatches || promoteExtras)
      saveCurrentBatchItem?.isVisible = queue.isOn && (AppModel.allowSavedBatches || promoteExtras)
      if !AppModel.allowSavedBatches && promoteExtras, #available(macOS 14, *), let bedge = promoteExtrasBadge as? NSMenuItemBadge {
        saveLastBatchItem?.badge = bedge
        saveCurrentBatchItem?.badge = bedge
      }
    }
    
    // Bonus features to hide when not purchased
    queuedPasteMultipleItem?.isVisible = AppModel.allowPasteMultiple || promoteExtras
    queuedPasteAllItem?.isVisibleAlternate = AppModel.allowPasteMultiple || promoteExtras
    if !AppModel.allowPasteMultiple && promoteExtras, #available(macOS 14, *), let bedge = promoteExtrasBadge as? NSMenuItemBadge {
      queuedPasteMultipleItem?.badge = bedge
      queuedPasteAllItem?.badge = bedge
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
    
    // after deleting all queue items, deleteItem is explicitly hidden, noteItem left visible,
    // yet the menu draws with note blurb missing and "Delete Clipboard Item" showing. an OS bug?
  }
  
  private func updateDynamicItemVisibility() {
    // visibility of each of the 3 sections of clip items, plus their titles and trailing separators
    updateQueueClipItemVisibility()
    updateHistoryClipItemVisibility()
    updateBatchItemVisibility()
  }
  
  private func updateQueueClipItemVisibility() {
    let showQueueSection = !queue.isEmpty 
    
    queueHeadingItem?.isVisible = showQueueSection
    topQueueAnchorItem?.isVisible = showQueueSection
    postQueueSeparatorItem?.isVisible = showQueueSection
    
    guard let first = firstQueueItemIndex, let end = postQueueItemIndex, first <= end else {
      if !queue.isEmpty {
        fatalError("can't locate the queue menu items section, expected \(queue.batchClips.count)*\(batchItemGroupCount) items")
      } else {
        fatalError("can't locate the queue menu items section")
      }
    }
    
    for index in first ..< end {
      setClipItemVisibility(at: index, visible: showQueueSection, badgeless: true)
    }
    
    // badge the last item, which is the head of the queue 
    if first < end, #available(macOS 14, *) {
      let headItemGroup = useNaturalOrder ? first : end - batchItemGroupCount
      for cnt in 0 ..< batchItemGroupCount {
        if let headQueueItem = safeItem(at: headItemGroup + cnt), headQueueItem.isEnabled { 
          headQueueItem.badge = queueHeadBadge as? NSMenuItemBadge
        }
      }
    }
  }
  
  private func updateHistoryClipItemVisibility() {
    let showHistorySection = useHistory && showsExpandedMenu
    
    historyHeadingItem?.isVisible = showHistorySection
    topHistoryAnchorItem?.isVisible = showHistorySection
    postHistorySeparatorItem?.isVisible = showHistorySection
    
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
    
    let maxVisibleHistoryClips = !showHistorySection ? 0 :
      max((showsFullExpansion ? AppModel.effectiveMaxClips : AppModel.effectiveMaxVisibleClips), 0)
    
    guard let first = firstHistoryItemIndex, let end = postHistoryItemIndex, first <= end else {
      if maxVisibleHistoryClips > 0 {
        fatalError("can't locate the history menu items section, expected at least \(maxVisibleHistoryClips) items")
      } else {
        fatalError("can't locate the history menu items section")
      }
    }
    
    let endVisible = first + maxVisibleHistoryClips * historyItemGroupCount
    for index in first ..< end {
      setClipItemVisibility(at: index, visible: showHistorySection && index < endVisible, badgeless: true)
    }
  }
  
  private func updateBatchItemVisibility() {
    let showBatchSection = showsSavedBatches && batchItemCount > 0 && !queue.isOn
    
    batchesHeadingItem?.isVisible = showBatchSection
    postBatchesSeparatorItem?.isVisible = showBatchSection
    
    guard let first = firstBatchItemIndex, let end = postBatchesItemIndex, first <= end else {
      fatalError("can't locate the batches menu items section")
    }
    
    for index in first ..< end {
      safeItem(at: index)?.isHidden = !showBatchSection
    }
  }
  
  private func trimHistoryClipMenuItems() {
    // remove history menu items bottom up to sync with history storage which
    // may have trimmed off the end of its clips to keep within the maximum allowed
    guard useHistory else {
      return
    }
    let clips = history.all
    if historyClipsCount <= clips.count {
      return
    }
    let newBottommostClip = clips.last // will remove off end of the menu until the limit or item matching this clip
    
    guard var historyVisitIndex = postHistoryItemIndex, let firstHistoryIndex = firstHistoryItemIndex else {
      fatalError("can't locate the history menu items section")
    }
    while historyVisitIndex > firstHistoryIndex {
      historyVisitIndex -= historyItemGroupCount
      guard let menuItemClip = (safeItem(at: historyVisitIndex) as? ClipMenuItem)?.clip else {
        fatalError("menu item at \(historyVisitIndex) is invalid or not a clip menu item: \(String(describing: item(at: historyVisitIndex)))")
      }
      if menuItemClip === newBottommostClip {
        return
      }
      // these history menu items don't match the last clip, remove 'em
      safeRemoveClipItems(at: historyVisitIndex, count: historyItemGroupCount)
    }
  }
  
  // MARK: - more public functions
  
  func highlightedClipMenuItem() -> ClipMenuItem? {
    return highlightedClipItem()
  } 
  
  func highlightedBatchMenuItem() -> BatchMenuItem? {
    return highlightedBatchItem()
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
    iterateOverBatchParentItems {
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
    showsExpandedMenu = enable && useHistory && AppModel.allowExpandedHistory && historyItemCount > 0
    showsFullExpansion = enable && full
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
    
    let menuItems = buildBatchItemAndAlternates(forClip: clip)
    safeInsertClipItems(menuItems, at: index)
    
    trimHistoryClipMenuItems()
    
    sanityCheckClipMenuItems()
  }
  
  func addedClipToHistory(_ clip: Clip) {
    guard useHistory else {
      os_log(.debug, "didn't expect to add history menu item when history disabled")
      return
    }
    guard queueItemCount == 0 else {
      os_log(.debug, "didn't expect to add history menu item when queue not empty")
      sanityCheckClipMenuItems()
      return
    }
    guard let index = firstHistoryItemIndex else {
      fatalError("can't locate the queue menu items section")
    }
    
    let menuItems = buildHistoryItemAndAlternates(forClip: clip)
    safeInsertClipItems(menuItems, at:index)
    
    trimHistoryClipMenuItems()
    
    sanityCheckClipMenuItems()
  }
  
  func pushedClipsOnQueue(_ count: Int) {
    queueItemsNeedsRebuild = true
    historyItemsNeedsRebuild = true
    rebuildNecessaryDynamicItemsInBackground()
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
    
    // Leaky abstraction!: We know popped queue clips don't no longer go to the history right away.
    // If queue hassn't fully emptied, rely on visibility update to remove popped clip items the
    // next time the menu is opened and no need to rebuild any menu items yet.
    if queue.isEmpty {
      queueItemsNeedsRebuild = true
      historyItemsNeedsRebuild = true
      rebuildNecessaryDynamicItemsInBackground()
    }
  }
  
  func poppedClipOffQueue() {
    poppedClipsOffQueue(1)
  }
  
  func cancelledQueue(_ count: Int) {
    poppedClipsOffQueue(count)
  }
  
  func startedQueueFromHistory(_ headHistoryPosition: Int) {
    guard useHistory else {
      os_log(.debug, "didn't expect to start queue from history menu items when history disabled")
      return
    }
    guard queueItemCount == 0 else {
      os_log(.debug, "didn't expect to start queue from history menu items when queue not currently empty")
      sanityCheckClipMenuItems()
      return
    }
    
    queueItemsNeedsRebuild = true
    historyItemsNeedsRebuild = true
    rebuildNecessaryDynamicItemsInBackground()
  }
  
  func startedQueueFromBatch() {
    queueItemsNeedsRebuild = true
    rebuildNecessaryDynamicItemsInBackground()
  }
  
  // of these sync functions only the deletedXxxx ones below need to readjust the menu state
  // and the highlighed item afterward, because only when deleting does the menu stay open
  
  func deletedClipFromQueue(_ queuePosition: Int) {
    let clipsCount = queueClipsCount
    guard queuePosition >= 0 && queuePosition < clipsCount else {
      os_log(.debug, "didn't expect queue index %d to exceed range of queue clips, 0..<%d", queuePosition, clipsCount)
      sanityCheckClipMenuItems()
      return
    }
    guard let firstQueueIndex = firstQueueItemIndex else {
      fatalError("can't locate the queue menu items section")
    }
    
    let menuOrderPosition = useNaturalOrder ? clipsCount - queuePosition - 1 : queuePosition
    let index = firstQueueIndex + menuOrderPosition * batchItemGroupCount
    guard let clipMenuItem = safeItem(at: index) as? ClipMenuItem else {
      fatalError("can't get menu item for queue index \(queuePosition) at menu index \(index)")
    }
    
    let wasHeadItem = queuePosition == clipsCount - 1 // was badged menu item
    let wasLastInSection = menuOrderPosition == clipsCount - 1 // was lowest in the menu
    let wasHighlighed = clipMenuItem == highlightedClipMenuItem()
    
    safeRemoveClipItems(at: index, count: batchItemGroupCount)
    
    if queueItemCount == 0 {
      // don't call just updateQueueClipItemVisibility. transform many manu items to account for queue now empty
      updateMenuItemStates()
      
      highlightItem(nil)
      
    } else {
      // change the highlighted item appropriately
      if wasHighlighed && !wasLastInSection, let nextItem = safeItem(at: index) { 
        // after deleting the selected batch item, as normal highlight the next item
        highlightItem(nextItem)
      }
      else if wasHighlighed && menuOrderPosition > 0 && wasLastInSection,
              let newLastItem = safeItem(at: firstQueueIndex + (menuOrderPosition - 1) * batchItemGroupCount)
      {
        // after deleting the selected last queued item, highlight the previous item,
        // the new last one in the queue
        highlightItem(newLastItem)
      }
      
      // badge the new head item if necessary
      if wasHeadItem, let postQueueIndex = postQueueItemIndex, #available(macOS 14, *) {
        let headItemGroup = useNaturalOrder ? firstQueueIndex : postQueueIndex - batchItemGroupCount
        for cnt in 0 ..< batchItemGroupCount {
          if let headQueueItem = safeItem(at: headItemGroup + cnt), headQueueItem.isEnabled { 
            headQueueItem.badge = queueHeadBadge as? NSMenuItemBadge
          }
        }
        // this was an attempt to get the menu to show the new badge immediately, doesn't seem to work
        if let headItem = safeItem(at: headItemGroup) {
          itemChanged(headItem)
          update()
        }
      }
    }
    
    sanityCheckClipMenuItems()
  }
  
  func deletedClipFromHistory(_ historyPosition: Int) {
    guard historyPosition >= 0 && historyPosition < historyClipsCount else {
      os_log(.debug, "didn't expect history index %d to exceed range of history clips, 0..<%d", historyPosition, historyClipsCount)
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
      max((showsFullExpansion ? AppModel.effectiveMaxClips : AppModel.effectiveMaxVisibleClips), 0)
    let wasLastInSection = historyPosition == expectedNumVisibleHistoryClips - 1
    let wasHighlighed = clipMenuItem == highlightedClipMenuItem()
    
    safeRemoveClipItems(at: index, count: historyItemGroupCount)
    
    if historyItemCount == 0 {
      updateHistoryClipItemVisibility() // removes the now unwanted separator 
      
      highlightItem(nil)
      
    } else if wasHighlighed && !wasLastInSection { 
      // after deleting the selected last history item, normally highlight the next item
      if let nextItem = safeItem(at: index) {
        highlightItem(nextItem)
      }
    } else if wasHighlighed && historyPosition > 0 && wasLastInSection {
      // after deleting the selected last history item, next highlight the previous item,
      // the new last one in history
      if let newLastItem = safeItem(at: firstHistoryIndex + (historyPosition - 1) * historyItemGroupCount) {
        highlightItem(newLastItem)
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
    
    safeRemoveClipItems(at: firstHistoryIndex ..< postHistoryIndex)
    safeRemoveClipItems(at: firstQueueIndex ..< postQueueIndex)
    
    updateQueueClipItemVisibility()
    updateHistoryClipItemVisibility()
    
    sanityCheckClipMenuItems()
  }
  
  func addedBatch(_ batch: Batch) {
    guard let firstMenuIndex = firstBatchItemIndex else {
      fatalError("can't find the place to insert batch menu items")
    }
    let sortedBatches = history.batches
    guard let position = sortedBatches.firstIndex(where: { $0 == batch }) else {
      return
    }
    
    guard let menuItem = buildBatchParentItem(forBatch: batch) else {
      return
    }
    
    addBatchSubmenuItems(forParentItem: menuItem, fromClips: batch.getClipsArray())
    safeInsertBatchItem(menuItem, at: firstMenuIndex + position)
    
    sanityCheckBatchMenuItems()
  }
  
  func renamedBatch(_ batch: Batch) {
    iterateOverBatchParentItems { item in
      if item.batch === batch {
        item.refreshShortcut()
        item.regenerateTitle()
        return false // to abort iterating
      }
      return true
    }
  }
  
  func deletedBatch(_ position: Int) {
    guard position >= 0 && position < batchItemCount else {
      os_log(.debug, "didn't expect batch index %d to exceed range of saved batches, 0..<%d", position, batchItemCount)
      return
    }
    guard let firstBatchIndex = firstBatchItemIndex else {
      fatalError("can't locate the batch menu items section")
    }
    
    let index = firstBatchIndex + position
    guard let batchMenuItem = safeItem(at: index) as? BatchMenuItem else {
      fatalError("can't get menu item for batch index \(position) at menu index \(index)")
    }
    
    let wasLastInSection = position == batchItemCount - 1 // was lowest in the menu
    let wasHighlighed = batchMenuItem == highlightedBatchMenuItem()
    
    safeRemoveBatchItem(at: index)
    
    if batchItemCount == 0 {
      updateBatchItemVisibility() // removes the now unwanted separator 
      
      highlightItem(nil)
      
    } else if wasHighlighed && !wasLastInSection { 
      // after deleting the selected batch item, as normal highlight the next item
      if let nextItem = safeItem(at: index) {
        highlightItem(nextItem)
      }
    } else if wasHighlighed && position > 0 && wasLastInSection {
      // after deleting the selected last batch item, next highlight the previous item,
      // the new last one in the menu 
      if let newLastItem = safeItem(at: firstBatchIndex + position - 1) {
        highlightItem(newLastItem)
      }
    }
    
    sanityCheckBatchMenuItems()
  }
  
  func deletedClip(_ clipsPosition: Int, fromBatch batchPosition: Int) {
    guard batchPosition >= 0 && batchPosition < batchItemCount else {
      os_log(.debug, "didn't expect batch index %d to exceed range of saved batches, 0..<%d", batchPosition, batchItemCount)
      return
    }
    guard let firstBatchIndex = firstBatchItemIndex else {
      fatalError("can't locate the batch menu items section")
    }
    
    let index = firstBatchIndex + batchPosition
    guard let batchMenuItem = safeItem(at: index) as? BatchMenuItem else {
      fatalError("can't get menu item for batch index \(batchPosition) at menu index \(index)")
    }
    
    guard clipsPosition >= 0 && clipsPosition < batchMenuItem.clipCount else {
      os_log(.debug, "didn't expect batch clip index %d to exceed range of batch clips, 0..<%d", clipsPosition, batchMenuItem.clipCount)
      return
    }
    guard let firstClipIndex = batchMenuItem.firstClipItemIndex, let submenu = batchMenuItem.submenu else {
      fatalError("can't locate the batch's clip items in its submenu")
    }
    
    let menuOrderPosition = useNaturalOrder ? batchMenuItem.clipCount - clipsPosition - 1 : clipsPosition
    let subindex = firstClipIndex + menuOrderPosition * batchItemGroupCount
    guard subindex < submenu.numberOfItems && subindex + batchItemGroupCount <= submenu.numberOfItems,
            let clipMenuItem = submenu.item(at: subindex) as? ClipMenuItem else {
      fatalError("can't get submenu clip item for index \(clipsPosition) at menu index \(subindex)")
    }
    
    let wasHeadItem = clipsPosition == batchMenuItem.clipCount - 1 // was badged menu item
    let wasLastInMenu = menuOrderPosition == batchMenuItem.clipCount - 1 // was last in the menu, ie. at the end
    let wasHighlighed = clipMenuItem == submenu.highlightedItem
    
    for cnt in 0 ..< batchItemGroupCount { 
      submenu.removeItem(at: subindex + cnt)
    }
    
    if batchMenuItem.clipCount > 0, let firstClipIndex = batchMenuItem.firstClipItemIndex, let postClipIndex = batchMenuItem.postClipItemIndex {
      // change the highlighted item appropriately
      if wasHighlighed && !wasLastInMenu && subindex < submenu.numberOfItems, let nextItem = submenu.item(at: subindex) {
        // after deleting the selected batch item, as normal highlight the next item
        highlightSubmenuItem(nextItem, in: submenu)
      }
      else if wasHighlighed && wasLastInMenu && postClipIndex - batchItemGroupCount < submenu.numberOfItems,
              let newLastItem = submenu.item(at: postClipIndex - batchItemGroupCount)
      {
        // after deleting the selected last clip item, next highlight the previous item,
        // the new last one in the menu 
        highlightSubmenuItem(newLastItem, in: submenu)
      }
      
      // badge the new head item if necessary
      if wasHeadItem, #available(macOS 14, *) {
        let headItemGroup = useNaturalOrder ? firstClipIndex : postClipIndex - batchItemGroupCount
        for cnt in 0 ..< batchItemGroupCount {
          if headItemGroup + cnt < submenu.numberOfItems, let headItem = submenu.item(at: headItemGroup + cnt), headItem.isEnabled {
            headItem.badge = queueHeadBadge as? NSMenuItemBadge
          }
        }
        // this was an attempt to get the menu to show the new badge immediately, doesn't seem to work
        if let headItem = submenu.item(at: headItemGroup) {
          submenu.itemChanged(headItem)
          submenu.update()
        }
      }
    }
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
      highlightItem(firstItem)
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
      highlightItem(highlightableItems(items).last) // start from the end after reaching the first item
    }
  }
  
  func selectNext() {
    if !highlightNext(items) {
      highlightItem(highlightableItems(items).first) // start from the beginning after reaching the last item
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
  
  private func highlightedBatchItem() -> BatchMenuItem? {
    #if DELETE_MENUITEM_DETECTS_ITS_SHORTCUT
    return nil
    #else
    return highlightedItem as? BatchMenuItem
    #endif
  }
  
  private func highlightNext(_ menuItems: [NSMenuItem]) -> Bool {
    let highlightableItems = self.highlightableItems(menuItems)
    let currentHighlightedItem = highlightedItem ?? highlightableItems.first
    var itemsIterator = highlightableItems.makeIterator()
    while let item = itemsIterator.next() {
      if item == currentHighlightedItem {
        if let itemToHighlight = itemsIterator.next() {
          highlightItem(itemToHighlight)
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
  
  private func highlightItem(_ itemToHighlight: NSMenuItem?) {
    if #available(macOS 14, *) {
      DispatchQueue.main.async { self.callHhighlightItem(itemToHighlight) }
    } else {
      callHhighlightItem(itemToHighlight, onMenu: self)
    }
  }
  
  private func callHhighlightItem(_ itemToHighlight: NSMenuItem?) {
    let highlightItemSelector = NSSelectorFromString("highlightItem:")
    // We need to first highlight a menu item somewhere near the top of the menu to
    // force menu redrawing (was using the search menu item, but its now sometimes gone)
    // when it has more items that can fit into the screen height and scrolling items
    // are added to the top and bottom of menu.
    self.perform(highlightItemSelector, with: queuedCopyItem)
    if let item = itemToHighlight, !item.isHighlighted, items.contains(item) {
      perform(highlightItemSelector, with: item)
    } else {
      // un-highlight the copy menu item we just highlighted
      perform(highlightItemSelector, with: nil)
    }
  }
  
  private func highlightSubmenuItem(_ itemToHighlight: NSMenuItem?, in menu: NSMenu) {
    if #available(macOS 14, *) {
      DispatchQueue.main.async { self.callHhighlightItem(itemToHighlight, onMenu: menu) }
    } else {
      callHhighlightItem(itemToHighlight, onMenu: menu)
    }
  }
  
  private func callHhighlightItem(_ itemToHighlight: NSMenuItem?, onMenu menu: NSMenu) {
    let highlightItemSelector = NSSelectorFromString("highlightItem:")
    if let item = itemToHighlight, !item.isHighlighted, menu.items.contains(item) {
      menu.perform(highlightItemSelector, with: item)
    } else {
      menu.perform(highlightItemSelector, with: nil)
    }
  }
  
  // MARK: - utility functions
  // In these functions `index` means menu item index
  
  private func setClipItemVisibility(at index: Int, visible: Bool, badgeless: Bool = false) {
    guard let menuItem = safeItem(at: index) as? ClipMenuItem else {
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
  
  private func safeInsertClipItem(_ newItem: NSMenuItem, at index: Int) {
    guard !items.contains(newItem), index <= items.count else {
      return
    }
    
    sanityCheckClipMenuItemIndex(index, forInserting: true)
    
    insertItem(newItem, at: index)
  }
  
  private func safeInsertClipItems(_ newItems: [NSMenuItem], at index: Int) {
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
  
  private func safeRemoveClipItem(_ deleteItem: NSMenuItem) {
    guard items.contains(deleteItem) else {
      return
    }
    
    sanityCheckClipMenuItemIndex(index(of: deleteItem))
    
    removeItem(deleteItem)
  }
  
  private func safeRemoveClipItems(_ deleteItems: [NSMenuItem]) {
    for deleteItem in deleteItems {
      guard items.contains(deleteItem) else {
        return
      }
      
      sanityCheckClipMenuItemIndex(index(of: deleteItem))
      
      removeItem(deleteItem)
    }
  }
  
  private func safeRemoveClipItem(at index: Int) {
    guard index <= items.count else {
      return
    }
    
    sanityCheckClipMenuItemIndex(index)
    
    removeItem(at: index)
  }
  
  private func safeRemoveClipItems(at index: Int, count: Int) {
    guard count > 0 else {
      return
    }
    safeRemoveClipItems(at: index ..< index + count)
  }
  
  private func safeRemoveClipItems(at range: Range<Int>) {
    guard !range.isEmpty else {
      return
    }
    
    // redunant to do both these and the checks in the loop below
    //sanityCheckClipMenuItemIndex(range.lowerBound)
    //sanityCheckClipMenuItemIndex(range.upperBound - 1)
    
    for index in range.reversed() {
      sanityCheckClipMenuItemIndex(index)
      
      removeItem(at: index)
    }
  }
  
  private func safeInsertBatchItem(_ newItem: NSMenuItem, at index: Int) {
    guard !items.contains(newItem), index <= items.count else {
      return
    }
    
    sanityCheckBatchMenuItemIndex(index, forInserting: true)
    
    insertItem(newItem, at: index)
  }
  
  private func safeRemoveBatchItem(at index: Int) {
    guard index <= items.count else {
      return
    }
    
    sanityCheckBatchMenuItemIndex(index)
    
    removeItem(at: index)
  }
  
  private func safeRemoveBatchItems(at range: Range<Int>) {
    guard !range.isEmpty else {
      return
    }
    
    for index in range.reversed() {
      //sanityChecBatchClipMenuItemIndex(index)
      
      removeItem(at: index)
    }
  }
  
  func saveMoveItems(at index: Int, count: Int, to destIndex: Int) {
    // after working to get this right, now i don't think its needed anymore :(
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
    guard let item = item(at: i) else { // never called to add to very end of the menu, so no need to add `inserting==false`
      fatalError("menu index \(i) to be changed is out of bounds with respect to the entire menu")
    }
    guard inserting || item is ClipMenuItem else {
      fatalError("menu index \(i) is not a ClipMenuItem")
    }
    if i < firstQueueIndex {
      fatalError("menu index \(i) to be changed preceeds the queue section")
    }
    if i > (inserting ? postQueueIndex : postQueueIndex - 1) && i < firstHistoryIndex {
      fatalError("menu index \(i) to be changed is inbetween queue and history sections")
    }
    if i > (inserting ? postHistoryIndex : postHistoryIndex - 1) {
      fatalError("menu index \(i) to be changed follows the history section")
    }
  }
  
  private func sanityCheckBatchMenuItemIndex(_ i: Int, forInserting inserting: Bool = false) {
    guard let firstBatchIndex = firstBatchItemIndex, let postBatchIndex = postBatchesItemIndex else {
      fatalError("cannot locate batch section")
    }
    guard let item = item(at: i) else { // never called to add to very end of the menu, so no need to add `inserting==false`
      fatalError("menu index \(i) to be changed is out of bounds with respect to the entire menu")
    }
    guard inserting || item is BatchMenuItem else {
      fatalError("menu index \(i) is not a BatchMenuItem")
    }
    if i < firstBatchIndex {
      fatalError("menu index \(i) to be changed preceeds the batch section")
    }
    if i > (inserting ? postBatchIndex : postBatchIndex - 1) {
      fatalError("menu index \(i) to be changed follows the batch section")
    }
  }
  
  // TODO: another function for verifying a batch submenu item index
  
  private func sanityCheckClipMenuItems() {
    guard let firstQueueIndex = firstQueueItemIndex, let postQueueIndex = postQueueItemIndex else {
      fatalError("cannot locate queue section")
    }
    guard let firstHistoryIndex = firstHistoryItemIndex, let postHistoryIndex = postHistoryItemIndex else {
      fatalError("cannot locate history section")
    }
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
      fatalError("menu item at \(index) has a nil clip property")
    }
    guard !clip.isFault else {
      os_log(.debug, "menu item at %d has clip with isFault set, not sure its a problem? %@", index, item.title)
      return
    }
    guard let clipTitle = clip.title else {
      fatalError("menu item at \(index) has clip with a nil title")
    }
    guard clipTitle == item.title || (clipTitle == "" && item.title == " ") else {
      fatalError("menu item at \(index) has the wrong title, try: \(suggestedCommand)")
    }
  }
  
  private func sanityCheckBatchMenuItems() {
    guard let firstBatchIndex = firstBatchItemIndex, let postBatchIndex = postBatchesItemIndex else {
      fatalError("cannot locate batch section")
    }
    for index in firstBatchIndex ..< postBatchIndex {
      sanityCheckBatchParentMenuItem(at: index, forSectionStartingAt: firstBatchIndex)
      
      // TODO: verify batch's aubmwnu items also
    }
  }
  
  func sanityCheckBatchParentMenuItem(at index: Int, forSectionStartingAt from: Int) {
    let suggestedCommandMap = #"map{$0.title + ($0 is BatchMenuItem ?"  VS  "+(($0 as! BatchMenuItem).title) : "")}"#
    let suggestedCommand = "p items[\(from)...\(index)].\(suggestedCommandMap)"
    guard let item = item(at: index) as? BatchMenuItem else {
      fatalError("menu item at \(index) not a BatchMenuItem, try: \(suggestedCommand)")
    }
    guard let batch = item.batch else {
      fatalError("menu item at \(index) has a nil batch property")
    }
    guard !batch.isFault else {
      os_log(.debug, "menu item at %d has clip with isFault set, not sure its a problem? %@", index, item.title)
      return
    }
    guard let batchTitle = batch.title else {
      fatalError("menu item at \(index) has batch with a nil title")
    }
    guard batchTitle == item.title || (batchTitle == "" && item.title == " ") else {
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
  
  #if DEBUG
  func addDebugItems() {
    //addItem(NSMenuItem.separator())
    //let mi = addItem(withTitle: "banana", action: #selector(banana(_:)), keyEquivalent: "")
    //mi.target = self
  }
  #endif
  
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
