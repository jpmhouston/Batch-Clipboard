//
//  About.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-03-21.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//
//  Based on About.swift from the Maccy project
//  Portions Copyright © 2024 Alexey Rodionov. All rights reserved.
//

import Cocoa

// TODO: replace with a custom window
// so that: 1) intro button can be a real button 2) less cramped 3) can easily close programmatically

class About {
  
  private var blurb: NSAttributedString {
    return NSAttributedString(
      string: "Batch Clipboard adds the ability to\ncopy and paste many items together.",
      attributes: [.foregroundColor: NSColor.labelColor])
  }
  
  private var links: NSAttributedString {
    let string = NSMutableAttributedString(string: "Website │ GitHub │ Support",
                                           attributes: [.foregroundColor: NSColor.labelColor])
    string.addAttribute(.link, value: AppModel.homepageURL, range: NSRange(location: 0, length: 7))
    string.addAttribute(.link, value: AppModel.githubURL, range: NSRange(location: 10, length: 6))
    string.addAttribute(.link, value: AppModel.supportEmailURL, range: NSRange(location: 19, length: 7))
    #if APP_STORE
    string.append(NSAttributedString(string: "\n", attributes: [:]))
    let spacingStyle = NSMutableParagraphStyle()
    spacingStyle.maximumLineHeight = 3
    string.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: spacingStyle]))
    string.append(NSAttributedString(string: "Privacy Policy | App Store EULA",
                                     attributes: [.foregroundColor: NSColor.labelColor]))
    string.addAttribute(.link, value: AppModel.privacyPolicyURL, range: NSRange(location: 28, length: 14))
    string.addAttribute(.link, value: AppModel.appStoreUserAgreementURL, range: NSRange(location: 45, length: 14))
    #endif
    return string
  }
  
  private var introLink: NSAttributedString {
    let string = NSMutableAttributedString(string: "For details reopen the intro window.",
                                           attributes: [.foregroundColor: NSColor.labelColor])
    string.addAttribute(.link, value: AppModel.showIntroInAppURL, range: NSRange(location: 12, length: 23))
    return string
  }
  
  private var creditsLink: NSMutableAttributedString {
    let string = NSMutableAttributedString(string: "Credits and licenses: Show Licenses",
                                           attributes: [.foregroundColor: NSColor.labelColor])
    string.addAttribute(.link, value: AppModel.showLicensesInAppURL, range: NSRange(location: 22, length: 13))
    return string
  }
  
  private var newLine: NSAttributedString {
    return NSAttributedString(string: "\n")
  }
  
  private var shortSpacingLine: NSAttributedString {
    let spacingStyle = NSMutableParagraphStyle()
    spacingStyle.maximumLineHeight = 8
    return NSAttributedString(string: "\n", attributes: [.paragraphStyle: spacingStyle])
  }
  
  private var credits: NSAttributedString {
    let credits = NSMutableAttributedString(string: "", attributes: [.foregroundColor: NSColor.labelColor])
    credits.append(blurb)
    credits.append(newLine)
    credits.append(introLink)
    credits.append(newLine)
    credits.append(shortSpacingLine)
    credits.append(links)
    credits.append(newLine)
    credits.append(shortSpacingLine)
    credits.append(creditsLink)
    credits.setAlignment(.center, range: NSRange(location: 0, length: credits.length))
    return credits
  }
  
  private var version: String {
    let infoPlistVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    #if APP_STORE
    return infoPlistVersion + " for Mac App Store"
    #else
    return infoPlistVersion + " non-App Store build"
    #endif
  }
  
  @objc
  func openAbout() {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(options: [.credits: credits, .applicationVersion: version])
  }
}
