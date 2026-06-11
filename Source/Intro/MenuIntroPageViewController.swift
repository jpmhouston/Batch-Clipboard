//
//  MenuIntroPageViewController.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2026-06-11.
//  Copyright © 2026 Bananameter Labs. All rights reserved.
//

import AppKit

class MenuIntroPageViewController: IntroPageController {
  @IBOutlet var specialCopyPasteBehaviorLabel: NSTextField?
  @IBOutlet var filledIconLabel: NSTextField?
  
  override func viewDidLoad() {
    Self.styleLabels([specialCopyPasteBehaviorLabel, filledIconLabel].compactMap { $0 })
  }
}
