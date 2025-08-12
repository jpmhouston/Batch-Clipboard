//
//  ClipMenuItem.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-07-10.
//  Portions Copyright © 2025 Bananameter Labs. All rights reserved.
//
//  Based on HistoryMenuItem.swift from the Maccy project
//  Portions Copyright © 2024 Alexey Rodionov. All rights reserved.
//

import AppKit

//extension NSAttributedString.Key {
//  static let headIndicator: Self = .init("batchclipqueuehead")
//}

class ClipMenuItem: NSMenuItem {
  var clip: Clip?
  var value = "" // yes, title and valus string are kind of the same, but not exactly and need both
  var groupIndex = 0
  var groupCount = 0 
  
  var isHeadOfQueue = false {
    didSet { updateHeadOfQueueIndication() }
  }
  
  private let indicatorBadge = NSLocalizedString("first_replay_item_badge", comment: "") + " \u{2BAD}"
  private var useBadges: Bool {
    // return false and comment the rest out to exercise not using badges when on macOS >=14
    if #unavailable(macOS 14) {
      false
    } else {
      !AppDelegate.performingUITest // use badges unless running a UI test
    }
  }
  
  private let imageMaxWidth: CGFloat = 340.0

  // Assign "empty" title to the image (but it can't be empty string).
  // This may still be required for onStateImage to render correctly at times
  // (in Maccy it was when item was pinned). Otherwise, it's not rendered with the error:
  //
  // GetEventParameter(inEvent, kEventParamMenuTextBaseline, typeCGFloat, NULL, sizeof baseline, NULL, &baseline)
  // returned error -9870 on line 2078 in -[NSCarbonMenuImpl _carbonDrawStateImageForMenuItem:withEvent:]
  private let imageTitle = " "

  private let systemFont: NSFont = {
    if #available(macOS 11, *) {
      return NSFont.systemFont(ofSize: 13)
    } else {
      return NSFont.systemFont(ofSize: 14)
    }
  }()

  private let systemBoldFont: NSFont = {
    if #available(macOS 11, *) {
      return NSFont.boldSystemFont(ofSize: 13)
    } else {
      return NSFont.boldSystemFont(ofSize: 14)
    }
  }()

  private let systemItalicFont: NSFont = {
    var systemFont: NSFont
    if #available(macOS 11, *) {
      systemFont = NSFont.systemFont(ofSize: 13)
    } else {
      systemFont = NSFont.systemFont(ofSize: 14)
    }

    let italicFontDescriptor = systemFont.fontDescriptor.withSymbolicTraits([.italic])

    return NSFont(descriptor: italicFontDescriptor, size: 0) ?? systemFont
  }()
  
  // TODO: i think ok to renmove clipboard property
  
  internal var clipboard: Clipboard!
  
  required init(coder: NSCoder) {
    super.init(coder: coder)
  }
  
  // define this to avoid a mysterious runtime failure:
  // Fatal error: Use of unimplemented initializer 'init(title:action:keyEquivalent:)' for class 'Batch_Clipboard.ClipMenuItem'
  override init(title: String, action: Selector?, keyEquivalent: String) {
    super.init(title: title, action: action, keyEquivalent: keyEquivalent)
  }
  
  func configured(withClip clip: Clip, num: Int, of count: Int, distinguishForDebugging: Bool = false) -> Self {
    groupIndex = num - 1
    groupCount = count
    self.clip = clip
    self.value = clip.value
    
    if clip.isImage {
      loadImage(clip)
    } else if clip.isFile {
      loadFile(clip)
    } else if clip.isText {
      loadText(clip)
    } else if clip.isRTF {
      loadRTF(clip)
    } else if clip.isHTML {
      loadHTML(clip)
    }
    
    if distinguishForDebugging {
      let attributedTitle = NSMutableAttributedString(string: title, attributes: [.underlineStyle: NSUnderlineStyle.single.rawValue])
      self.attributedTitle = attributedTitle
    }
    return self
  }
  
  func alternate() {
    isAlternate = true
    // isHidden is implicit in macOS 14.4 and completely prevents selecting hidden item.
    if #unavailable(macOS 14.4) {
      isHidden = true
    }
  }
  
  func resizeImage() {
    guard let clip, !clip.isImage else {
      return
    }
    
    loadImage(clip)
  }
  
  func regenerateTitle() {
    guard let clip, !clip.isImage else {
      return
    }
    
    let newTitle = clip.generateTitle()
    clip.title = newTitle
    title = newTitle
  }
  
  func highlight(_ ranges: [ClosedRange<Int>]) {
    guard !ranges.isEmpty, title != imageTitle else {
      self.attributedTitle = nil
      return
    }
    
    let attributedTitle = NSMutableAttributedString(string: title)
    for range in ranges {
      let rangeLength = range.upperBound - range.lowerBound + 1
      let highlightRange = NSRange(location: range.lowerBound, length: rangeLength)
      
      if Range(highlightRange, in: title) != nil {
        switch UserDefaults.standard.highlightMatches {
        case "italic":
          attributedTitle.addAttribute(.font, value: systemItalicFont, range: highlightRange)
        case "underline":
          attributedTitle.addAttributes([
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .font: systemFont
          ], range: highlightRange)
        default:
          attributedTitle.addAttribute(.font, value: systemBoldFont, range: highlightRange)
        }
      }
    }
    
    self.attributedTitle = attributedTitle
    
    if isHeadOfQueue && !useBadges {
      styleToIndicateHeadOfQueue()
    }
  }
  
  private func loadImage(_ clip: Clip) {
    guard let image = clip.image else {
      return
    }
    
    if image.size.width > imageMaxWidth {
      image.size.height /= image.size.width / imageMaxWidth
      image.size.width = imageMaxWidth
    }
    
    let imageMaxHeight = CGFloat(UserDefaults.standard.imageMaxHeight)
    if image.size.height > imageMaxHeight {
      image.size.width /= image.size.height / imageMaxHeight
      image.size.height = imageMaxHeight
    }
    
    self.image = image
    self.title = imageTitle
  }
  
  private func loadFile(_ clip: Clip) {
    self.title = clip.title ?? ""
    self.image = ColorImage.from(title)
  }
  
  private func loadRTF(_ clip: Clip) {
    self.title = clip.title ?? ""
    self.image = ColorImage.from(title)
  }
  
  private func loadHTML(_ clip: Clip) {
    self.title = clip.title ?? ""
    self.image = ColorImage.from(title)
  }
  
  private func loadText(_ clip: Clip) {
    self.title = clip.title ?? ""
    self.image = ColorImage.from(title)
  }
  
  private func updateHeadOfQueueIndication() {
    if useBadges {
      badgeToIndicateHeadOfQueue()
    } else {
      styleToIndicateHeadOfQueue()
    }
  }
  
  private func badgeToIndicateHeadOfQueue() {
    if #available(macOS 14, *) {
      if isHeadOfQueue {
        badge = NSMenuItemBadge(string: indicatorBadge)
      } else {
        badge = nil
      }
    }
  }
  
  private func styleToIndicateHeadOfQueue() {
    // not bulletproof, adding to attributedTitle adds to title too
//    let indicatorPrefix = "\u{261D}\u{FE0E} "
//    var indicatorPrefixLength: Int { (indicatorPrefix as NSString).length }
//    guard title != imageTitle else {
//      return
//    }
//    if let currentStyledTitle = attributedTitle {
//      let indicatorAttributes: [NSAttributedString.Key: Any] = [.font: systemBoldFont, .headIndicator: NSNumber(value: true)]
//      let alreadyPrefixed = currentStyledTitle.attribute(.headIndicator, at: 0, effectiveRange: nil) != nil
//      
//      if isHeadOfQueue && !alreadyPrefixed {
//        let prefixedTitle = NSMutableAttributedString(string: indicatorPrefix as String, attributes: indicatorAttributes)
//        prefixedTitle.append(currentStyledTitle)
//        attributedTitle = prefixedTitle
//        
//      } else if !isHeadOfQueue && !alreadyPrefixed {
//        let unprefixedTitle = NSMutableAttributedString(attributedString: currentStyledTitle)
//        unprefixedTitle.deleteCharacters(in: NSRange(location: 0, length: indicatorPrefixLength))
//      }
//          
//    } else if isHeadOfQueue {
//      let styledTitle = NSMutableAttributedString(string: title, attributes: [.font: systemFont])
//      let prefixedTitle = NSMutableAttributedString(string: indicatorPrefix as String, attributes: [.font: systemBoldFont])
//      prefixedTitle.append(styledTitle)
//      attributedTitle = prefixedTitle
//    }
  }
  
}
