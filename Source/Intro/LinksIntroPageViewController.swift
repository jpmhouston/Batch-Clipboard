//
//  LinksIntroPageViewController.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2026-06-11.
//  Copyright © 2026 Bananameter Labs. All rights reserved.
//

import AppKit
import os.log

class LinksIntroPageViewController: IntroPageController {
  @IBOutlet var inAppPurchageSection: NSView?
  @IBOutlet var appStorePromoSection: NSView?
  @IBOutlet var openDocsLinkButton: NSButton?
  @IBOutlet var copyDocsLinkButton: NSButton?
  @IBOutlet var sendSupportEmailButton: NSButton?
  @IBOutlet var copySupportEmailButton: NSButton?
  @IBOutlet var openDonationLinkButton: NSButton?
  @IBOutlet var copyDonationLinkButton: NSButton?
  //@IBOutlet var openPrivacyPolicyLinkButton: NSButton?
  //@IBOutlet var openAppStoreEULALinkButton: NSButton?
  //@IBOutlet var sendL10nEmailButton: NSButton?
  //@IBOutlet var copyL10nEmailButton: NSButton?
  @IBOutlet var aboutGitHubLabel: NSTextField?
  @IBOutlet var appStoreAboutGitHubLabel: NSTextField?
  @IBOutlet var openGitHubLinkButton: NSButton?
  @IBOutlet var copyGitHubLinkButton: NSButton?
  @IBOutlet var openMaccyLinkButton: NSButton?
  @IBOutlet var copyMaccyLinkButton: NSButton?
  
  private var optionKeyEventMonitor: Any?
  
  deinit {
    removeOptionKeyObserver()
  }
  
  // MARK: -
  
  override func willShow() -> NSButton? {
    #if APP_STORE
    inAppPurchageSection?.isHidden = false
    appStorePromoSection?.isHidden = true
    openDonationLinkButton?.isHidden = true
    copyDonationLinkButton?.isHidden = true
    //openPrivacyPolicyLinkButton?.isHidden = false
    //openAppStoreEULALinkButton?.isHidden = false
    aboutGitHubLabel?.isHidden = true
    appStoreAboutGitHubLabel?.isHidden = false
    #else
    inAppPurchageSection?.isHidden = true
    appStorePromoSection?.isHidden = false
    //openPrivacyPolicyLinkButton?.isHidden = true
    //openAppStoreEULALinkButton?.isHidden = true
    aboutGitHubLabel?.isHidden = false
    appStoreAboutGitHubLabel?.isHidden = true
    #endif
    
    showAltCopyEmailButtons(false)
    setupOptionKeyObserver() { [weak self] event in
      self?.showAltCopyEmailButtons(event.modifierFlags.contains(.option))
    }
    
    return nil
  }
  
  override func shouldLeave() -> Bool {
    removeOptionKeyObserver()
    return true
  }
  
  // MARK: -
  
  @IBAction func openInAppPurchaceSettings(_ sender: AnyObject) {
    app.showSettings(selectingPane: .purchase)
  }
  
  @IBAction func openAppInMacAppStore(_ sender: AnyObject) {
    openURL(string: AppModel.macAppStoreURL)
  }
  
  @IBAction func openAboutBox(_ sender: AnyObject) {
    openURL(string: AppModel.showAboutInAppURL)
  }
  
  @IBAction func openDocumentationWebpage(_ sender: AnyObject) {
    openURL(string: AppModel.homepageURL)
  }
  
  @IBAction func copyDocumentationWebpage(_ sender: AnyObject) {
    Clipboard.shared.copy(AppModel.homepageURL, excludeFromHistory: false)
  }
  
  @IBAction func openGitHubWebpage(_ sender: AnyObject) {
    openURL(string: AppModel.githubURL)
  }
  
  @IBAction func copyGitHubWebpage(_ sender: AnyObject) {
    Clipboard.shared.copy(AppModel.githubURL, excludeFromHistory: false)
  }
  
  @IBAction func openDonationWebpage(_ sender: AnyObject) {
    openURL(string: AppModel.donationURL)
  }
  
  @IBAction func copyDonationWebpage(_ sender: AnyObject) {
    Clipboard.shared.copy(AppModel.donationURL, excludeFromHistory: false)
  }
  
  @IBAction func openPrivacyPolicyWebpage(_ sender: AnyObject) {
    openURL(string: AppModel.privacyPolicyURL)
  }
  
  @IBAction func openAppStoreEULAWebpage(_ sender: AnyObject) {
    openURL(string: AppModel.appStoreUserAgreementURL)
  }
  
  @IBAction func openMaccyWebpage(_ sender: AnyObject) {
    openURL(string: AppModel.maccyURL)
  }
  
  @IBAction func copyMaccyWebpage(_ sender: AnyObject) {
    Clipboard.shared.copy(AppModel.maccyURL, excludeFromHistory: false)
  }
  
  @IBAction func sendSupportEmail(_ sender: AnyObject) {
    openURL(string: AppModel.supportEmailURL)
  }
  
  @IBAction func copySupportEmail(_ sender: AnyObject) {
    Clipboard.shared.copy(AppModel.supportEmailAddress, excludeFromHistory: false)
  }
  
  @IBAction func sendLocalizeVolunteerEmail(_ sender: AnyObject) {
    openURL(string: AppModel.localizeVolunteerEmailURL)
  }
  
  @IBAction func copyLocalizeVolunteerEmail(_ sender: AnyObject) {
    Clipboard.shared.copy(AppModel.localizeVolunteerEmailAddress, excludeFromHistory: false)
  }
  
  // MARK: -
  
  private func showAltCopyEmailButtons(_ showCopy: Bool) {
    openDocsLinkButton?.isHidden = showCopy
    copyDocsLinkButton?.isHidden = !showCopy
    sendSupportEmailButton?.isHidden = showCopy
    copySupportEmailButton?.isHidden = !showCopy
    //sendL10nEmailButton?.isHidden = showCopy  // for now i've removed the translation buttons
    //copyL10nEmailButton?.isHidden = !showCopy  // until i form some l10n plans
    #if !APP_STORE
    openDonationLinkButton?.isHidden = showCopy
    copyDonationLinkButton?.isHidden = !showCopy
    #endif
    openGitHubLinkButton?.isHidden = showCopy
    copyGitHubLinkButton?.isHidden = !showCopy
    openMaccyLinkButton?.isHidden = showCopy
    copyMaccyLinkButton?.isHidden = !showCopy
  }
  
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
  
}
