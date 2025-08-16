//
//  AppModel.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-07-10.
//  Portions Copyright © 2025 Bananameter Labs. All rights reserved.
//
//  Based on Maccy.swift from the Maccy project
//  Portions Copyright © 2024 Alexey Rodionov. All rights reserved.
//

import AppKit
import KeyboardShortcuts
import Settings
import os.log
#if SPARKLE_UPDATES
import Sparkle
#endif

// swiftlint:disable type_body_length
class AppModel: NSObject {
  
  static var returnFocusToPreviousApp = true
  static var busy = false
  
  static var allowExpandedHistory = true
  static var allowFullyExpandedHistory = false
  static var allowHistorySearch = false
  static var allowReplayFromHistory = false
  static var allowReplayLastBatch = true
  static var allowPasteMultiple = false
  static var allowUndoCopy = false
  static var allowSavedBatches = false
  static var allowLastBatch = true
  
  static var allowDictinctStorageSize: Bool { Self.allowFullyExpandedHistory || Self.allowHistorySearch }
  static var effectiveMaxClips: Int {
    allowDictinctStorageSize ? UserDefaults.standard.historySize : UserDefaults.standard.maxMenuItems
  }
  static var effectiveMaxVisibleClips: Int {
    (allowDictinctStorageSize && UserDefaults.standard.maxMenuItems == 0) ? UserDefaults.standard.historySize
      : UserDefaults.standard.maxMenuItems
  }
  
  static var firstLaunch = false
  
  #if APP_STORE
  static var hasBoughtExtras = false
  static let allowPurchases = true
  #else
  static let allowPurchases = false
  #endif
  
  // Note:
  // I'm using `internal` to say: i wanted this to be `private` but code using this is in extension in other file
  // where no access modifier given, that means public to the whole module, ie. the default access also `internal`.
  // Given normal useage of `internal` it might make more sense to do this exactly the other way around,
  // however I want the "used in extension to this class" declarations to have a modifier to look similar to lines
  // with `private` and the "public to this module" declarations lines to look different.
  
  internal let menuIcon = MenuBarIcon()
  internal let about = About()
  internal let clipboard = Clipboard.shared
  internal let history = History()
  internal let alerts = Alerts()
  internal var menu: AppMenu!
  internal var menuController: MenuController!
  
  private var copyHotKey: CopyKeyboardShortcutHandler!
  private var pasteHotKey: PasteKeyboardShortcutHandler!
  private var startHotKey: StartKeyboardShortcutHandler!
  private var replayLastHotKey: ReplayLastKeyboardShortcutHandler!
  private var savedBatchHotKeys: Set<ReplaySavedKeyboardShortcutHandler> = []
  
  #if APP_STORE
  private let purchases = AppStorePurchases()
  private var promotionExpirationTimer: Timer?
  #endif
  #if SPARKLE_UPDATES
  private let updaterController = SPUStandardUpdaterController(updaterDelegate: nil, userDriverDelegate: nil)
  #endif
  internal var introWindowController = IntroWindowController()
  internal var licensesWindowController = LicensesWindowController()
  
  internal var queue: ClipboardQueue!
  internal var copyTimeoutTimer: DispatchSourceTimer?
  
  internal lazy var storageSettingsPaneViewController = StorageSettingsViewController()
  #if APP_STORE
  internal lazy var generalSettingsPaneViewController = GeneralSettingsViewController()
  internal lazy var settingsWindowController = SettingsWindowController(
    panes: [
      generalSettingsPaneViewController,
      AppearanceSettingsViewController(),
      storageSettingsPaneViewController,
      PurchaseSettingsViewController(purchases: purchases),
      IgnoreSettingsViewController(),
      AdvancedSettingsViewController()
    ]
  )
  #else
  internal lazy var settingsWindowController = SettingsWindowController(
    panes: [
      GeneralSettingsViewController(updater: updaterController.updater),
      AppearanceSettingsViewController(),
      storageSettingsPaneViewController,
      IgnoreSettingsViewController(),
      AdvancedSettingsViewController()
    ]
  )
  #endif
  
  private var clipboardCheckIntervalObserver: NSKeyValueObservation?
  private var enabledPasteboardTypesObserver: NSKeyValueObservation?
  private var ignoreEventsObserver: NSKeyValueObservation?
  private var imageHeightObserver: NSKeyValueObservation?
  private var maxTitleLengthObserver: NSKeyValueObservation?
  private var showSpecialSymbolsObserver: NSKeyValueObservation?
  private var maxMenuItemsObserver: NSKeyValueObservation?
  private var storageSizeObserver: NSKeyValueObservation?
  private var keepHistoryObserver: NSKeyValueObservation?
  private var keepHistoryObserver2: NSKeyValueObservation?
  private var statusItemConfigurationObserver: NSKeyValueObservation?
  private var statusItemVisibilityObserver: NSKeyValueObservation?
  
  enum PasteSeparator: Int, CaseIterable {
    // the popup menu in Alerts.nib must be kept in symc with these enum cases 
    case newline, doubleNewline, space, commaSpace
    var string: String {
      switch self {
      case .newline: "\n"
      case .doubleNewline: "\n\n"
      case .space: " "
      case .commaSpace: ", "
      }
    }
    static var validRawValue = 0 ..< allCases.count
  }
  
  // MARK: -
  
  override init() {
    super.init()
    
    // many things that follow must happen in a particular order
    
    UserDefaults.standard.register(defaults: [
      UserDefaults.Keys.enabledPasteboardTypes: UserDefaults.Values.enabledPasteboardTypes,
      UserDefaults.Keys.ignoredPasteboardTypes: UserDefaults.Values.ignoredPasteboardTypes,
      
      UserDefaults.Keys.clipboardCheckInterval: UserDefaults.Values.clipboardCheckInterval,
      UserDefaults.Keys.imageMaxHeight: UserDefaults.Values.imageMaxHeight,
      UserDefaults.Keys.maxMenuItems: UserDefaults.Values.maxMenuItems,
      UserDefaults.Keys.maxTitleLength: UserDefaults.Values.maxTitleLength,
      UserDefaults.Keys.previewDelay: UserDefaults.Values.previewDelay,
      UserDefaults.Keys.searchMode: UserDefaults.Values.searchMode,
      UserDefaults.Keys.showInStatusBar: UserDefaults.Values.showInStatusBar,
      UserDefaults.Keys.showSpecialSymbols: UserDefaults.Values.showSpecialSymbols,
      UserDefaults.Keys.historySize: UserDefaults.Values.historySize,
      UserDefaults.Keys.highlightMatch: UserDefaults.Values.highlightMatch
    ])
    
    migrateUserDefaults()
    
    // history, queue, menu, statusicon
    if UserDefaults.standard.keepHistory {
      history.loadList()
      clipboard.start()
    }
    
    queue = ClipboardQueue(clipboard: clipboard, history: history)
    
    menu = AppMenu.load(withHistory: history, queue: queue, owner: self)
    
    menuIcon.enableRemoval(true)
    menuIcon.isVisible = true
    updateMenuIconEnabledness()
    if UserDefaults.standard.legacyFocusTechnique {
      menuController = MenuController(menu, menuIcon.statusItem)
    } else {
      menuIcon.setDirectOpen(toMenu: menu, menu.menuBarShouldOpen)
    }
    
    // hotkey and clipboard callbacks
    copyHotKey = CopyKeyboardShortcutHandler(queuedCopy)
    pasteHotKey = PasteKeyboardShortcutHandler(queuedPaste)
    startHotKey = StartKeyboardShortcutHandler(startQueueMode)
    replayLastHotKey = ReplayLastKeyboardShortcutHandler(replayLastBatch)
    restoreSavedBatchHotKeys()
    
    initializeObservers()
    
    clipboard.onNewCopy(clipboardChanged) 
    
    // Bonus features may get toggled from off to on after a delay to access the app-store receipt,
    // at that point `menu.buildDynamicItems()` gets automatically called again. If that were to
    // happen immediately instead then the one below is redundant, but no harm. 
    loadFeatureFlags()
    
    // This potential debug code to inspect or log whatever currently called after almost everything
    // is setup, except maybe bonus feature flags after receipt access completes. However, where this
    // is called can be moved up to run earlier.
    #if DEBUG
    debugLaunchState()
    #endif
    
    // launch initial user interface
    menu.buildDynamicItems()
    //configureMenuShortcuts()
    
    // The first `menu.prepareToOpen()` can take a while so do it early instead of when the menu
    // is first clicked on. To not delay the intro window from opening, delay this call.
    // Also by making this delay not super-short, hopefully loading the app store receipt has
    // happened and the re-do `buildDynamicItems()` has already occurred as well.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      self.menu.prepareToOpen()
    }
    
    if !UserDefaults.standard.completedIntro {
      showIntro(self)
    } else if !hasAccessibilityPermissionBeenGranted() {
      showIntroAtPermissionPage()
    } else if UserDefaults.standard.keepHistoryChoicePending {
      // expect user migrating from 1.0 won't fall into cases above, get here & really see this page   
      showIntroAtHistoryUpdatePage()
    }
    
    // this instantiates the settings window, but it's not not initially visible
    settingsWindowController.window?.collectionBehavior.formUnion(.moveToActiveSpace)
  }
  
  deinit {
    clipboardCheckIntervalObserver?.invalidate()
    enabledPasteboardTypesObserver?.invalidate()
    ignoreEventsObserver?.invalidate()
    imageHeightObserver?.invalidate()
    maxTitleLengthObserver?.invalidate()
    showSpecialSymbolsObserver?.invalidate()
    maxMenuItemsObserver?.invalidate()
    storageSizeObserver?.invalidate()
    keepHistoryObserver?.invalidate()
    keepHistoryObserver2?.invalidate()
    statusItemConfigurationObserver?.invalidate()
    statusItemVisibilityObserver?.invalidate()
    
    menuIcon.cancelBlinkTimer()
    #if APP_STORE
    purchases.finish()
    #endif
  }

  func terminate() {
    if UserDefaults.standard.clearOnQuit {
      clearHistory(suppressClearAlert: true)
    }
  }
  
  func wasReopened() {
    // if the user has chosen to hide the menu bar icon when not in batch mode then
    // open the Settings window whenever the application icon is double clicked again
    if !UserDefaults.standard.showInStatusBar {
      showSettings(selectingPane: .general)
    }
  }
  
  internal func takeFocus() {
    if UserDefaults.standard.legacyFocusTechnique {
      Self.returnFocusToPreviousApp = false
    } else {
      if !UserDefaults.standard.avoidTakingFocus {
        NSApp.activate(ignoringOtherApps: true)
      }
    }
  }
  
  internal func returnFocus() {
    if UserDefaults.standard.legacyFocusTechnique {
      Self.returnFocusToPreviousApp = true
    } else {
      if !UserDefaults.standard.avoidTakingFocus {
        let visibleWindows = NSApp.windows.filter { $0.isVisible && $0.className != NSApp.statusBarWindow?.className }
        if AppModel.returnFocusToPreviousApp && visibleWindows.count == 0 {
          NSApp.hide(self)
        }
      }
    }
  }
  
  private func migrateUserDefaults() {
    let userDefaults = UserDefaults.standard
    
    Self.firstLaunch = userDefaults.dictionaryRepresentation().isEmpty
    if Self.firstLaunch {
      // set something in userdefaults to know on next launch it's not the first
      userDefaults.completedIntro = false
    }
    
    if userDefaults.object(forKey: UserDefaults.Keys.keepHistoryChoicePending) == nil {
      if Self.firstLaunch {
        userDefaults.keepHistory = false // deliberately omitted from registered defaults above
        userDefaults.keepHistoryChoicePending = false
      } else {
        // this 1.1 flag unset even though not first launch must mean migrating from 1.0
        // offer to upgrade to new history-less default, but until they do, keep history on
        userDefaults.keepHistory = true
        userDefaults.keepHistoryChoicePending = true
        os_log(.info, "user must confirm history remaining on, or migrate to history off")
      } 
    }
    
    #if APP_STORE
    migrateUserDefaultsForAppStore()
    #endif
  }
  
  #if DEBUG
  func debugLaunchState() {
    nop() // put breakpoint here maybe doing "p queue.dump"
  }
  #endif
  
  // MARK: - dynamic keyboard shortcuts for saved batches
  
  // Called hotkeys here to avoid confusion with the tpye KeyboardShortcuts.Shortcut
  // which is only a representation of the key combonation unassociated with the
  // associated name str and setup hander, as in a statically defined KeyboardShortcuts.Name
  // We also pass around name strings, so refer to KeyboardShortcuts.Name instead as
  // a "hotkey definition" or "shortcut definition".
  // We setup this association even when the shortcut is nil to reserver its unique
  // name string and prepare for the user adding a key combination at any time.  
  typealias HotKeyShortcut = KeyboardShortcuts.Shortcut
  typealias HotKeyDefinition = KeyboardShortcuts.Name
  
  private func restoreSavedBatchHotKeys() {
    savedBatchHotKeys = []
    for batch in Batch.saved {
      guard let name = batch.fullname, !name.isEmpty else {
        continue
      }
      let hotKeyDefinition = defineHotKey(named: name, withShortcut: batch.keyShortcut)
      registerHotKeyHandler(to: hotKeyDefinition, forBatch: batch)
    }
  }
  
  private func defineHotKey(named name: String, withShortcut shortcut: HotKeyShortcut?) -> HotKeyDefinition {
    let hotKeyDefinition = HotKeyDefinition(name)
    KeyboardShortcuts.setShortcut(shortcut, for: hotKeyDefinition)
    return hotKeyDefinition
  }
  
  private func registerHotKeyHandler(to hotKeyDefinition: HotKeyDefinition, forBatch batch: Batch) {
    if savedBatchHotKeys.contains(where: { $0.name == hotKeyDefinition }) {
      return
    }
    let handler = ReplaySavedKeyboardShortcutHandler(for: hotKeyDefinition, batch: batch, replaySavedBatch)
    savedBatchHotKeys.insert(handler)
  }
  
  private func unregisterHotKeyDefinition(_ oldDefinition: HotKeyDefinition) {
    KeyboardShortcuts.setShortcut(nil, for: oldDefinition)
    if let oldHandler = savedBatchHotKeys.first(where: { $0.name == oldDefinition }) {
      savedBatchHotKeys.remove(oldHandler)
    }
  }
  
  // these funtions available to call from elsewhere in AppModel
  
  internal func registerHotKeyHandler(forBatch batch: Batch) {
    guard let name = batch.fullname, !name.isEmpty else {
      return
    }
    registerHotKeyHandler(to: HotKeyDefinition(name), forBatch: batch)
  }
  
  internal func unregisterHotKeyDefinition(forBatch batch: Batch) {
    guard let name = batch.fullname, !name.isEmpty else {
      return
    }
    unregisterHotKeyDefinition(HotKeyDefinition(name))
  }
  
  internal func prohibitedNewBatchNames() -> Set<String> {
    // hotkeys defs must be unique, since using batch name directly as hotkey defs they must be unique too
    // empty strings shouldn't be allowed either fyi
    var savedBatchNames = savedBatchHotKeys.map { $0.name }
    savedBatchNames.append(contentsOf: [.queueStart, .queuedCopy, .queuedPaste, .queueReplay ])
    return Set(savedBatchNames.map { $0.rawValue })
  }
  
  @discardableResult
  internal func replaceRegisteredHotKey(forRenamedBatch batch: Batch) -> Bool {
    guard let newName = batch.fullname, !newName.isEmpty else {
      return false
    }
    guard savedBatchHotKeys.contains(where: { $0.nameString == newName }) == false else {
      return false
    }
    
    // shortcut definitions aren't meant to be static, so some hoops to jump through
    // to remove the old one dynamically
    var reuseShortcut: HotKeyShortcut? = nil
    
    if let oldHandler = savedBatchHotKeys.first(where: { $0.batch === batch }) {
      reuseShortcut = KeyboardShortcuts.getShortcut(for: oldHandler.name)
      KeyboardShortcuts.setShortcut(nil, for: oldHandler.name) // removes entry from UserDefaults
      savedBatchHotKeys.remove(oldHandler)
      
      // TODO: replace with `KeyboardShortcuts.removeHandler(for: oldHandler.name)`
      // when the next version of KeyboardShortcuts available
      KeyboardShortcuts.removeAllHandlers()
      savedBatchHotKeys.forEach {
        $0.installHandler()
      }
    }
    
    let newDefinition = defineHotKey(named: newName, withShortcut: reuseShortcut)
    registerHotKeyHandler(to: newDefinition, forBatch: batch)
    return true
  }
  
  // MARK: - features & purchases
  
  private func loadFeatureFlags() {
    #if BONUS_FEATUES_ON
    setFeatureFlags(givenPurchase: true)
    #endif
    #if APP_STORE && BONUS_FEATUES_ON
    Self.hasBoughtExtras = true
    #endif
    #if APP_STORE
    purchases.start(withObserver: self) { [weak self] _, update in
      self?.purchasesUpdated(update)
    }
    #endif
  }
  
  private func setFeatureFlags(givenPurchase hasPurchased: Bool) {
    Self.allowFullyExpandedHistory = hasPurchased
    Self.allowHistorySearch = hasPurchased
    Self.allowReplayFromHistory = hasPurchased
    Self.allowPasteMultiple = hasPurchased
    Self.allowUndoCopy = hasPurchased
    Self.allowSavedBatches = hasPurchased
    //Self.allowLastBatch = hasPurchased // putting this in the normal version
  }
  
  func hasAccessibilityPermissionBeenGranted() -> Bool {
    AXIsProcessTrustedWithOptions(nil)
  }
  
  #if APP_STORE
  
  private func migrateUserDefaultsForAppStore() {
    #if !BONUS_FEATUES_ON
    let userDefaults = UserDefaults.standard

    if Self.firstLaunch {
      // defaults defined here in code are to promote extras temporarily
      userDefaults.promoteExtras = true
      userDefaults.promoteExtrasExpires = true
      
      if let expiration = promoteExtrasExpirationDate(), let date = expiration.date {
        setPromoteExtrasExpirationTimer(to: date)
        userDefaults.promoteExtrasExpiration = expiration
      } else {
        // cannot set the timer, don't promote the bonus features after all
        userDefaults.promoteExtras = false
      }
      
    } else if userDefaults.promoteExtras && userDefaults.promoteExtrasExpires {
      if let restoredExpiration = userDefaults.promoteExtrasExpiration,
         let restoredDate = restoredExpiration.date, restoredDate.timeIntervalSinceNow > 0 // ie. date is in the future
      {
        setPromoteExtrasExpirationTimer(to: restoredDate)
      } else {
        // already passed the expiration, cancel promoting the bonus features
        userDefaults.promoteExtras = false
      }
    }
    #endif
  }
  
  func setPromoteExtrasExpirationTimer(on: Bool) {
    if on {
      // first try re-using an existing expiration date, only picking a
      // new date if the existing one is in the past
      if let reusedExpiration = UserDefaults.standard.promoteExtrasExpiration,
         let reusedDate = reusedExpiration.date, reusedDate.timeIntervalSinceNow > 0 {// ie. date is in the future
        setPromoteExtrasExpirationTimer(to: reusedDate)
      }
      else if let newExpiration = promoteExtrasExpirationDate(), let date = newExpiration.date {
        setPromoteExtrasExpirationTimer(to: date)
        UserDefaults.standard.promoteExtrasExpiration = newExpiration
      }
      // otherwise failed to pick a date to set the timer with, expiration won't occur
    } else {
      clearPromoteExtrasExpirationTimer()
    }
  }
  
  private func setPromoteExtrasExpirationTimer(to date: Date) {
    guard date.timeIntervalSinceNow > 0 else { // ie. date is in the future
      // can't set the timer to this date, expiration won't occur
      return
    }
    // useful, tricky breakpoint here: setting exipiry timer to @LocalShortDateFormatter().string(from:date)@
    
    promotionExpirationTimer = Timer.scheduledTimer(withTimeInterval: date.timeIntervalSinceNow, repeats: false) { [weak self] _ in
      self?.promotionExpirationTimer = nil
      UserDefaults.standard.promoteExtras = false
      DispatchQueue.main.async {
        self?.generalSettingsPaneViewController.promoteExtrasStateChanged()
      }
    }
  }
  
  private func clearPromoteExtrasExpirationTimer() {
    promotionExpirationTimer?.invalidate()
    promotionExpirationTimer = nil
  }
  
  private func promoteExtrasExpirationDate() -> DateComponents? {
    let calendar = Calendar(identifier: .gregorian)
    #if DEBUG
    guard let minuteFromNow = calendar.date(byAdding: .minute, value: 1, to: Date()) else {
      return nil
    }
    return calendar.dateComponents([.year, .month, .day, .hour, .minute, .calendar], from: minuteFromNow)
    #else
    guard let nextWeek = calendar.date(byAdding: .day, value: 7, to: Date()) else {
      return nil
    }
    let midnightNextWeek = calendar.startOfDay(for: nextWeek)
    return calendar.dateComponents([.year, .month, .day, .hour, .minute, .calendar], from: midnightNextWeek)
    #endif
  }
  
  class LocalShortDateFormatter: DateFormatter, @unchecked Sendable { // used by logging breakpoint in setPromoteExtrasExpirationTimer
    override init() { super.init(); dateStyle = .short; timeStyle = .short }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  }
  
  private func purchasesUpdated(_ update: AppStorePurchases.ObservationUpdate) {
    #if !BONUS_FEATUES_ON
    let alreadyHadExtras = Self.hasBoughtExtras
    
    setFeatureFlags(givenPurchase: purchases.hasBoughtExtras)
    Self.hasBoughtExtras = purchases.hasBoughtExtras
    
    if purchases.hasBoughtExtras {
      clearPromoteExtrasExpirationTimer()
      UserDefaults.standard.promoteExtras = false
      UserDefaults.standard.promoteExtrasExpiration = nil
    }
    
    if Self.hasBoughtExtras != alreadyHadExtras { // in most cases unnecessary, but just be sure
      self.history.trim()
      self.menu.buildDynamicItems()
    }
    #endif
  }
  
  #endif // APP_STORE
  
  // MARK: - observations
  
  // Non-history items in the cleepp menu are defined in a nib file instead of programmatically
  // (the best code is no code), action methods for those items now live in this class,
  // defined in a class extension AppModel+Actions. Also history menu item subclasses no longer exist,
  // the actions for those are also defined in the extension, and other "business logic" for the
  // queueing feature.
  
  func historySettingsInconsistent() -> Bool {
    // this is when there are items in history even though the v1.1 keep-history settings
    // are at their defaults that indicate it should be empty
    return history.count > 0 && !UserDefaults.standard.keepHistory && !UserDefaults.standard.saveClipsAcrossDisabledHistory
  }
  
  private func updateMenuIconEnabledness() {
    menuIcon.isEnabled = !(UserDefaults.standard.ignoreEvents || UserDefaults.standard.enabledPasteboardTypes.isEmpty)
  }
  
  func updateSavingHistory(_ newKeepHistoryValue: Bool) {
    if newKeepHistoryValue {
      UserDefaults.standard.keepHistory = true
      history.loadList()
      clipboard.restart()
      menu.buildDynamicItems()
    } else if history.count == 0 { // turn off history but don't need to ask about retaining data
      UserDefaults.standard.keepHistory = false
      history.offloadList()
      clipboard.stop()
      menu.buildDynamicItems()
    } else if UserDefaults.standard.supressSaveClipsAlert {
      UserDefaults.standard.keepHistory = false
      if !UserDefaults.standard.saveClipsAcrossDisabledHistory {
        history.clearHistory()
      }
      history.offloadList()
      clipboard.stop()
      menu.buildDynamicItems()
    } else {
      takeFocus()
      
      alerts.withDisableHistoryConfirmationAlert { [weak self] confirm, retainDB, dontAskAgain in
        guard let self = self else { return }
        if confirm {
          UserDefaults.standard.keepHistory = false
          
          UserDefaults.standard.saveClipsAcrossDisabledHistory = retainDB
          if dontAskAgain {
            UserDefaults.standard.supressSaveClipsAlert = true
          }
          
          if !retainDB {
            history.clearHistory()
          }
          history.offloadList()
          clipboard.stop()
          menu.buildDynamicItems()
          
        } else {
          UserDefaults.standard.keepHistory = true
        }
        
        returnFocus()
      }
      
    }
  }
  
  private func initializeObservers() {
    clipboardCheckIntervalObserver = UserDefaults.standard.observe(\.clipboardCheckInterval, options: .old) { [weak self] _, change in
      guard let self = self else { return }
      if let newValue = change.newValue, newValue == UserDefaults.standard.clipboardCheckInterval { return } 
      clipboard.restart()
    }
    enabledPasteboardTypesObserver = UserDefaults.standard.observe(\.enabledPasteboardTypes, options: []) { [weak self] _, _ in
      guard let self = self else { return }
      updateMenuIconEnabledness()
    }
    ignoreEventsObserver = UserDefaults.standard.observe(\.ignoreEvents, options: []) { [weak self] _, _ in
      guard let self = self else { return }
      updateMenuIconEnabledness()
    }
    imageHeightObserver = UserDefaults.standard.observe(\.imageMaxHeight, options: .old) { [weak self] _, change in
      guard let self = self else { return }
      if let newValue = change.newValue, newValue == UserDefaults.standard.imageMaxHeight { return } 
      menu.resizeImageMenuItems()
    }
    maxTitleLengthObserver = UserDefaults.standard.observe(\.maxTitleLength, options: .old) { [weak self] _, change in
      guard let self = self else { return }
      if let newValue = change.newValue, newValue == UserDefaults.standard.maxTitleLength { return } 
      menu.regenerateMenuItemTitles()
      CoreDataManager.shared.saveContext()
    }
    showSpecialSymbolsObserver = UserDefaults.standard.observe(\.showSpecialSymbols, options: .old) { [weak self] _, change in
      guard let self = self else { return }
      if let newValue = change.newValue, newValue == UserDefaults.standard.showSpecialSymbols { return } 
      self.menu.regenerateMenuItemTitles()
      CoreDataManager.shared.saveContext()
      self.menu.buildDynamicItems()
    }
    maxMenuItemsObserver = UserDefaults.standard.observe(\.maxMenuItems, options: .old) { [weak self] _, change in
      guard let self = self else { return }
      if let newValue = change.newValue, newValue == UserDefaults.standard.maxMenuItems { return }
      if queue.isEmpty { // don't trylu trim when using queue, possible for there to be more than the max items queued
        history.trim(to: Self.effectiveMaxClips)
        menu.buildDynamicItems()
        CoreDataManager.shared.saveContext()
      }
      menu.buildDynamicItems()
    }
    storageSizeObserver = UserDefaults.standard.observe(\.historySize, options: .old) { [weak self] _, change in
      guard let self = self else { return }
      if let newValue = change.newValue, newValue == UserDefaults.standard.historySize { return }
      if queue.isEmpty { // don't trylu trim when using queue, possible for there to be more than the max items queued
        history.trim(to: Self.effectiveMaxClips)
        CoreDataManager.shared.saveContext()
      }
      menu.buildDynamicItems()
    }
    keepHistoryObserver = storageSettingsPaneViewController.observe(\.keepHistoryChange, options: .new) { [weak self] _, change in
      // old value of the flag is ephemeral, only care if its different than `keepHistory`
      guard let self = self else { return }
      //print("switch observer, new = \(change.newValue == nil ? "nil" : String(describing: change.newValue!)), keepHistory = \(UserDefaults.standard.keepHistory)")
      guard let newValue = change.newValue, newValue != UserDefaults.standard.keepHistory else { return }
      updateSavingHistory(newValue)
    }
    keepHistoryObserver2 = introWindowController.observe(\.viewController.keepHistoryChange, options: .new) { [weak self] _, change in
      // old value of the flag is ephemeral, only care if its different than `keepHistory`
      guard let self = self else { return }
      //print("switch observer, new = \(change.newValue == nil ? "nil" : String(describing: change.newValue!)), keepHistory = \(UserDefaults.standard.keepHistory)")
      guard let newValue = change.newValue, newValue != UserDefaults.standard.keepHistory else { return }
      updateSavingHistory(newValue)
    }
    // note: only code in this class should be changing UserDefaults.standard.keepHistory directly
    #if FALSE
    statusItemConfigurationObserver = UserDefaults.standard.observe(\.showInStatusBar, options: .old) { [weak self] _, change in
      guard let self = self else { return }
      if let newValue = change.newValue, newValue == UserDefaults.standard.showInStatusBar { return }
      if self.statusItem.isVisible != change.newValue! {
        self.statusItem.isVisible = change.newValue!
      }
    }
    statusItemVisibilityObserver = observe(\.statusItem.isVisible, options: .old) { [weak self] _, change in
      guard let self = self else { return }
      if let newValue = change.newValue, newValue == UserDefaults.standard.isVisible { return }
      if UserDefaults.standard.showInStatusBar != change.newValue! {
        UserDefaults.standard.showInStatusBar = change.newValue!
      }
    }
    #endif
  }
  
}
// swiftlint:enable type_body_length

func nop() { }
func dontWarnUnused(_ x: Any) { }
