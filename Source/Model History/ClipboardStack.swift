//
//  ClipboardStack.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2026-05-05.
//  Copyright © 2026 Bananameter Labs. All rights reserved.
//

import AppKit
import os.log

class ClipboardStack {
  
  var clips: [Clip]
  var size: Int { clips.count } // { clips.count > 0 ? clips.count - 1 : 0 }
  var notEmpty: Bool { !clips.isEmpty }
  var isEmpty: Bool { clips.isEmpty }
  var isOn: Bool { notEmpty }
  var isOff: Bool { isEmpty } // remove this replace with notOn?
  var notOn: Bool { isEmpty }
  
  var first: Clip? { clips.first }
  var top: Clip? { clips.last }
  
  //better if these were protocols that can be easily mocked
  private let clipboard: Clipboard
  private let history: History
  
  init(clipboard c: Clipboard, history h: History) {
    clipboard = c
    history = h
    clips = []
  }
  
  func push() {
    if let clip = clipboard.newClipFromCurrent() {
      clips.append(clip)
    }
  }
  
  func pop(ontoClipboard alsoPutOnClipboard: Bool = true) {
    if let clip = clips.last {
      clips.removeLast()
      if alsoPutOnClipboard {
        clipboard.copy(clip, excludeFromHistory: true)
      }
    }
  }
  
}
