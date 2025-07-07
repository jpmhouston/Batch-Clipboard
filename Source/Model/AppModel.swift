//
//  AppModel.swift
//  Cleepp
//
//  Created by Pierre Houston on 2024-07-10.
//  Portions Copyright © 2024 Bananameter Labs. All rights reserved.
//
//  Based on GlobalHotKey from Maccy which is
//  Copyright © 2024 Alexey Rodionov. All rights reserved.
//

import Cocoa
import KeyboardShortcuts
import Settings
#if CLEEPP && ALLOW_SPARKLE_UPDATES
import Sparkle
#endif

// swiftlint:disable type_body_length
class AppModel: NSObject {
  // Note:
  // I'm using `internal` to say: i wanted this to be `private` but code using this is in extension in other file
  // where no access modifier given, that means public to the whole module, ie. the default access also `internal`.
  // Given normal useage of `internal` it might make more sense to do this exactly the other way around,
  // however I want the "used in extension to this class" declarations to have a modifier to look similar to lines
  // with `private` and the "public to this module" declarations lines to look different.
  
  static var returnFocusToPreviousApp = true

  internal let menuIcon = MenuBarIcon()
  internal let about = About()
  internal let clipboard = Clipboard.shared
  internal let history = History()
  internal var menu: AppMenu!
  private var menuController: MenuController!

#if CLEEPP
  private var startHotKey: StartKeyboardShortcutHandler!
  private var copyHotKey: CopyKeyboardShortcutHandler!
  private var pasteHotKey: PasteKeyboardShortcutHandler!
#else
  private var hotKey: GlobalHotKey!
  var selectedItem: ClipItem? { (menu.highlightedItem as? ClipMenuItem)?.clipItem }
  private let statusItemTitleMaxLength = 20
#endif

#if CLEEPP
  static var busy = false
  
  static var allowExpandedHistory = true
  static var allowFullyExpandedHistory = false
  static var allowHistorySearch = false
  static var allowReplayFromHistory = false
  static var allowPasteMultiple = false
  static var allowUndoCopy = false
  
  static var allowDictinctStorageSize: Bool { Self.allowFullyExpandedHistory || Self.allowHistorySearch }
  
  static var firstLaunch = false
  
  #if APP_STORE
  static var hasBoughtExtras = false
  static let allowPurchases = true
  #else
  static let allowPurchases = false
  #endif
  
  #if APP_STORE
  private let purchases = AppStorePurchases()
  private var promotionExpirationTimer: Timer?
  #endif
  #if ALLOW_SPARKLE_UPDATES
  private let updaterController = SPUStandardUpdaterController(updaterDelegate: nil, userDriverDelegate: nil)
  #endif
  internal var introWindowController = IntroWindowController()
  internal var licensesWindowController = LicensesWindowController()
  
  internal var queue: ClipboardQueue! // can this be injected wherever its needed, or must is be static & public?
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
#endif

  private var clearAlert: NSAlert {
    let alert = NSAlert()
    alert.messageText = NSLocalizedString("clear_alert_message", comment: "")
    alert.informativeText = NSLocalizedString("clear_alert_comment", comment: "")
    alert.addButton(withTitle: NSLocalizedString("clear_alert_confirm", comment: ""))
    alert.addButton(withTitle: NSLocalizedString("clear_alert_cancel", comment: ""))
    alert.showsSuppressionButton = true
    return alert
  }

#if CLEEPP
  // omits the pins panel, app store build gets the purchase panel
  #if APP_STORE
  internal lazy var generalSettingsPaneViewController = GeneralSettingsViewController()
  internal lazy var settingsWindowController = SettingsWindowController(
    panes: [
      generalSettingsPaneViewController,
      AppearanceSettingsViewController(),
      PurchaseSettingsViewController(purchases: purchases),
      StorageSettingsViewController(),
      IgnoreSettingsViewController(),
      AdvancedSettingsViewController()
    ]
  )
  #else
  internal lazy var settingsWindowController = SettingsWindowController(
    panes: [
      GeneralSettingsViewController(updater: updaterController.updater),
      AppearanceSettingsViewController(),
      StorageSettingsViewController(),
      IgnoreSettingsViewController(),
      AdvancedSettingsViewController()
    ]
  )
  #endif
#else
  internal lazy var settingsWindowController = SettingsWindowController(
    panes: [
      GeneralSettingsViewController(),
      StorageSettingsViewController(),
      AppearanceSettingsViewController(),
      PinsSettingsViewController(),
      IgnoreSettingsViewController(),
      AdvancedSettingsViewController()
    ]
  )
#endif

  private var clipboardCheckIntervalObserver: NSKeyValueObservation?
  private var enabledPasteboardTypesObserver: NSKeyValueObservation?
  private var ignoreEventsObserver: NSKeyValueObservation?
  private var imageHeightObserver: NSKeyValueObservation?
  private var hideFooterObserver: NSKeyValueObservation?
  private var hideSearchObserver: NSKeyValueObservation?
  private var hideTitleObserver: NSKeyValueObservation?
  private var maxMenuItemLengthObserver: NSKeyValueObservation?
  private var pasteByDefaultObserver: NSKeyValueObservation?
  private var pinToObserver: NSKeyValueObservation?
  private var removeFormattingByDefaultObserver: NSKeyValueObservation?
  private var sortByObserver: NSKeyValueObservation?
  private var showSpecialSymbolsObserver: NSKeyValueObservation?
  private var showRecentCopyInMenuBarObserver: NSKeyValueObservation?
  private var statusItemConfigurationObserver: NSKeyValueObservation?
  private var statusItemVisibilityObserver: NSKeyValueObservation?
  private var statusItemChangeObserver: NSKeyValueObservation?

  override init() {
    UserDefaults.standard.register(defaults: [
      UserDefaults.Keys.clipboardCheckInterval: UserDefaults.Values.clipboardCheckInterval,
      UserDefaults.Keys.imageMaxHeight: UserDefaults.Values.imageMaxHeight,
      UserDefaults.Keys.maxMenuItems: UserDefaults.Values.maxMenuItems,
      UserDefaults.Keys.maxMenuItemLength: UserDefaults.Values.maxMenuItemLength,
      UserDefaults.Keys.previewDelay: UserDefaults.Values.previewDelay,
      UserDefaults.Keys.showInStatusBar: UserDefaults.Values.showInStatusBar,
      UserDefaults.Keys.showSpecialSymbols: UserDefaults.Values.showSpecialSymbols
    ])
    #if CLEEPP
    // cleepp doesn't populate these in its app delegates's migration method,
    // maybe should go in Clipboard.init instead though
    UserDefaults.standard.register(defaults: [
      UserDefaults.Keys.enabledPasteboardTypes: UserDefaults.Values.enabledPasteboardTypes,
      UserDefaults.Keys.ignoredPasteboardTypes: UserDefaults.Values.ignoredPasteboardTypes,
    ])
    #endif
    
    super.init()
    initializeObservers()

    settingsWindowController.window?.collectionBehavior.formUnion(.moveToActiveSpace)

    #if CLEEPP
    initializeStateFlags()
    
    queue = ClipboardQueue(clipboard: clipboard, history: history)
    menu = AppMenu.load(withHistory: history, queue: queue, owner: self)
    
    startHotKey = StartKeyboardShortcutHandler(startQueueMode)
    copyHotKey = CopyKeyboardShortcutHandler(queuedCopy)
    pasteHotKey = PasteKeyboardShortcutHandler(queuedPaste)
    #else
    disableUnusedGlobalHotkeys()

    menu = Menu(history: history, clipboard: Clipboard.shared)
    
    hotKey = GlobalHotKey(popUp)
    #endif

    menuController = MenuController(menu, menuIcon.statusItem)
    start()
  }

  deinit {
    clipboardCheckIntervalObserver?.invalidate()
    enabledPasteboardTypesObserver?.invalidate()
    ignoreEventsObserver?.invalidate()
    hideFooterObserver?.invalidate()
    hideSearchObserver?.invalidate()
    hideTitleObserver?.invalidate()
    maxMenuItemLengthObserver?.invalidate()
    pasteByDefaultObserver?.invalidate()
    pinToObserver?.invalidate()
    removeFormattingByDefaultObserver?.invalidate()
    sortByObserver?.invalidate()
    showRecentCopyInMenuBarObserver?.invalidate()
    showSpecialSymbolsObserver?.invalidate()
    statusItemConfigurationObserver?.invalidate()
    statusItemVisibilityObserver?.invalidate()
    statusItemChangeObserver?.invalidate()
    
    menuIcon.cancelBlinkTimer()
    #if APP_STORE
    purchases.finish()
    #endif
  }

  func terminate() {
    if UserDefaults.standard.clearOnQuit {
      clearUnpinned(suppressClearAlert: true)
    }
  }

  func wasReopened() {
    #if CLEEPP
    // if the user has chosen to hide the menu bar icon when not in batch mode then
    // open the Settings window whenever the application icon is double clicked again
    if !UserDefaults.standard.showInStatusBar {
      showSettings(selectingPane: .general)
    }
    #else
    popUp()
    #endif
  }
  
  func popUp() {
    menuController.popUp()
  }

  func select(position: Int) -> String? {
    return menu.select(position: position)
  }

  func delete(position: Int) -> String? {
    #if CLEEPP
    let result = menu.delete(position: position)
    fixQueueAfterDeletingItem(atIndex: position)
    return result
    #else
    return menu.delete(position: position)
    #endif
  }

  func item(at position: Int) -> ClipItem? {
    return menu.historyItem(at: position)
  }
  
  func clearUnpinned(suppressClearAlert: Bool = false) {
    #if CLEEPP
    clearAll(suppressClearAlert: suppressClearAlert)
    #else
    withClearAlert(suppressClearAlert: suppressClearAlert) {
      self.history.clearUnpinned()
      self.menu.clearUnpinned()
      self.clipboard.clear()
      self.updateMenuTitle()
    }
    #endif
  }

  private func start() {
    menuIcon.enableRemoval(true)
    #if CLEEPP
    menuIcon.isVisible = true
    #else
    menuIcon.isVisible = UserDefaults.standard.showInStatusBar
    #endif

    #if !CLEEPP
    menuIcon.setImage(named: UserDefaults.standard.menuIcon)
    #endif

    #if CLEEPP
    clipboard.onNewCopy(clipboardChanged)
    #else
    clipboard.onNewCopy(history.add)
    clipboard.onNewCopy(menu.add)
    clipboard.onNewCopy(updateMenuTitle)
    #endif
    clipboard.start()

    #if CLEEPP
    menu.buildItems()
    // prepareForPopup() can take a while the first time so do it early
    // instead of the first time the menu is clicked on, and in case the
    // intro needs to be shown, delay this call a bit to let that open
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      self.menu.prepareForPopup(location: .inMenuBar)
    }
    #else
    populateHeader()
    populateItems()
    populateFooter()
    #endif

    updateStatusItemEnabledness()
    
    #if CLEEPP
    if !UserDefaults.standard.completedIntro {
      showIntro(self)
    } else if !Permissions.allowed {
      showIntroAtPermissionPage(self)
    }
    #endif
  }

#if CLEEPP
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
    setFeatureFlags(givenPurchase: purchases.hasBoughtExtras)
    Self.hasBoughtExtras = purchases.hasBoughtExtras
    
    if purchases.hasBoughtExtras {
      clearPromoteExtrasExpirationTimer()
      UserDefaults.standard.promoteExtras = false
      UserDefaults.standard.promoteExtrasExpiration = nil
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
  }
  
  // Non-history items in the cleepp menu are defined in a nib file instead of programmatically
  // (the best code is no code), action methods for those items now live in this class, defined
  // in a class extension. Also history menu item subclasses no longer exist, actions for those
  // are also defined in the extension, and other "business logic" for the queueing feature.
  
#else
  private func populateHeader() {
    let headerItem = NSMenuItem()
    headerItem.title = "Maccy"
    headerItem.view = MenuHeader().view

    menu.insertItem(headerItem, at: 0)
  }

  private func updateHeader() {
    menu.removeItem(at: 0)
    populateHeader()
  }

  private func populateItems() {
    menu.buildItems()
    menu.updateUnpinnedItemsVisibility()
    updateMenuTitle()
  }

  private func populateFooter() {
    MenuFooter.allCases.map({ $0.menuItem }).forEach({ item in
      item.action = #selector(menuItemAction)
      item.target = self
      menu.addItem(item)
    })
  }

  private func updateFooter() {
    MenuFooter.allCases.forEach({ _ in
      menu.removeItem(at: menu.numberOfItems - 1)
    })
    populateFooter()
  }

  @objc
  private func menuItemAction(_ sender: NSMenuItem) {
    if let tag = MenuFooter(rawValue: sender.tag) {
      switch tag {
      case .about:
        Maccy.returnFocusToPreviousApp = false
        about.openAbout(sender)
        Maccy.returnFocusToPreviousApp = true
      case .clear:
        clearUnpinned()
      case .clearAll:
        clearAll()
      case .quit:
        NSApp.terminate(sender)
      case .preferences:
        Maccy.returnFocusToPreviousApp = false
        settingsWindowController.show()
        settingsWindowController.window?.orderFrontRegardless()
        Maccy.returnFocusToPreviousApp = true
      default:
        break
      }
    }
  }
#endif

  private func clearAll(suppressClearAlert: Bool = false) {
    withClearAlert(suppressClearAlert: suppressClearAlert) {
      self.history.clear()
      self.menu.clearAll()
      self.clipboard.clear()
      #if CLEEPP
      self.queue.off()
      self.updateMenuIcon()
      #endif
      self.updateMenuTitle()
    }
  }

  private func withClearAlert(suppressClearAlert: Bool, _ closure: @escaping () -> Void) {
    if suppressClearAlert || UserDefaults.standard.suppressClearAlert {
      closure()
    } else {
      AppModel.returnFocusToPreviousApp = false
      let alert = clearAlert
      DispatchQueue.main.async {
        if alert.runModal() == NSApplication.ModalResponse.alertFirstButtonReturn {
          if alert.suppressionButton?.state == .on {
            UserDefaults.standard.suppressClearAlert = true
          }
          closure()
        }
        AppModel.returnFocusToPreviousApp = true
      }
    }
  }

  private func rebuild() {
    menu.clearAll()

    #if CLEEPP
    menu.buildItems()
    if queue.isOn {
      menu.updateHeadOfQueue(index: queue.headIndex)
    }
    #else
    menu.removeAllItems()
    populateHeader()
    populateItems()
    populateFooter()
    #endif
  }

#if !CLEEPP
  private func updateMenuIcon(_ newIcon: String) {
    switch newIcon {
//    case "scissors":
//      menuIcon.image = NSImage(named: .scissors)
//    case "paperclip":
//      menuIcon.image = NSImage(named: .paperclip)
//    case "clipboard":
//      menuIcon.image = NSImage(named: .clipboard)
    default:
      menuIcon.image = NSImage(named: .maccyStatusBar)
    }
  }
  
  internal func updateMenuTitle(_ item: ClipItem? = nil) {
    guard UserDefaults.standard.showRecentCopyInMenuBar else {
      menuIcon.badge = ""
      return
    }

    var title = ""
    if let item = item {
      title = HistoryMenuItem(item: item, clipboard: clipboard).title
    } else if let item = menu.firstUnpinnedHistoryMenuItem {
      title = item.title
    }

    menuIcon.badge = String(title.prefix(statusItemTitleMaxLength))
  }
#endif

  private func updateStatusItemEnabledness() {
    menuIcon.isEnabled = !(UserDefaults.standard.ignoreEvents ||
      UserDefaults.standard.enabledPasteboardTypes.isEmpty)
  }

  // swiftlint:disable function_body_length
  private func initializeObservers() {
    clipboardCheckIntervalObserver = UserDefaults.standard.observe(\.clipboardCheckInterval, options: .new) { _, _ in
      self.clipboard.restart()
    }
    enabledPasteboardTypesObserver = UserDefaults.standard.observe(\.enabledPasteboardTypes, options: .new) { _, _ in
      self.updateStatusItemEnabledness()
    }
    ignoreEventsObserver = UserDefaults.standard.observe(\.ignoreEvents, options: .new) { _, _ in
      self.updateStatusItemEnabledness()
    }
    imageHeightObserver = UserDefaults.standard.observe(\.imageMaxHeight, options: .new) { _, _ in
      self.menu.resizeImageMenuItems()
    }
    maxMenuItemLengthObserver = UserDefaults.standard.observe(\.maxMenuItemLength, options: .new) { _, _ in
      self.menu.regenerateMenuItemTitles()
      CoreDataManager.shared.saveContext()
    }
    #if !CLEEPP
    hideFooterObserver = UserDefaults.standard.observe(\.hideFooter, options: .new) { _, _ in
      self.updateFooter()
    }
    hideSearchObserver = UserDefaults.standard.observe(\.hideSearch, options: .new) { _, _ in
      self.updateHeader()
    }
    hideTitleObserver = UserDefaults.standard.observe(\.hideTitle, options: .new) { _, _ in
      self.updateHeader()
    }
    pasteByDefaultObserver = UserDefaults.standard.observe(\.pasteByDefault, options: .new) { _, _ in
      self.rebuild()
    }
    pinToObserver = UserDefaults.standard.observe(\.pinTo, options: .new) { _, _ in
      self.rebuild()
    }
    removeFormattingByDefaultObserver = UserDefaults.standard.observe(\.removeFormattingByDefault,
                                                                      options: .new) { _, _ in
      self.rebuild()
    }
    sortByObserver = UserDefaults.standard.observe(\.sortBy, options: .new) { _, _ in
      self.rebuild()
    }
    showSpecialSymbolsObserver = UserDefaults.standard.observe(\.showSpecialSymbols, options: .new) { _, _ in
      self.menu.regenerateMenuItemTitles()
      CoreDataManager.shared.saveContext()
    }
    showRecentCopyInMenuBarObserver = UserDefaults.standard.observe(\.showRecentCopyInMenuBar,
                                                                    options: .new) { _, _ in
      self.updateMenuTitle()
    }
    statusItemConfigurationObserver = UserDefaults.standard.observe(\.showInStatusBar,
                                                                    options: .new) { _, change in
      if self.statusItem.isVisible != change.newValue! {
        self.statusItem.isVisible = change.newValue!
      }
    }
    statusItemVisibilityObserver = observe(\.statusItem.isVisible, options: .new) { _, change in
      if UserDefaults.standard.showInStatusBar != change.newValue! {
        UserDefaults.standard.showInStatusBar = change.newValue!
      }
    }
    statusItemChangeObserver = UserDefaults.standard.observe(\.menuIcon, options: .new) { _, change in
      self.updateMenuIcon(change.newValue!)
    }
    #endif
  }
  // swiftlint:enable function_body_length
  
  #if !CLEEPP
  private func disableUnusedGlobalHotkeys() {
    let names: [KeyboardShortcuts.Name] = [.delete, .pin]
    KeyboardShortcuts.disable(names)
    //names.forEach(KeyboardShortcuts.disable) // if KyboardShortcuts >1.11.0 change to: KeyboardShortcuts.disable(names)
    
    NotificationCenter.default.addObserver(
      forName: Notification.Name("KeyboardShortcuts_shortcutByNameDidChange"),
      object: nil,
      queue: nil
    ) { notification in
      if let name = notification.userInfo?["name"] as? KeyboardShortcuts.Name, names.contains(name) {
        KeyboardShortcuts.disable(name)
      }
    }
  }
  #endif
}
// swiftlint:enable type_body_length
