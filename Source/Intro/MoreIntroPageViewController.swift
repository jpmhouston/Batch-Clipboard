//
//  MoreIntroPageViewController.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2026-06-11.
//  Copyright © 2026 Bananameter Labs. All rights reserved.
//

import AppKit

class MoreIntroPageViewController: IntroPageController {
  @IBOutlet var manuallyEnterQueueModeLabel: NSTextField?
  @IBOutlet var manuallyStartReplayingLabel: NSTextField?
  @IBOutlet var batchItemsInMenuLabel: NSTextField?
  
  override func viewDidLoad() {
    Self.styleLabels([manuallyEnterQueueModeLabel, manuallyStartReplayingLabel, batchItemsInMenuLabel].compactMap { $0 })
  }
  
  // MARK: -
  
  @IBAction func openGeneralSettings(_ sender: AnyObject) {
    app.showSettings(selectingPane: .keyboard)
  }
  
}
