//
//  GeneralSettingsViewController.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-07-10.
//  Portions Copyright © 2025 Bananameter Labs. All rights reserved.
//
//  Based on GeneralSettingsViewController.swift from the Maccy project
//  Portions Copyright © 2024 Alexey Rodionov. All rights reserved.
//

import AppKit
import Settings
#if SPARKLE_UPDATES
import Sparkle
#endif
#if canImport(ServiceManagement)
import ServiceManagement
#endif

class GeneralSettingsViewController: NSViewController, SettingsPane {
  public let paneIdentifier = Settings.PaneIdentifier.general
  public let paneTitle = NSLocalizedString("preferences_general", comment: "")
  public let toolbarItemIcon = NSImage(named: .gear)!
  
  override var nibName: NSNib.Name? { "GeneralSettingsViewController" }
  
  #if SPARKLE_UPDATES
  private var sparkleUpdater: SPUUpdater
  #endif
  private lazy var loginItemsURL = URL(
    string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
  )
  
  @IBOutlet weak var launchAtLoginCheckbox: NSButton?
  @IBOutlet weak var openLoginItemsPanelSection: NSView?
  @IBOutlet weak var openLoginItemsPanelButton: NSButton?
  @IBOutlet weak var checkForUpdatesSection: NSView?
  @IBOutlet weak var automaticUpdatesCheckbox: NSButton?
  @IBOutlet weak var betaFeedUpdatesCheckbox: NSButton?
  @IBOutlet weak var checkForUpdatesSeparator: NSView?
  @IBOutlet weak var menuHidingCheckbox: NSButton?
  @IBOutlet weak var menuHiddenBlurbNormal: NSTextField?
  @IBOutlet weak var menuHiddenBlurbLaunchStartsQueue: NSTextField?
  @IBOutlet weak var menuHiddenBlurbDockShowing: NSTextField?
  @IBOutlet weak var menuHiddenBlurbDockStartsQueue: NSTextField?
  @IBOutlet weak var showInDockCheckbox: NSButton?
  @IBOutlet weak var relaunchingStartsBatchCheckbox: NSButton?
  @IBOutlet weak var promoteExtrasCheckbox: NSButton?
  @IBOutlet weak var promoteExtrasExpiresCheckbox: NSButton?
  @IBOutlet weak var promoteExtrasSeparator: NSView?
  @IBOutlet weak var promoteExtrasItemsSection: NSView?
  
  #if SPARKLE_UPDATES
  init(updater: SPUUpdater) {
    sparkleUpdater = updater
    super.init(nibName: nil, bundle: nil)
  }
  
  private init() {
    fatalError("init(updater:) must be used instead of init()")
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  #endif
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    if #available(macOS 13.0, *) {
      showLaunchAtLoginOptions(true)
    } else {
      showLaunchAtLoginOptions(false) // show instead the open login items button 
    }
    
    #if SPARKLE_UPDATES
    showSparkleUpdateOptions(true)
    #else
    showSparkleUpdateOptions(false)
    #endif
    
    showMenuHidingLabels()
    
    #if APP_STORE
    if #available(macOS 14, *) { // badged menu items first available in macOS 14
      showPromoteExtrasOptions(true)
    } else {
      showPromoteExtrasOptions(false)
    }
    #else
    showPromoteExtrasOptions(false)
    #endif
  }
  
  override func viewWillAppear() {
    super.viewWillAppear()
    populateLaunchAtLogin()
    populateSparkleAutomaticUpdates()
    populateSparkleBetaFeed()
    populateMenuHiding()
    populateDockOptions()
    populatePromoteExtrasOptions()
  }
  
  // MARK: -
  
  public func promoteExtrasStateChanged() {
    populatePromoteExtrasOptions()
  }
  
  private func populateLaunchAtLogin() {
    guard #available(macOS 13.0, *) else {
      return
    }
    launchAtLoginCheckbox?.state = SMAppService.mainApp.status == .enabled ? .on : .off
  }
  
  private func populateSparkleAutomaticUpdates() {
    #if SPARKLE_UPDATES
    let automatic = sparkleUpdater.automaticallyChecksForUpdates
    automaticUpdatesCheckbox?.state = automatic ? .on : .off
    enableSparkleBetaFeed(automatic)
    #endif
  }
  
  private func enableSparkleBetaFeed(_ enable: Bool = true) {
    #if SPARKLE_UPDATES
    betaFeedUpdatesCheckbox?.isEnabled = enable
    #endif
  }
  
  private func populateSparkleBetaFeed() {
    #if SPARKLE_UPDATES
    let useBetaFeed = UserDefaults.standard.sparkleUsesBetaFeed
    betaFeedUpdatesCheckbox?.state = useBetaFeed ? .on : .off
    #endif
  }
  
  private func populateMenuHiding() {
    let hideMenu = UserDefaults.standard.menuHiddenWhenInactive
    menuHidingCheckbox?.state = hideMenu ? .on : .off
  }
  
  private func populateDockOptions() {
    let showsInDock = UserDefaults.standard.showsInDock
    let relaunchingStartsBatch = UserDefaults.standard.relaunchingStartsBatch
    showInDockCheckbox?.state = showsInDock ? .on : .off
    relaunchingStartsBatchCheckbox?.state = relaunchingStartsBatch ? .on : .off
  }
  
  private func populatePromoteExtrasOptions() {
    #if APP_STORE
    promoteExtrasCheckbox?.state = UserDefaults.standard.promoteExtras ? .on : .off
    promoteExtrasExpiresCheckbox?.state = UserDefaults.standard.promoteExtrasExpires ? .on : .off
    promoteExtrasCheckbox?.isEnabled = !AppModel.hasBoughtExtras
    promoteExtrasExpiresCheckbox?.isEnabled = !AppModel.hasBoughtExtras && UserDefaults.standard.promoteExtras
    #endif
  }
  
  // MARK: -
  
  @IBAction func sparkleAutomaticUpdatesChanged(_ sender: NSButton) {
    #if SPARKLE_UPDATES
    let automatic = (sender.state == .on)
    sparkleUpdater.automaticallyChecksForUpdates = automatic
    enableSparkleBetaFeed(automatic)
    #endif
  }
  
  @IBAction func sparkleBetaFeedChanged(_ sender: NSButton) {
    #if SPARKLE_UPDATES
    let useBetaFeed = (sender.state == .on)
    UserDefaults.standard.sparkleUsesBetaFeed = useBetaFeed
    #endif
  }
  
  @IBAction func sparkleUpdateCheck(_ sender: NSButton) {
    #if SPARKLE_UPDATES
    sparkleUpdater.checkForUpdates()
    #endif
  }
  
  @IBAction func launchAtLoginChanged(_ sender: NSButton) {
    guard #available(macOS 13.0, *) else {
      return
    }
    if sender.state == .on {
      do {
        if SMAppService.mainApp.status == .enabled {
          try? SMAppService.mainApp.unregister()
        }
        try SMAppService.mainApp.register()
      } catch {
        sender.state = .off
      }
      
    } else {
      do {
        try SMAppService.mainApp.unregister()
      } catch {
        sender.state = .on
      }
    }
  }
  
  @IBAction func openLoginItemsPanel(_ sender: NSButton) {
    guard let url = loginItemsURL else {
      return
    }
    NSWorkspace.shared.open(url)
  }
  
  @IBAction func menuHidingChanged(_ sender: NSButton) {
    UserDefaults.standard.menuHiddenWhenInactive = (sender.state == .on)
    showMenuHidingLabels()
  }
  
  @IBAction func showInDockChanged(_ sender: NSButton) {
    UserDefaults.standard.showsInDock = (sender.state == .on)
    showMenuHidingLabels()
  }
  
  @IBAction func relaunchingStartsBatchChanged(_ sender: NSButton) {
    UserDefaults.standard.relaunchingStartsBatch = (sender.state == .on)
    showMenuHidingLabels()
  }
  
  @IBAction func promoteExtrasChanged(_ sender: NSButton) {
    #if APP_STORE
    UserDefaults.standard.promoteExtras = (sender.state == .on)
    // turning promotion itself off & on doesn't reset the expiration date
    // but keeps the same expiration as long as its still in the future
    updatePromoteExtrasExpirationOption()
    updatePromoteExtrasExpirationTimer()
    #endif
  }
  
  @IBAction func promoteExtrasExpiresChanged(_ sender: NSButton) {
    #if APP_STORE
    UserDefaults.standard.promoteExtrasExpires = (sender.state == .on)
    // turning expiration checkbox off and on does reset the expiration date
    UserDefaults.standard.promoteExtrasExpiration = nil
    updatePromoteExtrasExpirationTimer()
    #endif
  }
  
  #if APP_STORE
  private func updatePromoteExtrasExpirationOption() {
    promoteExtrasExpiresCheckbox?.isEnabled = !AppModel.hasBoughtExtras && UserDefaults.standard.promoteExtras
  }

  private func updatePromoteExtrasExpirationTimer() {
    guard let model = (NSApp.delegate as? AppDelegate)?.model else {
      return
    }
    model.setPromoteExtrasExpirationTimer(on: UserDefaults.standard.promoteExtras && UserDefaults.standard.promoteExtrasExpires)
  }
  #endif
  
  // MARK: -
  
  private func showSparkleUpdateOptions(_ show: Bool) {
    checkForUpdatesSection?.isHidden = !show
    //checkForUpdatesSeparator?.isHidden = !show
  }
  
  private func showLaunchAtLoginOptions(_ show: Bool) {
    launchAtLoginCheckbox?.isHidden = !show
    openLoginItemsPanelSection?.isHidden = show
  }
  
  private func showMenuHidingLabels() {
    menuHiddenBlurbNormal?.isHidden = true
    menuHiddenBlurbLaunchStartsQueue?.isHidden = true
    menuHiddenBlurbDockShowing?.isHidden = true
    menuHiddenBlurbDockStartsQueue?.isHidden = true
    if UserDefaults.standard.menuHiddenWhenInactive {
      let showsInDock = UserDefaults.standard.showsInDock
      let relaunchingStartsBatch = UserDefaults.standard.relaunchingStartsBatch
      switch (showsInDock, relaunchingStartsBatch) {
      case (false, false): menuHiddenBlurbNormal?.isHidden = false
      case (false, true): menuHiddenBlurbLaunchStartsQueue?.isHidden = false
      case (true, false): menuHiddenBlurbDockShowing?.isHidden = false
      case (true, true): menuHiddenBlurbDockStartsQueue?.isHidden = false
      }
    }
  }
  
  private func showPromoteExtrasOptions(_ show: Bool) {
    promoteExtrasSeparator?.isHidden = !show
    promoteExtrasItemsSection?.isHidden = !show
  }
}
