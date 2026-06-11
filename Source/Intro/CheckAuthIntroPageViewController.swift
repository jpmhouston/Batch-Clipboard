//
//  CheckAuthIntroPageViewController.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2026-06-11.
//  Copyright © 2026 Bananameter Labs. All rights reserved.
//

import AppKit

class CheckAuthIntroPageViewController: IntroPageController {
  @IBOutlet var openSecurityPanelButton: NSButton?
  @IBOutlet var openSecurityPanelSpinner: NSProgressIndicator?
  @IBOutlet var hasAuthorizationEmoji: NSTextField?
  @IBOutlet var needsAuthorizationEmoji: NSTextField?
  @IBOutlet var hasAuthorizationLabel: NSTextField?
  @IBOutlet var needsAuthorizationLabel: NSTextField?
  @IBOutlet var nextAuthorizationDirectionsLabel: NSTextField?
  
  var advancePageCallback: (()->Void)?
  var isAuthorized = false
  
  private let openSecurityPanelSpinnerTime = 1.25
  
  // MARK: -
  
  override func willShow() -> NSButton? {
    isAuthorized = app.hasAccessibilityPermissionBeenGranted()
    hasAuthorizationEmoji?.isHidden = !isAuthorized
    needsAuthorizationEmoji?.isHidden = isAuthorized
    hasAuthorizationLabel?.isHidden = !isAuthorized
    needsAuthorizationLabel?.isHidden = isAuthorized
    nextAuthorizationDirectionsLabel?.isHidden = isAuthorized
    openSecurityPanelButton?.isEnabled = !isAuthorized
    return !isAuthorized ? openSecurityPanelButton : nil
  }
  
  override func shouldLeave() -> Bool {
    openSecurityPanelSpinner?.stopAnimation(self)
    return true
  }
  
  // MARK: -
  
  @IBAction func openSettingsAppSecurityPanel(_ sender: AnyObject) {
    app.openSecurityPanel()
    
    // make window controller skip ahead to the next page after a delay
    guard let windowController = (self.view.window?.windowController as? IntroWindowController) else {
      return
    }
    openSecurityPanelSpinner?.startAnimation(sender)
    DispatchQueue.main.asyncAfter(deadline: .now() + openSecurityPanelSpinnerTime) { [weak self] in
      self?.openSecurityPanelSpinner?.stopAnimation(sender)
      windowController.advanceFromPage(.checkAuth)
    }
  }
}
