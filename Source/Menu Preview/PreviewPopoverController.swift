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

  func showPopover(for menuItem: ClipMenuItem, allClips: [AppMenu.ClipRecord]) {
    previewThrottle.throttle { [self] in
      let popover = NSPopover()
      popover.animates = false
      popover.behavior = .semitransient
      popover.contentViewController = Preview(item: menuItem.clipItem)

      guard let window = NSApp.menuWindow,
            let windowContentView = window.contentView,
            let boundsOfVisibleMenuItem = boundsOfMenuItem(menuItem, windowContentView, allClips) else {
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

  private func boundsOfMenuItem(
    _ menuItem: NSMenuItem,
    _ windowContentView: NSView,
    _ allClips: [AppMenu.ClipRecord]
  ) -> NSRect? {
    if #available(macOS 14, *) {
      let windowRectInScreenCoordinates = windowContentView.accessibilityFrame()
      let menuItemRectInScreenCoordinates = menuItem.accessibilityFrame()
      return NSRect(
        origin: NSPoint(
          x: menuItemRectInScreenCoordinates.origin.x - windowRectInScreenCoordinates.origin.x,
          y: menuItemRectInScreenCoordinates.origin.y - windowRectInScreenCoordinates.origin.y),
        size: menuItemRectInScreenCoordinates.size
      )
    } else {
      guard let menuItem = menuItem as? ClipMenuItem,
            let itemIndex = allClips.firstIndex(where: { $0.menuItems.contains(menuItem) }) else {
        return nil
      }
      let indexedItem = allClips[itemIndex]
      guard let previewView = indexedItem.popoverAnchor!.view else {
        return nil
      }

      func getPrecedingView() -> NSView? {
        for index in (0..<itemIndex).reversed() {
          // PreviewMenuItem always has a view
          // Check if preview item is visible (it may be hidden by the search filter)
          if let view = allClips[index].popoverAnchor?.view,
             view.window != nil {
            return view
          }
        }
        // If the item is the first visible one, the preceding view is the header.
        guard let header = menuItem.menu?.items.first?.view else {
          // Should never happen as we always have a MenuHeader installed.
          return nil
        }
        return header
      }

      guard let precedingView = getPrecedingView() else {
        return nil
      }

      let bottomPoint = previewView.convert(
        NSPoint(x: previewView.bounds.minX, y: previewView.bounds.maxY),
        to: windowContentView
      )
      let topPoint = precedingView.convert(
        NSPoint(x: previewView.bounds.minX, y: precedingView.bounds.minY),
        to: windowContentView
      )

      let heightOfVisibleMenuItem = abs(topPoint.y - bottomPoint.y)
      return NSRect(
        origin: bottomPoint,
        size: NSSize(width: menuItem.menu?.size.width ?? 0, height: heightOfVisibleMenuItem)
      )
    }
  }

  func cancelPopover() {
    previewThrottle.cancel()
    previewPopover?.close()
    previewPopover = nil
  }
}
