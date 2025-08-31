//
//  ClickableTextField.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2025-08-30.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//
//  This is for the Intro panel with a switch and clickable labels on each side.
//  Should instead make a custom NSControl encompassing those elements.
//

import AppKit

@objc protocol ClickableTextFieldDelegate {
  @objc optional func clickDidOccur(on field: ClickableTextField)
}

class ClickableTextField: NSTextField {
  
  weak var clickDelegate: ClickableTextFieldDelegate?
  
  override func mouseDown(with event: NSEvent) {
    clickDelegate?.clickDidOccur?(on: self)
  }
  
}
