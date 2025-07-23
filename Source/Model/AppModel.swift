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
  static var allowPasteMultiple = false
  static var allowUndoCopy = false
  static var allowSavedBatches = false
  
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
  internal var menu: AppMenu!
  internal var menuController: MenuController!
  
  private var startHotKey: StartKeyboardShortcutHandler!
  private var copyHotKey: CopyKeyboardShortcutHandler!
  private var pasteHotKey: PasteKeyboardShortcutHandler!
  
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
  
  internal var bonusFeaturePromotionAlert: NSAlert {
    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = NSLocalizedString("promoteextras_alert_message", comment: "")
    alert.informativeText = NSLocalizedString("promoteextras_alert_comment", comment: "")
    alert.addButton(withTitle: NSLocalizedString("promoteextras_alert_show_settings", comment: ""))
    alert.addButton(withTitle: NSLocalizedString("promoteextras_alert_cancel", comment: ""))
    return alert
  }
  
  internal var numberQueuedAlert: NSAlert {
    let alert = NSAlert()
    alert.messageText = NSLocalizedString("number_alert_message", comment: "")
    alert.informativeText = NSLocalizedString("number_alert_comment", comment: "")
      .replacingOccurrences(of: "{number}", with: String(queue.size))
    alert.addButton(withTitle: NSLocalizedString("number_alert_confirm", comment: ""))
    alert.addButton(withTitle: NSLocalizedString("number_alert_cancel", comment: ""))
    let field = RangedIntegerTextField(acceptingRange: 1...queue.size, permittingEmpty: true,
                                       frame: NSRect(x: 0, y: 0, width: 200, height: 24)) { valid in
      alert.buttons[0].isEnabled = valid
    }
    field.placeholderString = String(queue.size)
    alert.accessoryView = field
    alert.window.initialFirstResponder = field
    return alert
  }
  
  internal var clearAlert: NSAlert {
    let alert = NSAlert()
    alert.messageText = NSLocalizedString("clear_alert_message", comment: "")
    alert.informativeText = NSLocalizedString("clear_alert_comment", comment: "")
    alert.addButton(withTitle: NSLocalizedString("clear_alert_confirm", comment: ""))
    alert.addButton(withTitle: NSLocalizedString("clear_alert_cancel", comment: ""))
    alert.showsSuppressionButton = true
    return alert
  }
  
  private var reoderingWhenEenablingHistoryAlert: NSAlert {
    let alert = NSAlert()
    alert.messageText = NSLocalizedString("reverse_order_alert_message", comment: "")
    alert.informativeText = NSLocalizedString("reverse_order_alert_comment", comment: "")
    alert.addButton(withTitle: NSLocalizedString("reverse_order_alert_confirm", comment: ""))
    alert.addButton(withTitle: NSLocalizedString("reverse_order_alert_cancel", comment: ""))
    alert.showsSuppressionButton = true
    return alert
  }
  
  private var clearWhenDisablingHistoryAlert: NSAlert {
    let alert = NSAlert()
    alert.messageText = NSLocalizedString("erase_history_alert_message", comment: "")
    alert.informativeText = NSLocalizedString("erase_history_alert_comment", comment: "")
    alert.addButton(withTitle: NSLocalizedString("erase_history_alert_confirm", comment: ""))
    alert.addButton(withTitle: NSLocalizedString("erase_history_alert_deny", comment: ""))
    alert.addButton(withTitle: NSLocalizedString("erase_history_alert_cancel", comment: ""))
    alert.showsSuppressionButton = true
    return alert
  }
  
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
  private var statusItemConfigurationObserver: NSKeyValueObservation?
  private var statusItemVisibilityObserver: NSKeyValueObservation?
  
  // MARK: -
  
  override init() {
    UserDefaults.standard.register(defaults: [
      // unlike maccy, app doesn't populate these in its app delegates's migration method,
      // maybe should go in Clipboard.init instead though
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
      UserDefaults.Keys.highlightMatch: UserDefaults.Values.highlightMatch,
      UserDefaults.Keys.keepHistory: UserDefaults.Values.keepHistory
    ])
    
    super.init()
    initializeStateFlags()
    
    settingsWindowController.window?.collectionBehavior.formUnion(.moveToActiveSpace)
    
    startHotKey = StartKeyboardShortcutHandler(startQueueMode)
    copyHotKey = CopyKeyboardShortcutHandler(queuedCopy)
    pasteHotKey = PasteKeyboardShortcutHandler(queuedPaste)
    
    queue = ClipboardQueue(clipboard: clipboard, history: history)
    clipboard.onNewCopy(clipboardChanged)       // main callback setup here 
    if UserDefaults.standard.keepHistory {
      clipboard.start()
    }
    
    menu = AppMenu.load(withHistory: history, queue: queue, owner: self)
    menu.buildDynamicItems()
    // prepareForPopup() can take a while the first time so do it early
    // instead of the first time the menu is clicked on, and in case the
    // intro needs to be shown, delay this call a bit to let that open
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      self.menu.prepareForPopup()
    }
    
    menuIcon.enableRemoval(true)
    menuIcon.isVisible = true
    updateMenuIconEnabledness()
    menuController = MenuController(menu, menuIcon.statusItem)
    
    if !UserDefaults.standard.completedIntro {
      showIntro(self)
    } else if !Permissions.allowed {
      showIntroAtPermissionPage(self)
    } else if historySettingsInconsistent() {
      // this should only happen when starting after an update from a previous version,
      // change to keep the history initially and let the user choose to keep it that way
      // or go along with the new defaults and delete the history
      UserDefaults.standard.keepHistory = true
      os_log(.info, "resolving having items history vs. keep-history settings at their negative defaults by showing intro page covering migration")
      showIntroAtHistoryUpdatePage(self)
    }
    
    // important to setup observers after potential early changes to observees above
    // (for example UserDefaults.standard.keepHistory)
    initializeObservers()
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
    statusItemConfigurationObserver?.invalidate()
    statusItemVisibilityObserver?.invalidate()
    
    menuIcon.cancelBlinkTimer()
    #if APP_STORE
    purchases.finish()
    #endif
  }

  func terminate() {
    if UserDefaults.standard.clearOnQuit || !UserDefaults.standard.keepHistory {
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
  
  func popUp() {
    menuController.popUp()
  }
  
  // MARK: - features & purchases
  
  private func initializeStateFlags() {
    let userDefaults = UserDefaults.standard
    Self.firstLaunch = userDefaults.dictionaryRepresentation().isEmpty
    if Self.firstLaunch {
      // set something in userdefaults to know on next launch it's not the first
      userDefaults.completedIntro = false
    }
    
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
    
    #if APP_STORE && !BONUS_FEATUES_ON
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
    }
    else if userDefaults.promoteExtras && userDefaults.promoteExtrasExpires {
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
  
  #if APP_STORE
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
    let alreadtHadExtras = Self.hasBoughtExtras
    
    setFeatureFlags(givenPurchase: purchases.hasBoughtExtras)
    Self.hasBoughtExtras = purchases.hasBoughtExtras
    
    if purchases.hasBoughtExtras {
      clearPromoteExtrasExpirationTimer()
      UserDefaults.standard.promoteExtras = false
      UserDefaults.standard.promoteExtrasExpiration = nil
    }
    
    if Self.hasBoughtExtras != alreadtHadExtras { // in most cases unnecessary, but just be sure
      self.history.trim()
      self.menu.buildDynamicItems()
      CoreDataManager.shared.saveContext()
    }
    #endif
  }
  #endif // APP_STORE
  
  private func setFeatureFlags(givenPurchase hasPurchased: Bool) {
    Self.allowFullyExpandedHistory = hasPurchased
    Self.allowHistorySearch = hasPurchased
    Self.allowReplayFromHistory = hasPurchased
    Self.allowPasteMultiple = hasPurchased
    Self.allowUndoCopy = hasPurchased
    Self.allowSavedBatches = hasPurchased
  }
  
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
      withEnableHistoryConfirmationAlert { [weak self] in
        self?.clipboard.restart()
        self?.menu.buildDynamicItems()
      }
    } else {
      withDisableHistoryConfirmationAlert { [weak self] retainDB in
        self?.clipboard.stop()
        if !retainDB {
          self?.history.clear()
        }
        self?.menu.buildDynamicItems()
      }
    }
  }
  
  private func withEnableHistoryConfirmationAlert(_ closure: @escaping () -> Void) {
    if UserDefaults.standard.supressUseHistoryAlert {
      UserDefaults.standard.keepHistory = true
      closure()
      return
    }
    Self.returnFocusToPreviousApp = false
    let alert = reoderingWhenEenablingHistoryAlert
    DispatchQueue.main.async {
      switch alert.runModal() {
      case NSApplication.ModalResponse.alertFirstButtonReturn:
        UserDefaults.standard.keepHistory = true
        closure()
      default:
        UserDefaults.standard.keepHistory = false
      }
    }
    Self.returnFocusToPreviousApp = true
  }
  
  private func withDisableHistoryConfirmationAlert(_ closure: @escaping (Bool) -> Void) {
    if UserDefaults.standard.supressSaveClipsAlert {
      UserDefaults.standard.keepHistory = false
      closure(UserDefaults.standard.saveClipsAcrossDisabledHistory)
      return
    }
    Self.returnFocusToPreviousApp = false
    let alert = clearWhenDisablingHistoryAlert
    DispatchQueue.main.async {
      switch alert.runModal() {
      case NSApplication.ModalResponse.alertFirstButtonReturn:
        UserDefaults.standard.keepHistory = false
        if alert.suppressionButton?.state == .on {
          UserDefaults.standard.supressSaveClipsAlert = true
          UserDefaults.standard.saveClipsAcrossDisabledHistory = false
        }
        closure(false)
      case NSApplication.ModalResponse.alertSecondButtonReturn:
        UserDefaults.standard.keepHistory = false
        if alert.suppressionButton?.state == .on {
          UserDefaults.standard.supressSaveClipsAlert = true
          UserDefaults.standard.saveClipsAcrossDisabledHistory = true
        }
        closure(true)
      default:
        UserDefaults.standard.keepHistory = true
      }
    }
    Self.returnFocusToPreviousApp = true
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
      // insist that `oldValie` is present in `changed` param, avoid redundant calls to `updateSavingHistory`
      guard let self = self else { return }
      //print("switch observer, new = \(change.newValue == nil ? "nil" : String(describing: change.newValue!)), keepHistory = \(UserDefaults.standard.keepHistory)")
      guard let newValue = change.newValue, newValue != UserDefaults.standard.keepHistory else { return }
      updateSavingHistory(newValue)
    }
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
