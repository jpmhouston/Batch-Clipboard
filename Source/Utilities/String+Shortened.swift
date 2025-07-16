//
//  String+Shortened.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-07-10.
//  Portions Copyright © 2025 Bananameter Labs. All rights reserved.
//
//  Based on String+Shortened.swift from the Maccy project
//  Portions Copyright © 2024 Alexey Rodionov. All rights reserved.
//

extension String {
  func shortened(to maxLength: Int) -> String {
    guard count > maxLength else {
      return self
    }

    let thirdMaxLength = maxLength / 3
    let indexStart = index(startIndex, offsetBy: thirdMaxLength * 2)
    let indexEnd = index(endIndex, offsetBy: -(thirdMaxLength + 1))
    return "\(self[...indexStart])...\(self[indexEnd...])"
  }
}
