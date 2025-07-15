//
//  EmptyPermittingNumberFormatter.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2025-07-14.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//

import AppKit

class EmptyPermittingNumberFormatter : NumberFormatter, @unchecked Sendable {
  
  var emptyPermitted = false
  
  override func string(for value: Any?) -> String? {
    if emptyPermitted && value == nil {
      return ""
    }
    return super.string(for: value)
  }
  
  override func isPartialStringValid(_ partialString: String,
                                     newEditingString newString: AutoreleasingUnsafeMutablePointer<NSString?>?,
                                     errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool
  {
    if emptyPermitted && partialString.isEmpty {
      return true
    }
    return super.isPartialStringValid(partialString, newEditingString: newString, errorDescription: error)
  }
  
}
