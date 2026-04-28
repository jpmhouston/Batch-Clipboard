//
//  AboutSettingsViewController.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2026-04-28.
//  Copyright © 2026 Bananameter Labs. All rights reserved.
//

import AppKit
import Settings
import os.log

class AboutSettingsViewController: NSViewController, SettingsPane {
  public let paneIdentifier = Settings.PaneIdentifier.about
  public let paneTitle = NSLocalizedString("preferences_about", comment: "")
  public let toolbarItemIcon = NSImage(named: .app)!
  
  override var nibName: NSNib.Name? { "AboutSettingsViewController" }
  
  @IBOutlet weak var appstoreVersionText: NSTextField!
  @IBOutlet weak var nonAppstoreVersionText: NSTextField!
  @IBOutlet weak var alreadyPurchasedText: NSTextField!
  @IBOutlet weak var advertisePurchaseText: NSTextField!
  @IBOutlet weak var buyMeACoffeeView: NSView!
  @IBOutlet weak var openRepoLinkButton: NSButton!
  @IBOutlet weak var copyRepoLinkButton: NSButton!
  @IBOutlet weak var openHomepageLinkButton: NSButton!
  @IBOutlet weak var copyHomepageLinkButton: NSButton!
  @IBOutlet weak var openDonationLinkButton: NSButton!
  @IBOutlet weak var copyDonationLinkButton: NSButton!
  @IBOutlet weak var sendSupportEmailButton: NSButton!
  @IBOutlet weak var copySupportEmailButton: NSButton!
  
  private var optionKeyEventMonitor: Any?
  
  override func viewDidLoad() {
    #if APP_STORE
    showVersionText(forAppStore: true)
    showAppStoreSupportText(true, hasPurchased: AppModel.hasBoughtExtras)
    showBuyMeACoffeeView(false)
    #else
    showVersionText(forAppStore: false)
    showAppStoreSupportText(false)
    showBuyMeACoffeeView(true)
    #endif
  }
  
  override func viewWillAppear() {
    super.viewWillAppear()
    showAltButtons(false)
    setupOptionKeyObserver() { [weak self] event in
      self?.showAltButtons(event.modifierFlags.contains(.option))
    }
  }
  
  override func viewWillDisappear() {
    super.viewWillDisappear()
    removeOptionKeyObserver()
  }
  
  // MARK: -
  
  private func showVersionText(forAppStore showAppStoreVariant: Bool) {
    appstoreVersionText.isHidden = !showAppStoreVariant
    nonAppstoreVersionText.isHidden = showAppStoreVariant
    
    guard let versionField = showAppStoreVariant ? appstoreVersionText : nonAppstoreVersionText else {
      return
    }
    var text = versionField.stringValue
    if let versionRange = text.range(of: "{vers}") {
      text.replaceSubrange(versionRange, with: appVersion ?? "?")
    }
    if let buildNumberRange = text.range(of: "{build}") {
      text.replaceSubrange(buildNumberRange, with: buildNumber ?? "?")
    }
    versionField.stringValue = text
  }
  
  private func showAppStoreSupportText(_ show: Bool, hasPurchased: Bool = false) {
    alreadyPurchasedText.isHidden = !(show && hasPurchased)
    advertisePurchaseText.isHidden = !(show && !hasPurchased)
  }
  
  private func showBuyMeACoffeeView(_ show: Bool) {
    buyMeACoffeeView.isHidden = !show
  }
  
  private func showAltButtons(_ showCopy: Bool) {
    if showCopy {
      openRepoLinkButton.isHidden = true
      copyRepoLinkButton.isHidden = false
      openHomepageLinkButton.isHidden = true
      copyHomepageLinkButton.isHidden = false
      openDonationLinkButton.isHidden = true
      copyDonationLinkButton.isHidden = false
      sendSupportEmailButton.isHidden = true
      copySupportEmailButton.isHidden = false
    } else {
      openRepoLinkButton.isHidden = false
      copyRepoLinkButton.isHidden = true
      openHomepageLinkButton.isHidden = false
      copyHomepageLinkButton.isHidden = true
      openDonationLinkButton.isHidden = false
      copyDonationLinkButton.isHidden = true
      sendSupportEmailButton.isHidden = false
      copySupportEmailButton.isHidden = true
    }
  }
  
  // MARK: -
  
  @IBAction func showIntro(_ sender: NSButton) {
    openURL(string: AppModel.showIntroInAppURL)
  }
  
  @IBAction func showLicenses(_ sender: NSButton) {
    openURL(string: AppModel.showLicensesInAppURL)
  }
  
  @IBAction func openHomepageLink(_ sender: NSButton) {
    openURL(string: AppModel.homepageURL)
  }
  
  @IBAction func copyHomepageLink(_ sender: NSButton) {
    Clipboard.shared.copy(AppModel.homepageURL, excludeFromHistory: false)
  }
  
  @IBAction func openRepoLink(_ sender: NSButton) {
    openURL(string: AppModel.githubURL)
  }
  
  @IBAction func copyRepoLink(_ sender: NSButton) {
    Clipboard.shared.copy(AppModel.githubURL, excludeFromHistory: false)
  }
  
  @IBAction func openDonationLink(_ sender: AnyObject) {
    openURL(string: AppModel.donationURL)
  }
  
  @IBAction func copyDonationLink(_ sender: AnyObject) {
    Clipboard.shared.copy(AppModel.donationURL, excludeFromHistory: false)
  }
  
  @IBAction func sendSupportEmail(_ sender: AnyObject) {
    openURL(string: AppModel.supportEmailURL)
  }
  
  @IBAction func copySupportEmail(_ sender: AnyObject) {
    Clipboard.shared.copy(AppModel.supportEmailAddress, excludeFromHistory: false)
  }
  
  // MARK: -
  
  private func setupOptionKeyObserver(_ observe: @escaping (NSEvent) -> Void) {
    if let previousMonitor = optionKeyEventMonitor {
      NSEvent.removeMonitor(previousMonitor)
    }
    optionKeyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
      observe(event)
      return event
    }
  }
  
  private func removeOptionKeyObserver() {
    if let eventMonitor = optionKeyEventMonitor {
      NSEvent.removeMonitor(eventMonitor)
      optionKeyEventMonitor = nil
    }
  }
  
  private func openURL(string: String) {
    guard let url = URL(string: string) else {
      os_log(.default, "failed to create URL %@", string)
      return
    }
    if !NSWorkspace.shared.open(url) {
      os_log(.default, "failed to open URL %@", string)
    }
  }
  
  var appVersion: String? {
    guard let versionStr = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
      return nil
    }
    return versionStr
  }

  var buildNumber: String? {
    guard let buildNumStr = Bundle.main.infoDictionary?["CFBundleVersion"] as? String else {
      return nil
    }
    return buildNumStr
  }
  
}
