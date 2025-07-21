//
//  ProxyMenu.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-07-10.
//  Portions Copyright © 2025 Bananameter Labs. All rights reserved.
//
//  Based on MenuLoader.swift from the Maccy project
//  Portions Copyright © 2024 Alexey Rodionov. All rights reserved.
//
import AppKit

// Dummy menu for NSStatusItem which allows to asynchronously
// execute callback when it's being opened. This gives us an
// possibility to load other menu in a non-blocking manner.
// See Maccy.withFocus() for more details about why this is needed.
class ProxyMenu: NSMenu, NSMenuDelegate {
  typealias LoaderCallback = (NSEvent.ModifierFlags, Bool) -> Void
  private var loader: LoaderCallback!

  required init(coder decoder: NSCoder) {
    super.init(coder: decoder)
  }

  init(_ loader: @escaping LoaderCallback) {
    super.init(title: "Loader")
    addItem(withTitle: "Loading…", action: nil, keyEquivalent: "")
    self.delegate = self
    self.loader = loader
  }

  func menuWillOpen(_ menu: NSMenu) {
    guard let event = NSApp.currentEvent else { return }
    let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let isRightClick = (event.type == .rightMouseDown || event.type == .rightMouseUp) // maybe only need down
    
    menu.cancelTrackingWithoutAnimation()
    // Just calling loader() doesn't work when avoidTakingFocus is true.
    Timer.scheduledTimer(withTimeInterval: 0.01, repeats: false) { _ in
      self.loader(modifierFlags, isRightClick)
    }
  }
}
