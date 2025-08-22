//
//  SparkleDelegate.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2025-08-21.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//

import AppKit

#if SPARKLE_UPDATES
import Sparkle

class SparkleDelegate: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
  
  weak var model: AppModel?
  init(_ modelObj: AppModel) {
    model = modelObj
  }
  
  // MARK: -
  // https://sparkle-project.org/documentation/publishing/#publishing-an-update section Channels
  
  func allowedChannels(for updater: SPUUpdater) -> Set<String> {
    Set(UserDefaults.standard.sparkleUsesBetaFeed ? ["beta"] : [])
  }
  
  // MARK: -
  // https://sparkle-project.org/documentation/gentle-reminders/
  
  var supportsGentleScheduledUpdateReminders: Bool {
    true
  }
  
  func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                            andInImmediateFocus immediateFocus: Bool) -> Bool {
    return immediateFocus
  }
  
  func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                 forUpdate update: SUAppcastItem,
                                                 state: SPUUserUpdateState) {
    // sample code skips doing anything if handleShowingUpdate is true,
    // however we want to show the menu item either way
    model?.menu.displayUpdateAvailable(true)
  }
  
}
#endif
