//
//  Preview.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-07-10.
//  Portions Copyright © 2025 Bananameter Labs. All rights reserved.
//
//  Based on Preview.swift from the Maccy project
//  Portions Copyright © 2024 Alexey Rodionov. All rights reserved.
//

import Cocoa
import KeyboardShortcuts

class Preview: NSViewController {
  @IBOutlet weak var textView: NSTextField!
  @IBOutlet weak var imageView: NSImageView!
  @IBOutlet weak var applicationValueLabel: NSTextField!
  @IBOutlet weak var firstCopyTimeValueLabel: NSTextField!
  @IBOutlet weak var lastCopyTimeValueLabel: NSTextField!
  @IBOutlet weak var numberOfCopiesValueLabel: NSTextField!
  @IBOutlet weak var deleteLabel: NSTextField!
  @IBOutlet weak var pinLabel: NSTextField!
  @IBOutlet weak var copyLabel: NSTextField!
  @IBOutlet weak var startLabel: NSTextField!
  
  private let maxTextSize = 1_500
  
  private var item: Clip?
  
  convenience init(item: Clip?) {
    self.init()
    self.item = item
  }
  
  override func viewDidLoad() {
    guard let item, !item.isFault else { return }
    
    if let image = item.image {
      textView.removeFromSuperview()
      imageView.image = image
      // Preserver image aspect ratio
      let aspect = image.size.height / image.size.width
      imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor, multiplier: aspect).isActive = true
      imageView.wantsLayer = true
      imageView.layer?.borderWidth = 1.0
      imageView.layer?.borderColor = NSColor.separatorColor.cgColor
      imageView.layer?.cornerRadius = 7.0
      imageView.layer?.masksToBounds = true
    } else if !item.fileURLs.isEmpty {
      imageView.removeFromSuperview()
      textView.stringValue = item.fileURLs
        .compactMap { $0.absoluteString.removingPercentEncoding }
        .joined(separator: "\n")
    } else if let string = item.rtf?.string {
      imageView.removeFromSuperview()
      textView.stringValue = string
    } else if let string = item.html?.string {
      imageView.removeFromSuperview()
      textView.stringValue = string
    } else if let string = item.text {
      imageView.removeFromSuperview()
      textView.stringValue = string
    } else {
      imageView.removeFromSuperview()
      textView.stringValue = item.title ?? ""
    }
    
    loadApplication(item)
    
    if textView.stringValue.count > maxTextSize {
      textView.stringValue = textView.stringValue.shortened(to: maxTextSize)
    }
    
    firstCopyTimeValueLabel.stringValue = formatDate(item.firstCopiedAt)
    
    startLabel.isHidden = !AppModel.allowReplayFromHistory
  }
  
  private func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d, H:mm:ss"
    formatter.timeZone = TimeZone.current
    return formatter.string(from: date)
  }
  
  private func loadApplication(_ item: Clip) {
    if item.universalClipboard {
      applicationValueLabel.stringValue = "iCloud"
      return
    }
    
    guard let bundle = item.application,
          let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else {
      applicationValueLabel.removeFromSuperview()
      return
    }
    
    applicationValueLabel.stringValue = url.deletingPathExtension().lastPathComponent
  }
  
}
