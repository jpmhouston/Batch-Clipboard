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

// swiftlint:disable file_length
import AppKit
import KeyboardShortcuts
import Settings
import os.log
#if SPARKLE_UPDATES
import Sparkle
#endif

class AppModel: NSObject {
  
  static var returnFocusToPreviousApp = true
  static var busy = false
  
  static var allowFullyExpandedHistory = false
  static var allowHistorySearch = false
  static var allowReplayFromHistory = false
  static var allowReplayLastBatch = true
  static var allowPasteMultiple = false
  static var allowUndoCopy = false
  static var allowSavedBatches = false
  static var allowRepeatingBatch = false
  // always include these features:
  static var allowMenuHiding = true
  static var allowExpandedHistory = true
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
  static let hasBoughtExtras = false
  static let allowPurchases = false
  #endif
  
  // Note:
  // I'm using `internal` to say: i wanted this to be `private` but code using this is in extension in other file
  // where no access modifier given, that means public to the whole module, ie. the default access also `internal`.
  // Given normal useage of `internal` it might make more sense to do this exactly the other way around,
  // however I want the "used in extension to this class" declarations to have a modifier to look similar to lines
  // with `private` and the "public to this module" declarations lines to look different.
  
  internal let menuIcon = MenuBarIcon()
  internal let clipboard = Clipboard.shared
  internal let history = History()
  internal let alerts = Alerts()
  internal var menu: AppMenu!
  internal var menuController: MenuController!
  
  private var copyHotKey: CopyKeyboardShortcutHandler!
  private var pasteHotKey: PasteKeyboardShortcutHandler!
  private var pasteMultipleHotKey: PasteMultipleKeyboardShortcutHandler!
  private var startHotKey: StartKeyboardShortcutHandler!
  private var startWithCurrentHotKey: StartWithCurrentKeyboardShortcutHandler!
  private var replayLastHotKey: ReplayLastKeyboardShortcutHandler!
  private var stackCopyHoyKey: StackCopyKeyboardShortcutHandler!
  private var savedBatchHotKeys: Set<ReplaySavedKeyboardShortcutHandler> = []
  
  #if APP_STORE
  private let purchases = AppStorePurchases()
  private var promotionExpirationTimer: DispatchSourceTimer?
  #endif
  #if SPARKLE_UPDATES
  lazy var sparkleDelegate = SparkleDelegate(self)
  lazy var updaterController = SPUStandardUpdaterController(updaterDelegate: self.sparkleDelegate,
                                                            userDriverDelegate: self.sparkleDelegate)
  #endif
  internal var introWindowController = IntroWindowController()
  internal var introWindowOpen = false
  internal var licensesWindowController = LicensesWindowController()
  internal var licensesWindowOpen = false
  
  internal var queue: ClipboardQueue!
  internal var stack: ClipboardStack!
  internal var copyTimeoutTimer: DispatchSourceTimer?
  internal var hideMenuPollingTimer: DispatchSourceTimer?
  internal var hideMenuOnNextIteration = false
  
  internal var settingsWindowOpen = false
  internal var settingsFirstOpen = true
  internal lazy var storageSettingsPaneViewController = StorageSettingsViewController()
  #if APP_STORE
  internal lazy var generalSettingsPaneViewController = GeneralSettingsViewController()
  internal lazy var settingsWindowController = SettingsWindowController(
    panes: [
      AboutSettingsViewController(),
      generalSettingsPaneViewController,
      KeyboardSettingsViewController(),
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
      AboutSettingsViewController(),
      GeneralSettingsViewController(updater: updaterController.updater),
      KeyboardSettingsViewController(),
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
  private var menuHidingObserver: NSKeyValueObservation?
  private var showsInDockObserver: NSKeyValueObservation?
  private var settingsClosedObserver: NSObjectProtocol?
  private var introClosedObserver: NSObjectProtocol?
  private var licensesClosedObserver: NSObjectProtocol?
  
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
      UserDefaults.Keys.showSpecialSymbols: UserDefaults.Values.showSpecialSymbols,
      UserDefaults.Keys.historySize: UserDefaults.Values.historySize,
      UserDefaults.Keys.highlightMatch: UserDefaults.Values.highlightMatch
    ])
    
    migrateUserDefaults()
    
    applyShowInDockSetting() // not sure if its important that this is called early
    
    // history, queue, menu, statusicon
    if UserDefaults.standard.keepHistory {
      history.loadList()
      clipboard.start()
    }
    
    queue = ClipboardQueue(clipboard: clipboard, history: history)
    stack = ClipboardStack(clipboard: clipboard, history: history)
    
    menu = AppMenu.load(withHistory: history, queue: queue, owner: self)
    
    menuIcon.isVisible = true
    menuIcon.enableRemoval(true, wasRemoved: menuIconWasRemoved)
    updateMenuIconEnabledness()
    if UserDefaults.standard.legacyFocusTechnique {
      menuController = MenuController(menu, menuIcon.statusItem)
    } else {
      menuIcon.setDirectOpen(toMenu: menu, menu.menuBarShouldOpen)
    }
    
    // hotkey and clipboard callbacks
    copyHotKey = CopyKeyboardShortcutHandler(queuedCopy)
    pasteHotKey = PasteKeyboardShortcutHandler(queuedPaste)
    pasteMultipleHotKey = PasteMultipleKeyboardShortcutHandler(queuedPasteMultiple)
    startHotKey = StartKeyboardShortcutHandler(startQueueMode)
    startWithCurrentHotKey = StartWithCurrentKeyboardShortcutHandler(startQueueModeWithCurrentClip)
    replayLastHotKey = ReplayLastKeyboardShortcutHandler(replayLastBatch)
    stackCopyHoyKey = StackCopyKeyboardShortcutHandler(stackCopy)
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
    
    // The first `menu.prepareToOpen()` can take a while so do it early instead of when the menu
    // is first clicked on. To not delay the intro window from opening, delay this call.
    // Also by making this delay not super-short, hopefully loading the app store receipt has
    // happened and the re-do `buildDynamicItems()` has already occurred as well.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      self.menu.prepareToOpen()
    }
    
    if !UserDefaults.standard.completedIntro {
      showIntro(self)
      ensureMenuIconVisible(pollingForWindowsToClose: true)
    } else if !hasAccessibilityPermissionBeenGranted() {
      showIntroAtPermissionPage()
      ensureMenuIconVisible(pollingForWindowsToClose: true)
    } else if UserDefaults.standard.keepHistoryChoicePending {
      // expect user migrating from 1.0 won't fall into cases above, get here & really see this page   
      showIntroAtHistoryUpdatePage()
      ensureMenuIconVisible(pollingForWindowsToClose: true)
    } else {
      letMenuIconAutoHide()
    }
    
    // this instantiates the settings window, but it's not initially visible
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
    menuHidingObserver?.invalidate()
    removeNotificationObserver(&settingsClosedObserver)
    removeNotificationObserver(&introClosedObserver)
    removeNotificationObserver(&licensesClosedObserver)
    
    menuIcon.cancelBlinkTimer()
    #if APP_STORE
    purchases.finish()
    #endif
  }
  
  func terminate() {
    if UserDefaults.standard.clearOnQuit {
      clearHistory(clipboardIncluded: UserDefaults.standard.clearSystemClipboard, interactive: false)
    }
  }
  
  func wasActvated() {
    // when app switched to the foreground enure the menu is made visible then switch back to the
    // previously frontmost app
    // (if icon indeed dbl-clicked then wasReopened below will be called **either beofre or after**)
    ensureMenuIconVisible(pollingForWindowsToClose: true)
    
    // sometimes when wasReopened below opened settings window the app would still end up hidden
    // some kind of race between takeFocus activating app and returnFocus hiding it :/
    // best fix found: defer hiding so other code that might open a window has a chance to run first
    // (if menu or a window has opened prevents returnFocus from hiding the app)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
      self?.returnFocus() 
    }
  }
  
  func wasReopened() {
    // when app icon dbl-clicked or clicked in dock, optionally open settings if shift pressed or
    // start queue if that option is set (wasActvated may have already been called to reveal the
    // potentially hidden menu icon, or may even be called afterward .. must behave well in any case and any order)
    ensureMenuIconVisible(pollingForWindowsToClose: true) // in case wasActvated not called, maybe not needed 
    
    let modifierFlags = NSEvent.modifierFlags
    let modifierPressed = modifierFlags.contains(.shift) || modifierFlags.contains(.option)
    if UserDefaults.standard.relaunchingStartsBatch && !modifierPressed {
      // although if that setting is on, start queue mode instead
      startQueueMode() // assume this short-circuits nicely if queue already started
      stopPollingToRehideMenuIcon()
    } else if modifierPressed {
      showSettings(selectingPane: .general)
    } else {
      returnFocus()
    }
  }
  
  internal func applyShowInDockSetting() {
    //showsInDock = UserDefaults.standard.showsInDock
    NSApp.setActivationPolicy(UserDefaults.standard.showsInDock ? .regular : .accessory)
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
        if AppModel.returnFocusToPreviousApp && !anyAppWindowsOpen() {
          NSApp.hide(self)
        }
      }
    }
  }
  
  internal func ensureMenuIconVisible(pollingForWindowsToClose poll: Bool = false) {
    if !menuIcon.isVisible {
      menuIcon.isVisible = true
    }
    if Self.allowMenuHiding && UserDefaults.standard.menuHiddenWhenInactive {
      if poll {
        startPollingToRehideMenuIcon()
      } else {
        stopPollingToRehideMenuIcon()
      }
    }
  }
  
  internal func letMenuIconAutoHide() {
    if Self.allowMenuHiding && UserDefaults.standard.menuHiddenWhenInactive && menuIcon.isVisible && inOffState {
      startPollingToRehideMenuIcon()
    }
  }
  
  private func anyAppWindowsOpen() -> Bool {
    // Was using inherited Maccy code to tell if any windows, including the menu, are open,
    // specifically omitting a hidden window for the status item (with an undocumented class NSStatusItemWindow)
    // however isVisible also returns false when the app is hidden, not helpful.
    //  return NSApp.windows.filter { $0.isVisible && $0.className != NSApp.statusBarWindow?.className }
    // Trying to engineer each window to get removed from the NSApp.windows when they're closed didn't work.
    // Now track our windows being opened & closed manually (alerts we don't need to worry about, each are modal)
    menu.isOpen || settingsWindowOpen || introWindowOpen || licensesWindowOpen
    // menu @menu.isOpen@, settings @settingsWindowOpen@, intro @introWindowOpen@, licenses @licensesWindowOpen@
  }
  
  internal func settingsWindowWasOpened() {
    if settingsWindowController.isWindowLoaded, let window = settingsWindowController.window {
      settingsWindowOpen = true
      addSettingsWindowCloseObserver(window)
    }
    // No `else` because we know the settings window is instantiated early (to set moveToActiveSpace on the
    // window that otherwise is completely defined in the Settings package). Maybe add an `else { assert() }`?
  }
  
  internal func introWindowWasOpened() {
    if introWindowController.isWindowLoaded, let window = introWindowController.window {
      introWindowOpen = true
      addIntroWindowCloseObserver(window)
    } else {
      nop() // good place for breakppint: introWindowWasOpened called but window nil, delaying
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
        guard let self = self else { return }
        introWindowOpen = true
        if introWindowController.isWindowLoaded, let window = introWindowController.window {
          addIntroWindowCloseObserver(window)
        }
      }
    }
  }
  
  internal func licensesWindowWasOpened() {
    if licensesWindowController.isWindowLoaded, let window = licensesWindowController.window {
      introWindowOpen = true
      addLicensesWindowCloseObserver(window)
    } else {
      nop() // good place for breakppint: licensesWindowWasOpened called but window nil, delaying
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
        guard let self = self else { return }
        licensesWindowOpen = true
        if licensesWindowController.isWindowLoaded, let window = licensesWindowController.window {
          addLicensesWindowCloseObserver(window)
        }
      }
    }
  }
  
  private func migrateUserDefaults() {
    let userDefaults = UserDefaults.standard
    
    Self.firstLaunch = userDefaults.object(forKey: UserDefaults.Keys.completedIntro) == nil
    if Self.firstLaunch {
      // set something in userdefaults to know on next launch it's not the first
      userDefaults.completedIntro = false
    }
    
    // reversed the sense of the history filter flag so for frash install unset now means hidden
    // but if upgrading then observe the previous flag
    if userDefaults.object(forKey: UserDefaults.Keys.hideSearch) != nil {
      userDefaults.showHistoryFilter = !userDefaults.hideSearch
    }
    
    // keepHistory false is the new default but deliberately omitted from registered defaults
    // b/c when upgrading from 1.0 this sometimes should instead be on
    // keepHistoryChoicePending is meant to be set the first time running v2.0+, ie. anytime its
    // not set already, and at that time decide what both it and keepHistory should be
    if userDefaults.object(forKey: UserDefaults.Keys.keepHistoryChoicePending) == nil {
      if Self.firstLaunch {
        userDefaults.keepHistory = false
        userDefaults.keepHistoryChoicePending = false
      } else {
        // this v2.0 flag unset even though not first launch must mean migrating from 1.0
        // offer to upgrade to new history-less default, but until they do, keep history on
        // (unfortunately if user wipes userdefaults from the cmd line they get this again)
        userDefaults.keepHistory = true
        userDefaults.keepHistoryChoicePending = true
        os_log(.info, "user must confirm history remaining on, or migrate to history off")
      } 
    }
    
    // showInStatusBar was previously unused, though the app was setting it to true as
    // a registered default, its now replaced by another key, don't leave this around for
    // inquisitive users poking around with `defaults read` to get confused by
    userDefaults.removeObject(forKey: UserDefaults.Keys.showInStatusBar)
    
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
    Self.allowRepeatingBatch = hasPurchased
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
      
      if AppModel.allowPurchases && AppMenu.badgedMenuItemsSupported,
         let expiration = promoteExtrasExpirationDate(), let date = expiration.date
      {
        setPromoteExtrasExpirationTimer(to: date)
        userDefaults.promoteExtrasExpiration = expiration
      } else {
        // purchases or menu badges not supported or cannot set the timer, don't promote the bonus features after all
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
    // called when ui toggles expriation off and on
    if on {
      // first try re-using an existing expiration date, only picking a
      // new date if the existing one is in the past
      if let reusedExpiration = UserDefaults.standard.promoteExtrasExpiration,
         let reusedDate = reusedExpiration.date, reusedDate.timeIntervalSinceNow > 0 {// ie. date is in the future
        setPromoteExtrasExpirationTimer(to: reusedDate)
        
      } else if let newExpiration = promoteExtrasExpirationDate(), let date = newExpiration.date {
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
    
    promotionExpirationTimer?.cancel()
    promotionExpirationTimer = DispatchSource.scheduledTimerForRunningOnMainQueue(afterDelay:
                                                date.timeIntervalSinceNow) { [weak self] in
      guard let self = self else { return }
      promotionExpirationTimer = nil
      UserDefaults.standard.promoteExtras = false
      generalSettingsPaneViewController.promoteExtrasStateChanged()
    }
  }
  
  private func clearPromoteExtrasExpirationTimer() {
    promotionExpirationTimer?.cancel()
    promotionExpirationTimer = nil
  }
  
  class LocalShortDateFormatter: DateFormatter, @unchecked Sendable { // used by logging breakpoint in setPromoteExtrasExpirationTimer
    override init() { super.init(); dateStyle = .short; timeStyle = .short }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  }
  
  private func promoteExtrasExpirationDate() -> DateComponents? {
    let calendar = Calendar(identifier: .gregorian)
    #if DEBUG
    guard let minuteFromNow = calendar.date(byAdding: .minute, value: 3, to: Date()) else {
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
    // this is when there are items in history even though the v2.0 keep-history settings
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
    } else if UserDefaults.standard.suppressSaveClipsAlert {
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
            UserDefaults.standard.suppressSaveClipsAlert = true
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
  
  private func startPollingToRehideMenuIcon() {
    guard hideMenuPollingTimer == nil else { 
      return // rather than restarting time if called a second time, if already running then leave it
    }
    // this polling timer should be running while one of our windows or the menu are open
    // if queue started then the timer ends, polling must be restarted once it finishes
    hideMenuOnNextIteration = false // this flag used to ensure 1 full N-second polling loop occurs after exit condition met
    hideMenuPollingTimer = DispatchSource.scheduledTimerForRunningOnMainQueueRepeated(afterDelay: 4, interval: 4) { [weak self] in
      guard let self = self else { return false }
      if !UserDefaults.standard.menuHiddenWhenInactive || !menuIcon.isVisible || !inOffState { // ie. is timer now moot
        hideMenuPollingTimer = nil
        return false
      }
      let shouldHideMenu = !anyAppWindowsOpen()
      if shouldHideMenu && hideMenuOnNextIteration {
        menuIcon.isVisible = false
        hideMenuPollingTimer = nil
        return false
      }
      hideMenuOnNextIteration = shouldHideMenu
      return true // continue repeating
    }
  }
  
  private func stopPollingToRehideMenuIcon() {
    hideMenuPollingTimer?.cancel()
    hideMenuPollingTimer = nil
  }
  
  private func menuIconWasRemoved() {
    // if hiding the icon is an allowed feature, then when the user drags-removes the
    // menu icon, act like turning the "hide" setting on. if not allowed act like quit
    if !Self.allowMenuHiding {
      NSApplication.shared.terminate(nil)
      
    } else if UserDefaults.standard.menuHiddenWhenInactive == false {
      UserDefaults.standard.menuHiddenWhenInactive = true
    }
    
    stopPollingToRehideMenuIcon() // if this timer was on, it's no longer needed
  }
  
  // swiftlint:disable cyclomatic_complexity
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
    if let historyPageController = introWindowController.historyPageController {
      keepHistoryObserver2 = historyPageController.observe(\.keepHistoryChange, options: .new) { [weak self] _, change in
        // old value of the flag is ephemeral, only care if its different than `keepHistory`
        guard let self = self else { return }
        //print("switch observer, new = \(change.newValue == nil ? "nil" : String(describing: change.newValue!)), keepHistory = \(UserDefaults.standard.keepHistory)")
        guard let newValue = change.newValue, newValue != UserDefaults.standard.keepHistory else { return }
        updateSavingHistory(newValue)
      }
    }
    menuHidingObserver = UserDefaults.standard.observe(\.menuHiddenWhenInactive, options: .new) { [weak self] _, change in
      // turning setting on (hide) first starts polling to wait until all of the app's
      // windows are closed, but turning setting off makes menu visislbe immediately
      guard let self = self, let newValue = change.newValue, Self.allowMenuHiding else { return }
      if newValue == true && menuIcon.isVisible {
        startPollingToRehideMenuIcon()
      } else if newValue == false && !menuIcon.isVisible {
        menuIcon.isVisible = true
        stopPollingToRehideMenuIcon()
      }
    }
    showsInDockObserver = UserDefaults.standard.observe(\.showsInDock, options: .new) { [weak self] _, _ in
      guard let self = self else { return }
      applyShowInDockSetting()
    }
  }
  // swiftlint:enable cyclomatic_complexity
  
  private func addSettingsWindowCloseObserver(_ window: NSWindow) {
    // observers are opaque, no way to inspect them to ensure they observe the same window and not
    // a re-instantiated window, however currently assume that these windows are never disposed & recreated
    //removeNotificationObserver(&settingsClosedObserver)
    if settingsClosedObserver == nil {
      let nc = NotificationCenter.default
      settingsClosedObserver = nc.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
        self?.settingsWindowOpen = false
      }
    }
  }
  
  private func addIntroWindowCloseObserver(_ window: NSWindow) {
    // observers are opaque, no way to inspect them to ensure they observe the same window and not
    // a re-instantiated window, however currently assume that these windows are never disposed & recreated
    //removeNotificationObserver(&introClosedObserver) 
    if introClosedObserver == nil {
      let nc = NotificationCenter.default
      introClosedObserver = nc.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
        self?.introWindowOpen = false
      }
    }
  }
  
  private func addLicensesWindowCloseObserver(_ window: NSWindow) {
    // observers are opaque, no way to inspect them to ensure they observe the same window and not
    // a re-instantiated window, however currently assume that these windows are never disposed & recreated
    //removeNotificationObserver(&licensesClosedObserver)
    if licensesClosedObserver == nil {
      let nc = NotificationCenter.default
      licensesClosedObserver = nc.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
        self?.licensesWindowOpen = false
      }
    }
  }
  
  private func removeNotificationObserver(_ observer: inout NSObjectProtocol?) {
    guard let obs = observer else { return }
    NotificationCenter.default.removeObserver(obs)
    observer = nil
  }
}

func nop() { }
func dontWarnUnused(_ x: Any) { }

// swiftlint:enable file_length
