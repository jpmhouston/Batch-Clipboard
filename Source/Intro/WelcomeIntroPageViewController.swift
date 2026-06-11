//
//  WelcomeIntroPageViewController.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2026-06-11.
//  Copyright © 2026 Bananameter Labs. All rights reserved.
//

import AppKit
#if INTRO_ANIMATED_LOGO
import SDWebImage
#endif

class WelcomeIntroPageViewController: IntroPageController {
  @IBOutlet var staticLogoImage: NSImageView?
  #if INTRO_ANIMATED_LOGO
  @IBOutlet var animatedLogoImage: SDAnimatedImageView?
  #endif
  @IBOutlet var logoStopButton: NSButton?
  @IBOutlet var logoRestartButton: NSButton?
  @IBOutlet var setupNeededLabel: NSTextField?
  
  private var logoTimer: DispatchSourceTimer?
  
  override func viewDidLoad() {
    setupLogo()
  }
  
  // MARK: -
  
  override func willShow() -> NSButton? {
    #if INTRO_ANIMATED_LOGO
    if !visited.contains(page) {
      startAnimatedLogo(withDelay: true)
    } else {
      resetAnimatedLogo()
    }
    #endif
    
    if app.hasAccessibilityPermissionBeenGranted() {
      setupNeededLabel?.isHidden = true
    }
    return nil
  }
  
  override func shouldLeave() -> Bool {
    #if INTRO_ANIMATED_LOGO
    stopAnimatedLogo()
    #endif
    return true
  }
  
  // MARK: -
  
  @IBAction func stopLogoAnimation(_ sender: AnyObject) {
    #if INTRO_ANIMATED_LOGO
    stopAnimatedLogo()
    #endif
  }
  
  @IBAction func restartLogoAnimation(_ sender: AnyObject) {
    #if INTRO_ANIMATED_LOGO
    startAnimatedLogo()
    #endif
  }
  
  // MARK: -
  
  private func setupLogo() {
    #if INTRO_ANIMATED_LOGO // note, app currently has no animated logo
    animatedLogoImage?.autoPlayAnimatedImage = false
    animatedLogoImage?.isHidden = true
    logoStopButton?.isHidden = true
    
    // replace NSImage loaded from the nib with a SDAnimatedImage
    guard let name = animatedLogoImage?.image?.name(), let sdImage = SDAnimatedImage(named: name + ".gif") else {
      logoRestartButton?.isHidden = true
      return
    }
    animatedLogoImage?.image = sdImage
    logoRestartButton?.isHidden = false
    #else
    logoStopButton?.isHidden = true
    logoRestartButton?.isHidden = true
    #endif
  }
  
  #if INTRO_ANIMATED_LOGO
  private func resetAnimatedLogo() {
    stopAnimatedLogo() // show static logo initially
  }

  private func stopAnimatedLogo() {
    cancelLogoTimer()
    animatedLogoImage?.player?.stopPlaying()
    animatedLogoImage?.isHidden = true
    logoStopButton?.isHidden = true
    logoRestartButton?.isHidden = false
  }

  private func startAnimatedLogo(withDelay useDelay: Bool = false) {
    let initialDelay = 2.0
    
    // reset player to the start and setup to stop after a loop completes
    guard let gifPlayer = animatedLogoImage?.player else {
      return
    }
    gifPlayer.seekToFrame(at: 0, loopCount: 0)
    gifPlayer.animationLoopHandler = { [weak self] loop in
      self?.stopAnimatedLogo()
    }
    
    // start with gif hidden, for a few seconds if useDelay is true
    animatedLogoImage?.isHidden = true
    logoStopButton?.isHidden = false
    logoRestartButton?.isHidden = true
    
    if !useDelay {
      animatedLogoImage?.isHidden = false
      gifPlayer.startPlaying()
    } else {
      runOnLogoDelayTimer(withDelay: initialDelay) { [weak self] in
        self?.animatedLogoImage?.isHidden = false
        self?.animatedLogoImage?.player?.startPlaying()
      }
    }
  }
  
  private func runOnLogoDelayTimer(withDelay delay: Double, _ action: @escaping () -> Void) {
    logoTimer?.cancel()
    logoTimer = DispatchSource.scheduledTimerForRunningOnMainQueue(afterDelay: delay) { [weak self] in
      self?.logoTimer = nil
      action()
    }
  }
  
  func cancelLogoTimer() {
    logoTimer?.cancel()
    logoTimer = nil
  }
  #endif // INTRO_ANIMATED_LOGO
}
