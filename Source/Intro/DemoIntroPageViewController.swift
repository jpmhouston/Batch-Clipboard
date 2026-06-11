//
//  DemoIntroPageViewController.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2026-06-11.
//  Copyright © 2026 Bananameter Labs. All rights reserved.
//

import AppKit

class DemoIntroPageViewController: IntroPageController {
  @IBOutlet var demoImage: NSImageView?
  @IBOutlet var demoCopyBubble: NSView?
  @IBOutlet var demoPasteBubble: NSView?
  
  private var demoTimer: DispatchSourceTimer?
  private var demoCanceled = false
  
  // MARK: -
  
  override func willShow() -> NSButton? {
    runDemo()
    return nil
  }
  
  override func shouldLeave() -> Bool {
    cancelDemo()
    return true
  }
  
  deinit {
    cancelDemo()
  }
  
  // MARK: -
  
  // swiftlint:disable nesting
  // swiftlint:disable colon
  private func runDemo() {
    let startInterval: Double = 2.5
    let normalFrameInterval: Double = 2.0
    let cursorMoveFrameInterval: Double = 1.0
    let swapFrameInterval: Double = 2.5
    let copyBalloonTime: Double = 0.75
    let prePasteBalloonTime: Double = 0.25
    let postPasteBalloonTime: Double = 0.5
    let endHoldInterval: Double = 5.0
    let repeatTransitionInterval: Double = 1.0
    
    enum Frame {
      case img(_ name: String?, keepBubble: Bool = false, _ interval: Double)
      case copybubble(show: Bool = true, _ interval: Double)
      case pastebubble(show: Bool = true, _ interval: Double)
    }
    let frames: [Frame] = [
      .img("introDemo1", startInterval),
      .img("introDemo2", copyBalloonTime), .copybubble(normalFrameInterval - copyBalloonTime),
      .img("introDemo3", copyBalloonTime), .copybubble(normalFrameInterval - copyBalloonTime),
      .img("introDemo4", copyBalloonTime), .copybubble(normalFrameInterval - copyBalloonTime),
      .img("introDemo5", swapFrameInterval), .pastebubble(prePasteBalloonTime),
      .img("introDemo6", keepBubble:true, postPasteBalloonTime), .pastebubble(show:false, normalFrameInterval - postPasteBalloonTime),
      .img("introDemo7", cursorMoveFrameInterval - prePasteBalloonTime), .pastebubble(prePasteBalloonTime),
      .img("introDemo8", keepBubble:true, postPasteBalloonTime), .pastebubble(show:false, normalFrameInterval - postPasteBalloonTime),
      .img("introDemo9", cursorMoveFrameInterval - prePasteBalloonTime), .pastebubble(prePasteBalloonTime),
      .img("introDemo10", keepBubble:true, postPasteBalloonTime), .pastebubble(show:false, endHoldInterval - postPasteBalloonTime),
      .img(nil, repeatTransitionInterval)
    ]
    
    // sanity check frames array not empty here so no need to check anywhere below
    guard frames.count > 0 else {
      return
    }
    
    func showFrame(_ index: Int) {
      let interval: Double
      switch frames[index] {
      case .img(let name, let keepBubble, let t):
        if !keepBubble {
          demoCopyBubble?.isHidden = true
          demoPasteBubble?.isHidden = true
        }
        if let name = name {
          demoImage?.image = NSImage(named: name)
        } else {
          demoImage?.image = nil
        }
        interval = t
        
      case .copybubble(let show, let t):
        demoCopyBubble?.isHidden = !show
        interval = t
        
      case .pastebubble(let show, let t):
        demoPasteBubble?.isHidden = !show
        interval = t
      }
      
      guard !self.demoCanceled else {
        return
      }
      runOnDemoTimer(afterDelay: interval) { [weak self] in
        guard let self = self, !self.demoCanceled else {
          return
        }
        if index + 1 < frames.count {
          showFrame(index + 1)
        } else {
          showFrame(0)
        }
      }
    }
    
    // kick off perpetual sequence
    demoCopyBubble?.isHidden = true
    demoPasteBubble?.isHidden = true
    demoCanceled = false
    showFrame(0)
  }
  // swiftlint:enable nesting
  // swiftlint:enable colon
  
  private func cancelDemo() {
    // If this func is called from the main thread, the runDemo sequence must be now blocked by the timer.
    // If this cancel is too late and callback within runDemo runs anyhow, it will stop safely because
    // either a) self not nil but demoCanceled flag will cause abort, or b) self=nil and closure aborts.
    // When called from deinit it must be that all strong references to self are gone so it's again
    // in the timer or the async dispatch in the timerFor.. method below, so will have case b). A-ok.
    demoCanceled = true
    cancelDemoTimer()
  }
  
  private func runOnDemoTimer(afterDelay delay: Double, _ action: @escaping () -> Void) {
    demoTimer?.cancel()
    demoTimer = DispatchSource.scheduledTimerForRunningOnMainQueue(afterDelay: delay) { [weak self] in
      self?.demoTimer = nil // doing this before calling closure supports closure itself calling runOnDemoTimer
      action()
    }
  }
  
  private func cancelDemoTimer() {
    demoTimer?.cancel()
    demoTimer = nil
  }
}
