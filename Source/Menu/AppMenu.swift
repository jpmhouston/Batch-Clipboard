//
//  AppMenu
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-03-20.
//  Portions Copyright © 2024 Bananameter Labs. All rights reserved.
//
//  Based on Menu.swift from Maccy
//  Portions are copyright © 2024 Alexey Rodionov. All rights reserved.
//

// swiftlint:disable file_length
import AppKit
import os.log

// Custom menu supporting "search-as-you-type" based on https://github.com/mikekazakov/MGKMenuWithFilter.
// swiftlint:disable type_body_length
class AppMenu: NSMenu, NSMenuDelegate {
  static let menuWidth = 300
  static let popoverGap = 5.0
  static let minNumMenuItems = 5 // things get weird if the effective menu size is 0
  
  private var isVisible = false
  
  private var history: History!
  private var queue: ClipboardQueue!
  private let previewController = PreviewPopoverController()
  
  class ClipRecord: NSObject {
    var value: String
    var title: String { item?.title ?? "" }
    var item: ClipItem?
    var menuItems: [ClipMenuItem]
    var popoverAnchor: NSMenuItem? { menuItems.last } // only when usePopoverAnchors, caller must know this :/
    
    init(value: String, item: ClipItem?, menuItems: [ClipMenuItem]) {
      self.value = value
      self.item = item
      self.menuItems = menuItems
    }
  }
  
  private var clips: [ClipRecord] = []
  private var headOfQueueClip: ClipRecord?
  private var queueItemsSeparator: NSMenuItem?
  private var disableDeleteTimer: DispatchSourceTimer?
  
  internal var historyMenuItems: [ClipMenuItem] {
    items.compactMap({ $0 as? ClipMenuItem }).excluding([topAnchorItem])
  }
  
  private var historyMenuItemsGroupCount: Int { usePopoverAnchors ? 3 : 2 } // 1 main, 1 alternate, 1 popover anchor
  private var maxMenuItems: Int {
    let numMenuItemsSetting = max(Self.minNumMenuItems, UserDefaults.standard.maxMenuItems)
    let numItemsStoredSetting = max(Self.minNumMenuItems, UserDefaults.standard.size)
    return if !AppModel.allowDictinctStorageSize {
      numMenuItemsSetting
    } else if showsExpandedMenu && showsFullExpansion {
      max(numMenuItemsSetting, numItemsStoredSetting)
    } else {
      min(numMenuItemsSetting, numItemsStoredSetting)
    }
  }
  
  private var usePopoverAnchors: Bool {
    // note: hardcoding false to exercise using anchors on >=sonoma won't work currently
    // would require changes in PreviewPopoverController
    if #unavailable(macOS 14) { true } else { false }
  }
  private var removeViewToHideMenuItem: Bool {
    if #unavailable(macOS 14) { true } else { false }
  }
  private var useQueueItemsSeparator: Bool {
    // to use the separator _and_ badge on >=sonoma
    true
    // to skip using separator when using the badge on >=sonoma. still deciding
    //if #unavailable(macOS 14) { true } else { false }
  }
  private var promoteExtrasBadge: NSObject?
  private var cacheUndoCopyItemShortcut = ""
  private var showsExpandedMenu = false
  private var showsFullExpansion = false
  private var showsSearchHeader = false
  private var isFiltered = false
  
  private var historyHeaderView: FilterFieldView? { historyHeaderItem?.view as? FilterFieldView ?? historyHeaderViewCache }
  private var historyHeaderViewCache: FilterFieldView?
  private let search = Searcher()
  private var lastHighlightedItem: ClipMenuItem?
  private var topAnchorItem: ClipMenuItem?
  private var previewPopover: NSPopover?
  private var protoCopyItem: ClipMenuItem?
  private var protoReplayItem: ClipMenuItem?
  private var protoAnchorItem: ClipMenuItem?
  private var menuWindow: NSWindow? { NSApp.menuWindow }
  private var deleteAction: Selector?
  
  @IBOutlet weak var queueStartItem: NSMenuItem?
  @IBOutlet weak var queueStopItem: NSMenuItem?
  @IBOutlet weak var queueReplayItem: NSMenuItem?
  @IBOutlet weak var queuedCopyItem: NSMenuItem?
  @IBOutlet weak var queuedPasteItem: NSMenuItem?
  @IBOutlet weak var queueAdvanceItem: NSMenuItem?
  @IBOutlet weak var queuedPasteMultipleItem: NSMenuItem?
  @IBOutlet weak var queuedPasteAllItem: NSMenuItem?
  @IBOutlet weak var noteItem: NSMenuItem?
  @IBOutlet weak var historyHeaderItem: NSMenuItem?
  @IBOutlet weak var prototypeCopyItem: NSMenuItem?
  @IBOutlet weak var prototypeReplayItem: NSMenuItem?
  @IBOutlet weak var prototypeAnchorItem: NSMenuItem?
  @IBOutlet weak var trailingSeparatorItem: NSMenuItem?
  @IBOutlet weak var deleteItem: NSMenuItem?
  @IBOutlet weak var clearItem: NSMenuItem?
  @IBOutlet weak var undoCopyItem: NSMenuItem?
  
  // MARK: -
  
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
    }
    if let prototypeReplayItem = prototypeReplayItem as? ClipMenuItem {
      protoReplayItem = prototypeReplayItem
      removeItem(prototypeReplayItem)
    }
    if let prototypeAnchorItem = prototypeAnchorItem as? ClipMenuItem {
      protoAnchorItem = prototypeAnchorItem
      removeItem(prototypeAnchorItem)
    }
    
    // save aside this action for when we clear it so search box key events can drive item deletions instead
    deleteAction = deleteItem?.action
    
    // remove this placeholder title just in case there's another bug and the headerview isn't shown
    historyHeaderItem?.title = ""
  }
  
  func prepareForPopup() {
    rebuildItemsAsNeeded()
    updateShortcuts()
    updateItemVisibility()
    updateDisabledMenuItems()
    addQueueItemsSeparator()
  }
  
  func menuWillOpen(_ menu: NSMenu) {
    isVisible = true
    
    previewController.menuWillOpen()
    
    if showsExpandedMenu && AppModel.allowHistorySearch && !UserDefaults.standard.hideSearch && !clips.isEmpty,
       let field = historyHeaderView?.queryField
    {
      field.refusesFirstResponder = false
      field.window?.makeFirstResponder(field)
      showsSearchHeader = true
    } else {
      showsSearchHeader = false
    }
  }
  
  func menuDidClose(_ menu: NSMenu) {
    isVisible = false
    showsExpandedMenu = false
    removeQueueItemsSeparator()
    
    previewController.menuDidClose()
    
    isFiltered = false
    if showsSearchHeader {
      // not sure why this is in a dispatch to the main thread, some timing thing i'm guessing
      DispatchQueue.main.async { 
        self.historyHeaderView?.setQuery("", throttle: false)
        self.historyHeaderView?.queryField.refusesFirstResponder = true
      }
    }
  }
  
  func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
    previewController.cancelPopover()
    
    // forget the outstanding deferred disable of the delete item
    disableDeleteTimer?.cancel()
    disableDeleteTimer = nil
    
    if let historyItem = item as? ClipMenuItem {
      deleteItem?.isEnabled = !AppModel.busy
      lastHighlightedItem = historyItem
      
      previewController.showPopover(for: historyItem, allClips: clips)
      
    } else if item == nil || item == deleteItem {
      // called with nil when cursor is over a disabled item, a separator, or is
      // away from any menu items
      // when cmd-delete hit, this is first called with nil and then with the
      // delete menu item itself, for both of these we must not (immediately) disable
      // the delete menu or unset lastHighlightedItem or else deleting won't work
      nop()
      disableDeleteTimer = DispatchSource.scheduledTimerForRunningOnMainQueue(afterDelay: 0.5) { [weak self] in
        self?.deleteItem?.isEnabled = false
        self?.lastHighlightedItem = nil
        self?.disableDeleteTimer = nil
      }
    } else {
      deleteItem?.isEnabled = false
      lastHighlightedItem = nil
    }
  }
  
  // MARK: -
  
  func buildHistoryItems() {
    clearHistoryItems() // wipes `clips` as well as history menu items
    
    if usePopoverAnchors {
      insertTopAnchorItem()
    }
    
    let historyItems = history.all.prefix(maxMenuItems)
    
    for item in historyItems {
      let menuItems = buildMenuItemAlternates(item)
      guard let menuItem = menuItems.first else {
        continue
      }
      let clip = ClipRecord(
        value: menuItem.value,
        item: item,
        menuItems: menuItems
      )
      clips.append(clip)
      menuItems.forEach(appendMenuItem)
    }
    
    addDebugItems()
  }
  
  private func addQueueItemsSeparator() {
    if !useQueueItemsSeparator {
      return
    }
    
    if queueItemsSeparator != nil {
      removeQueueItemsSeparator() // expected to already be removed! but ensure now that it really is
    }
    
    if showsExpandedMenu && !isFiltered && !AppModel.busy && !queue.isEmpty &&
        clips.count > queue.size
    {
      let followingItem = clips[queue.size]
      guard let followingMenuItem = followingItem.menuItems.first, let index = safeIndex(of: followingMenuItem) else {
        return
      }
      let separator = NSMenuItem.separator()
      insertItem(separator, at: index)
      queueItemsSeparator = separator
    }
  }
  
  private func removeQueueItemsSeparator() {
    if let separator = queueItemsSeparator {
      if index(of: separator) < 0 {
        queueItemsSeparator = nil
      } else {
        removeItem(separator)
        queueItemsSeparator = nil
      }
    }
  }
  
  private func updateDisabledMenuItems() {
    let notBusy = !AppModel.busy
    queueStartItem?.isEnabled = notBusy && !queue.isOn // although expect to be hidden if invalid
    queueReplayItem?.isEnabled = notBusy && queue.isOn && !queue.isReplaying
    queueStopItem?.isEnabled = notBusy && queue.isOn
    queuedCopyItem?.isEnabled = notBusy
    queuedPasteItem?.isEnabled = notBusy && !queue.isEmpty
    queuedPasteMultipleItem?.isEnabled = notBusy && !queue.isEmpty
    queuedPasteAllItem?.isEnabled = notBusy && !queue.isEmpty
    queueAdvanceItem?.isEnabled = notBusy && !queue.isEmpty // although expect to be hidden if invalid

    clearItem?.isEnabled = notBusy
    undoCopyItem?.isEnabled = notBusy
    
    deleteItem?.isEnabled = false // until programmatically enabled later as items are highlighted
    
    // clear delete actions when search box showing so its key events can drive item deletions instead
    let searchHeaderVisible = !(historyHeaderItem?.isHidden ?? true) // ie. if not hidden
    deleteItem?.action = searchHeaderVisible ? nil : deleteAction
  }
  
  func add(_ item: ClipItem) {
    let sortedItems = history.all
    guard let insertionIndex = sortedItems.firstIndex(where: { $0 == item }) else {
      return
    }
    guard let zerothHistoryHeaderItem = topAnchorItem ?? historyHeaderItem else {
      return
    }
    
    let menuItems = buildMenuItemAlternates(item)
    guard let menuItem = menuItems.first else {
      return
    }
    let clip = ClipRecord(
      value: menuItem.value,
      item: item,
      menuItems: menuItems
    )
    clips.insert(clip, at: insertionIndex)
    
    let firstHistoryMenuItemIndex = index(of: zerothHistoryHeaderItem) + 1
    let menuItemInsertionIndex = firstHistoryMenuItemIndex + self.historyMenuItemsGroupCount * insertionIndex
    
    ensureInEventTrackingModeIfVisible {
      var index = menuItemInsertionIndex
      for menuItem in menuItems {
        self.safeInsertItem(menuItem, at: index)
        index += 1
      }
      
      // i wish there was an explanation why clearRemovedItems should be called here
      self.clearRemovedItems()
    }
  }
  
  func clearHistoryItems() {
    clear(clips)
    clearAllHistoryMenuItems()
    headOfQueueClip = nil
  }
  
  func updateHeadOfQueue(index: Int?) {
    headOfQueueClip?.menuItems.forEach { $0.isHeadOfQueue = false }
    if let index = index, index >= 0, index < clips.count {
      setHeadOfQueueClipItem(clips[index])
    } else {
      setHeadOfQueueClipItem(nil)
    }
  }
  
  func setHeadOfQueueClipItem(_ clip: ClipRecord?) {
    headOfQueueClip = clip
    clip?.menuItems.forEach { $0.isHeadOfQueue = true }
  }
  
  func updateFilter(filter: String) {
    var results = search.search(string: filter, within: clips)
    
    // Strip the results that are longer than visible items.
    if maxMenuItems > 0 && maxMenuItems < results.count {
      results = Array(results[0...maxMenuItems - 1])
    }
    
    // Remove existing menu history items
    guard let zerothHistoryHeaderItem = topAnchorItem ?? historyHeaderItem,
          let trailingSeparatorItem = trailingSeparatorItem else {
      return
    }
    assert(index(of: zerothHistoryHeaderItem) < index(of: trailingSeparatorItem))
    
    for index in (index(of: zerothHistoryHeaderItem) + 1 ..< index(of: trailingSeparatorItem)).reversed() {
      safeRemoveItem(at: index)
    }
    
    // Add back matching ones in search results order... if search is empty should be all original items
    for result in results {
      for menuItem in result.object.menuItems {
        menuItem.highlight(result.titleMatches)
        appendMenuItem(menuItem)
      }
    }
    
    isFiltered = results.count < clips.count
    
    removeQueueItemsSeparator()
    
    highlight(historyMenuItems.first)
  }
  
  func select(_ searchQuery: String) {
    if let item = highlightedItem {
      performActionForItem(at: index(of: item))
    }
    // omit Maccy fallback of copying the search query, i can't make sense of that
    // Maccy does this here, maybe keep?: cancelTrackingWithoutAnimation()
  }
  
  func select(position: Int) -> String? {
    guard clips.count > position,
          let item = clips[position].menuItems.first else {
      return nil
    }
    
    performActionForItem(at: index(of: item))
    return clips[position].value
  }
  
  func historyItem(at position: Int) -> ClipItem? {
    guard clips.indices.contains(position) else {
      return nil
    }
    
    return clips[position].item
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
  
  func highlightedMenuItem() -> ClipMenuItem? {
    nop() // TODO: remove once no longer need a breakpoint here
    
    guard let menuItem = highlightedItem, let historyMenuItem = menuItem as? ClipMenuItem else {
      return nil
    }
    
    // When deleting mulitple items by holding the removal keys
    // we sometimes get into a race condition with menu updating indices.
    // https://github.com/p0deje/Maccy/issues/628
    guard index(of: historyMenuItem) >= 0 else {
      return nil
    }
    
    return historyMenuItem
  }
  
  @discardableResult
  func delete(position: Int) -> String? {
    guard position >= 0 && position < clips.count else {
      return nil
    }
    
    let clip = clips[position]
    let value = clip.value
    let wasHighlighted = clip.item == lastHighlightedItem?.clipItem
    
    // remove menu items, history item, this class's indexing item
    clip.menuItems.forEach(safeRemoveItem)
    history.remove(clip.item)
    clips.remove(at: position)
    
    // clean up head of queue item
    if clip == headOfQueueClip {
      setHeadOfQueueClipItem(position > 0 ? clips[position - 1] : nil)
      
      // after deleting the selected last-queued item, highlight the previous item (new last one in queue)
      // instead of letting the system highlight the next one
      if wasHighlighted && position > 0 {
        let prevItem = clips[position - 1].menuItems[0]
        highlight(prevItem)
        lastHighlightedItem = prevItem
      }
    }
    
    return value
  }
  
  func deleteHighlightedItem() -> Int? {
    guard let item = lastHighlightedItem,
          let position = clips.firstIndex(where: { $0.menuItems.contains(item) }) else {
      return nil
    }
    delete(position: position)
    
    return position
  }
  
  func resizeImageMenuItems() {
    historyMenuItems.forEach {
      $0.resizeImage()
    }
  }
  
  func regenerateMenuItemTitles() {
    historyMenuItems.forEach {
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
    guard AppModel.allowExpandedHistory && !historyMenuItems.isEmpty else {
      return
    }
    showsExpandedMenu = enable // gets set back to false in menuDidClose
    showsFullExpansion = full
  }
  
  // MARK: -
  
  private func insertTopAnchorItem() {
    // need an anchor item above all the history items because they're like fenceposts
    // (see "the fencepost problem") cannot use the saarch header item like Maccy because it can be hidden
    guard let protoAnchorItem = protoAnchorItem, let historyHeaderItem = historyHeaderItem else {
      return
    }
    let anchorItem = protoAnchorItem.copy() as! ClipMenuItem
    
    let index = index(of: historyHeaderItem) + 1
    insertItem(anchorItem, at: index)
    
    topAnchorItem = anchorItem
  }
  
  private func updateShortcuts() {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      
      queueStartItem?.setShortcut(for: .queueStart)
      queuedCopyItem?.setShortcut(for: .queuedCopy)
      queuedPasteItem?.setShortcut(for: .queuedPaste)
      
      // might have a start stop hotkey at some point, something like:
      //if !queue.isOn {
      //  queueStartItem?.setShortcut(for: .queueStartStop)
      //  queueStopItem?.setShortcut(for: nil)
      //} else {
      //  queueStartItem?.setShortcut(for: nil)
      //  queueStopItem?.setShortcut(for: .queueStartStop)
      //}
    }
  }
  
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
      }
    }
    return false
  }
  
  private func highlightableItems(_ items: [NSMenuItem]) -> [NSMenuItem] {
    return items.filter { !$0.isSeparatorItem && $0.isEnabled && !$0.isHidden }
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
    // we need to highlight a near-the-top menu item to force menu redrawing
    // (was ...need to highlight the filter menu item)
    // when it has more items that can fit into the screen height
    // and scrolling items are added to the top and bottom of menu
    perform(highlightItemSelector, with: historyMenuItems.first)
    if let item = itemToHighlight, !item.isHighlighted, items.contains(item) {
      perform(highlightItemSelector, with: item)
    } else {
      // Unhighlight current item.
      perform(highlightItemSelector, with: nil)
    }
  }
  
  private func clear(_ clipsToClear: [ClipRecord]) {
    for clip in clipsToClear {
      clip.menuItems.forEach(safeRemoveItem)
      
      if let removeIndex = clips.firstIndex(of: clip) {
        clips.remove(at: removeIndex)
      }
    }
    
    if let item = headOfQueueClip, clipsToClear.contains(item) {
      headOfQueueClip = nil
    }
  }
  
  private func appendMenuItem(_ item: NSMenuItem) {
    guard let historyEndItem = trailingSeparatorItem else { return }
    safeInsertItem(item, at: index(of: historyEndItem))
  }
  
  private func rebuildItemsAsNeeded() {
    let availableHistoryCount = clips.count
    let presentItemsCount = historyMenuItems.count / historyMenuItemsGroupCount
    
    let maxItems = queue.isOn ? max(maxMenuItems, queue.size) : maxMenuItems
    
    let maxAvailableItems = maxItems <= 0 || maxItems > availableHistoryCount ? availableHistoryCount : maxItems
    if presentItemsCount < maxAvailableItems {
      appendItemsUntilLimit(maxAvailableItems)
    } else if presentItemsCount > maxAvailableItems {
      removeItemsOverLimit(maxItems)
    }
  }
  
  private func removeItemsOverLimit(_ limit: Int) {
    var count = historyMenuItems.count / historyMenuItemsGroupCount
    for clip in clips.reversed() {
      if count <= limit {
        return
      }
      
      // if menu doesn't contains this item, skip it
      let menuItems = clip.menuItems.filter({ historyMenuItems.contains($0) })
      if menuItems.isEmpty {
        continue
      }
      
      menuItems.forEach(safeRemoveItem)
      count -= 1
    }
  }
  
  private func appendItemsUntilLimit(_ limit: Int) {
    var count = historyMenuItems.count / historyMenuItemsGroupCount
    for clip in clips {
      if count >= limit {
        return
      }
      
      // if menu contains this item already, skip it
      let menuItems = clip.menuItems.filter({ !historyMenuItems.contains($0) })
      if menuItems.isEmpty {
        continue
      }
      
      menuItems.forEach(appendMenuItem)
      if clip == headOfQueueClip {
        menuItems.forEach { $0.isHeadOfQueue = true }
      }
      count += 1
    }
  }
  
  private func buildMenuItemAlternates(_ item: ClipItem) -> [ClipMenuItem] {
    // (including the preview item) making the HistoryMenuItem subclasses unnecessary,
    guard let protoCopyItem = protoCopyItem, let protoReplayItem = protoReplayItem else {
      return []
    }
    
    var menuItems = [
      (protoCopyItem.copy() as! ClipMenuItem).configured(withItem: item),
      (protoReplayItem.copy() as! ClipMenuItem).configured(withItem: item) // distinguishForDebugging:true
    ]
    menuItems.sort(by: { !$0.isAlternate && $1.isAlternate })
    
    if usePopoverAnchors {
      guard let protoAnchorItem = protoAnchorItem else {
        return []
      }
      menuItems.append(protoAnchorItem.copy() as! ClipMenuItem)
    }
    
    assert(menuItems.count == historyMenuItemsGroupCount)
    
    return menuItems
  }
  
  private func clearRemovedItems() {
    let currentHistoryItems = history.all
    for clip in clips {
      if let historyItem = clip.item, !currentHistoryItems.contains(historyItem) {
        clip.menuItems.forEach(safeRemoveItem)
        
        if let removeIndex = clips.firstIndex(of: clip) {
          clips.remove(at: removeIndex)
        }
        
        if let item = headOfQueueClip, item == clip {
          headOfQueueClip = nil
        }
      }
    }
  }
  
  private func clearAllHistoryMenuItems() {
    guard let zerothHistoryHeaderItem = topAnchorItem ?? historyHeaderItem,
          let trailingSeparatorItem = trailingSeparatorItem else {
      return
    }
    assert(index(of: zerothHistoryHeaderItem) < index(of: trailingSeparatorItem))
    
    for index in (index(of: zerothHistoryHeaderItem) + 1 ..< index(of: trailingSeparatorItem)).reversed() {
      safeRemoveItem(at: index)
    }
    assert(historyMenuItems.isEmpty)
  }
  
  private func updateItemVisibility() {
    guard let historyHeaderItem = historyHeaderItem, let trailingSeparatorItem = trailingSeparatorItem else {
      return
    }
    let badgedMenuItemsSupported = if #available(macOS 14, *) { true } else { false }
    let promoteExtras = AppModel.allowPurchases && UserDefaults.standard.promoteExtras && badgedMenuItemsSupported
    if promoteExtras && promoteExtrasBadge == nil, #available(macOS 14, *) {
      promoteExtrasBadge = NSMenuItemBadge(string: NSLocalizedString("promoteextras_menu_badge", comment: ""))
    }
    
    let haveHistoryItems = !queue.isEmpty || (showsExpandedMenu && !clips.isEmpty)
    
    // Switch visibility of start vs replay menu item
    queueStartItem?.isVisible = !queue.isOn || queue.isReplaying // when on and replaying, show this though expect it will be disabled
    queueReplayItem?.isVisible = !queue.isEmpty && !queue.isReplaying
    
    // show advance menu item only when allowed
    queueAdvanceItem?.isVisible = !queue.isEmpty

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
    deleteItem?.isVisible = haveHistoryItems
    clearItem?.isVisible = haveHistoryItems
    
    // Visiblity of the history header and trailing separator
    // (the expanded menu means the search header and all of the history items)
    // hiding items with views not working well in macOS <= 14! remove view when hiding
    if removeViewToHideMenuItem {
      if !showsSearchHeader && historyHeaderItem.view != nil {
        historyHeaderViewCache = historyHeaderItem.view as? FilterFieldView
        historyHeaderItem.view = nil
      } else if showsSearchHeader && historyHeaderItem.view == nil {
        historyHeaderItem.view = historyHeaderViewCache
        historyHeaderViewCache = nil
      }
    }
    historyHeaderItem.isVisible = showsSearchHeader
    trailingSeparatorItem.isVisible = showsSearchHeader || haveHistoryItems
    
    // Show or hide the desired history items
    let zerothHistoryHeaderItem = topAnchorItem ?? historyHeaderItem
    let firstHistoryMenuItemIndex = index(of: zerothHistoryHeaderItem) + 1
    let endHistoryMenuItemIndex = index(of: trailingSeparatorItem)
    var remainingHistoryMenuItemIndex = firstHistoryMenuItemIndex
    
    // First queue items to always show when not filtering by a search term
    if !queue.isEmpty && !isFiltered {
      let endQueuedItemIndex = firstHistoryMenuItemIndex + historyMenuItemsGroupCount * queue.size
      
      for index in firstHistoryMenuItemIndex ..< endQueuedItemIndex {
        makeVisible(true, historyMenuItemAt: index)
      }
      
      remainingHistoryMenuItemIndex = endQueuedItemIndex
    }
    
    if remainingHistoryMenuItemIndex > endHistoryMenuItemIndex {
      os_log(.default, "range fail %d ..< %d, has topanchor: %d, first %d, end %d, remaining %d which might eq first + queue size %d * %d",
             remainingHistoryMenuItemIndex, endHistoryMenuItemIndex,
             topAnchorItem != nil ? 1 : 0, firstHistoryMenuItemIndex, endHistoryMenuItemIndex,
             remainingHistoryMenuItemIndex, queue.size, historyMenuItemsGroupCount)
      remainingHistoryMenuItemIndex = endHistoryMenuItemIndex
    }
    
    // Remaining history items hidden unless showing the expanded menu
    for index in remainingHistoryMenuItemIndex ..< endHistoryMenuItemIndex {
      makeVisible(showsExpandedMenu, historyMenuItemAt: index)
    }
  }
  
  private func makeVisible(_ visible: Bool, historyMenuItemAt index: Int) {
    guard let menuItem = item(at: index) else { return }
    if menuItem.keyEquivalentModifierMask.isEmpty {
      menuItem.isVisible = visible
    } else {
      menuItem.isVisibleAlternate = visible
    }
  }
  
  private func safeInsertItem(_ item: NSMenuItem, at index: Int) {
    guard !items.contains(item), index <= items.count else {
      return
    }
    
    sanityCheckIndexIsHistoryItemIndex(index, forInserting: true)
    
    insertItem(item, at: index)
  }
  
  private func safeRemoveItem(_ item: NSMenuItem) {
    guard items.contains(item) else {
      return
    }
    
    sanityCheckIndexIsHistoryItemIndex(index(of: item))
    
    removeItem(item)
  }
  
  private func safeRemoveItem(at index: Int) {
    guard index <= items.count else {
      return
    }
    
    sanityCheckIndexIsHistoryItemIndex(index)
    
    removeItem(at: index)
  }
  
  private func safeIndex(of item: NSMenuItem) -> Int? {
    let index = index(of: item)
    return index >= 0 ? index : nil
  }
  
  private func sanityCheckIndexIsHistoryItemIndex(_ i: Int, forInserting inserting: Bool = false) {
    if item(at: i) != nil, let historyHeaderItem, let trailingSeparatorItem {
      if i <= index(of: topAnchorItem ?? historyHeaderItem) {
        fatalError("sanityCheckIndex failure 1")
      }
      if i > index(of: trailingSeparatorItem) {
        fatalError("sanityCheckIndex failure 2")
      }
      if !inserting && i == index(of: trailingSeparatorItem) {
        fatalError("sanityCheckIndex failure 3")
      }
    }
  }
  
  private func boundsOfMenuItem(_ item: NSMenuItem, _ windowContentView: NSView) -> NSRect? {
    if !usePopoverAnchors {
      let windowRectInScreenCoordinates = windowContentView.accessibilityFrame()
      let menuItemRectInScreenCoordinates = item.accessibilityFrame()
      return NSRect(
        origin: NSPoint(
          x: menuItemRectInScreenCoordinates.origin.x - windowRectInScreenCoordinates.origin.x,
          y: menuItemRectInScreenCoordinates.origin.y - windowRectInScreenCoordinates.origin.y),
        size: menuItemRectInScreenCoordinates.size
      )
    } else {
      // assumes the last of a group of history items is the anchor
      guard let topAnchorView = topAnchorItem?.view, let item = item as? ClipMenuItem,
            let itemIndex = clips.firstIndex(where: { $0.menuItems.contains(item) }) else {
        return nil
      }
      let clip = clips[itemIndex]
      guard let previewView = clip.menuItems.last?.view else {
        return nil
      }
      
      var precedingView = topAnchorView
      for index in (0..<itemIndex).reversed() {
        // Check if anchor for this item is visible (it may be hidden by the search filter)
        if let view = clips[index].menuItems.last?.view, view.window != nil {
          precedingView = view
          break
        }
      }
      
      let bottomPoint = previewView.convert(
        NSPoint(x: previewView.bounds.minX, y: previewView.bounds.maxY),
        to: windowContentView
      )
      let topPoint = precedingView.convert(
        NSPoint(x: previewView.bounds.minX, y: precedingView.bounds.minY),
        to: windowContentView
      )
      
      let heightOfVisibleMenuItem = abs(topPoint.y - bottomPoint.y)
      return NSRect(
        origin: bottomPoint,
        size: NSSize(width: item.menu?.size.width ?? 0, height: heightOfVisibleMenuItem)
      )
    }
  }
  
  private func ensureInEventTrackingModeIfVisible(
    dispatchLater: Bool = false,
    block: @escaping () -> Void
  ) {
    if isVisible && (
      dispatchLater ||
      RunLoop.current != RunLoop.main ||
      RunLoop.current.currentMode != .eventTracking
    ) {
      RunLoop.main.perform(inModes: [.eventTracking], block: block)
    } else {
      block()
    }
  }
  
}
// swiftlint:enable type_body_length

// MARK: -

extension AppMenu {
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

// an isVisible property made logic more clear than with the isHidden property,
// eliminating many double negatives
// and isVisibleAlternate isolates differences between macOS14 and earlier
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
