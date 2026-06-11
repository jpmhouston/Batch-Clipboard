//
//  SetAuthIntroPageViewController.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2026-06-11.
//  Copyright © 2026 Bananameter Labs. All rights reserved.
//

import AppKit

class SetAuthIntroPageViewController: IntroPageController {
  @IBOutlet var authorizationVerifiedEmoji: NSTextField?
  @IBOutlet var authorizationDeniedEmoji: NSTextField?
  
  // MARK: -
  
  override func willShow() -> NSButton? {
    authorizationVerifiedEmoji?.isHidden = true
    authorizationDeniedEmoji?.isHidden = true
    return nil
  }
  
  // MARK: -
  
  @IBAction func checkAccessibilityAuthorization(_ sender: AnyObject) {
    let isAuthorized = app.hasAccessibilityPermissionBeenGranted()
    authorizationVerifiedEmoji?.isHidden = !isAuthorized
    authorizationDeniedEmoji?.isHidden = isAuthorized
  }
}
