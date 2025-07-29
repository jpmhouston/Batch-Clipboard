//
//  RangedIntegerTextField.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-03-16.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//

import AppKit

class RangedIntegerTextField: NSTextField {
  
  typealias ChangeValidationAction = (Bool)->Void
  
  var allowEmpty = false
  var validationAction: ChangeValidationAction?
  
  init(acceptingRange range: Range<Int>, permittingEmpty: Bool, frame: NSRect, validationAction action: ChangeValidationAction? = nil) {
    super.init(frame: frame)
    configure(acceptingRange: range, permittingEmpty: permittingEmpty, validationAction: action)
  }
  
  init(acceptingRange range: ClosedRange<Int>, permittingEmpty: Bool, frame: NSRect, validationAction action: ChangeValidationAction? = nil) {
    super.init(frame: frame)
    configure(acceptingRange: range, permittingEmpty: permittingEmpty, validationAction: action)
  }
  
  init(permittingEmpty: Bool, frame: NSRect, validationAction action: ChangeValidationAction? = nil) {
    allowEmpty = permittingEmpty
    validationAction = action
    super.init(frame: frame)
    formatter = NumberFormatter()
  }
  
  override init(frame: NSRect) {
    super.init(frame: frame)
    formatter = NumberFormatter()
  }
  
  required init?(coder: NSCoder) {
    super.init(coder: coder)
  }
  
  func configure(acceptingRange range: Range<Int>, permittingEmpty: Bool, validationAction action: ChangeValidationAction? = nil) {
    let fmtr = NumberFormatter()
    fmtr.minimum = range.lowerBound as NSNumber
    fmtr.maximum = (!range.isEmpty ? range.upperBound - 1 : range.upperBound) as NSNumber
    fmtr.maximumFractionDigits = 0
    configure(withFormatter: fmtr, permittingEmpty: permittingEmpty, validationAction: action) 
  }
  
  func configure(acceptingRange range: ClosedRange<Int>, permittingEmpty: Bool, validationAction action: ChangeValidationAction? = nil) {
    let fmtr = NumberFormatter()
    fmtr.minimum = range.lowerBound as NSNumber
    fmtr.maximum = range.upperBound as NSNumber
    fmtr.maximumFractionDigits = 0
    configure(withFormatter: fmtr, permittingEmpty: permittingEmpty, validationAction: action) 
  }
  
  func configure(withFormatter fmtr: Formatter?, permittingEmpty: Bool, validationAction action: ChangeValidationAction? = nil) {
    formatter = fmtr
    allowEmpty = permittingEmpty
    validationAction = action
  }
  
  var isValid: Bool {
    if stringValue.isEmpty {
      return allowEmpty
    }
    // true if formatter successfully converts to a value
    return (formatter as? NumberFormatter)?.number(from: stringValue) != nil
//    guard let value = Int(stringValue) else {
//      return false
//    }
//    switch allowedRange {
//    case .open(let r):
//      return r.contains(value)
//    case .closed(let r):
//      return r.contains(value)
//    }
  }
  
  override func textDidChange(_ notification: Notification) {
    super.textDidChange(notification)
    validationAction?(isValid)
  }
  
  override func resignFirstResponder() -> Bool {
    return isValid
  }
  
}
