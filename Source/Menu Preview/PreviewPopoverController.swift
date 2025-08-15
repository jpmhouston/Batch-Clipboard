//
//  PreviewPopoverController.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-07-10.
//  Portions Copyright © 2025 Bananameter Labs. All rights reserved.
//
//  Based on PreviewPopoverController.swift from the Maccy project
//  Portions Copyright © 2024 Alexey Rodionov. All rights reserved.
//

import AppKit

class PreviewPopoverController {
  private static let popoverGap = 5.0
  private static let subsequentPreviewDelay = 0.2
  
  private var initialPreviewDelay: Double { Double(UserDefaults.standard.previewDelay) / 1000 }
  private lazy var previewThrottle = Throttler(minimumDelay: initialPreviewDelay)
  
  private var previewPopover: NSPopover?
  
  func menuWillOpen() {
    previewThrottle.minimumDelay = initialPreviewDelay
  }
  
  func menuDidClose() {
    cancelPopover()
  }
  
  func showPopover(for menuItem: ClipMenuItem, anchors: (NSView, NSView)? = nil) {
    previewThrottle.throttle { [self] in
      let popover = NSPopover()
      popover.animates = false
      popover.behavior = .semitransient
      popover.contentViewController = Preview(item: menuItem.clip)
      
      let window: NSWindow?
      if menuItem.parent != nil, let rect = screenFrameForMenuItem(menuItem, orAnchors:anchors) {
        window = NSApp.menuWindow(containing: rect)
      } else {
        window = NSApp.menuWindow
      }
      guard let window = window, let windowContentView = window.contentView,
            let boundsOfVisibleMenuItem = boundsOfMenuItem(menuItem, windowContentView, anchors) else {
        return
      }
      
      previewThrottle.minimumDelay = PreviewPopoverController.subsequentPreviewDelay
      
      popover.show(
        relativeTo: boundsOfVisibleMenuItem,
        of: windowContentView,
        preferredEdge: .maxX
      )
      previewPopover = popover
      
      if let popoverWindow = popover.contentViewController?.view.window {
        let gap = PreviewPopoverController.popoverGap
        if popoverWindow.frame.maxX <= window.frame.minX {
          popoverWindow.setFrameOrigin(
            NSPoint(x: popoverWindow.frame.minX - gap, y: popoverWindow.frame.minY)
          )
        } else if popoverWindow.frame.minX >= window.frame.maxX {
          popoverWindow.setFrameOrigin(
            NSPoint(x: popoverWindow.frame.minX + gap, y: popoverWindow.frame.minY)
          )
        }
      }
    }
  }
  
  private func screenFrameForMenuItem(_ menuItem: ClipMenuItem,
                                      orAnchors anchors: (NSView, NSView)?) -> NSRect? {
    if #available(macOS 14, *) {
      return menuItem.accessibilityFrame()
    }
    if let (view, _) = anchors {
      return view.convert(view.bounds, to: nil)
    }
    return nil
  }
  
  private func boundsOfMenuItem(_ menuItem: ClipMenuItem, _ windowContentView: NSView,
                                _ anchors: (NSView, NSView)?) -> NSRect? {
    if #available(macOS 14, *) {
      let windowRectInScreenCoordinates = windowContentView.accessibilityFrame()
      let menuItemRectInScreenCoordinates = menuItem.accessibilityFrame()
      return NSRect(
        origin: NSPoint(
          x: menuItemRectInScreenCoordinates.origin.x - windowRectInScreenCoordinates.origin.x,
          y: menuItemRectInScreenCoordinates.origin.y - windowRectInScreenCoordinates.origin.y),
        size: menuItemRectInScreenCoordinates.size
      )
    }
    
    guard let anchors = anchors else {
      return nil
    }
    let (leadingView, trailingView) = anchors
    
    let leadingPoint = leadingView.convert(
      NSPoint(x: leadingView.bounds.minX, y: leadingView.bounds.minY),
      to: windowContentView
    )
    let trailingPoint = trailingView.convert(
      NSPoint(x: trailingView.bounds.minX, y: trailingView.bounds.maxY),
      to: windowContentView
    )
    return NSRect(
      origin: trailingPoint,
      size: NSSize(width: menuItem.menu?.size.width ?? 0,
                   height: abs(leadingPoint.y - trailingPoint.y))
    )
  }
  
  func cancelPopover() {
    previewThrottle.cancel()
    previewPopover?.close()
    previewPopover = nil
  }
}
