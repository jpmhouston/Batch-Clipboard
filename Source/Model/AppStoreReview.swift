//
//  AppStoreReview.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-07-10.
//  Portions Copyright © 2025 Bananameter Labs. All rights reserved.
//
//  Based on AppStoreReview.swift from the Maccy project
//  Portions Copyright © 2024 Alexey Rodionov. All rights reserved.
//

import StoreKit

class AppStoreReview {
  class func ask(after times: Int = 50) {
    UserDefaults.standard.numberOfUsages += 1
    if UserDefaults.standard.numberOfUsages < times { return }

    let today = Date()
    let lastReviewRequestDate = UserDefaults.standard.lastReviewRequestedAt
    guard let minimumRequestDate = Calendar.current.date(byAdding: .month, value: 1, to: lastReviewRequestDate),
          today > minimumRequestDate else {
      return
    }

    UserDefaults.standard.lastReviewRequestedAt = today

    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
      SKStoreReviewController.requestReview()
    }
  }
}
