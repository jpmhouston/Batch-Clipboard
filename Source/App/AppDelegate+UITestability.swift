//
//  AppDelegate+UITestability.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-05-09.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//

import AppKit

extension AppDelegate {
  
  // until i re-architect use allow a mock clipboard object, the real clipboard obj should have
  // this special case in invokeApplicationCopy():
  //  if AppDelegate.shouldFakeAppInteraction {
  //    copy(AppDelegate.fakedAppCopy, excludeFromHistory: false)
  //    action()
  //    return
  //  }
  // and in invokeApplicationPaste():
  //  if AppDelegate.shouldFakeAppInteraction {
  //    AppDelegate.fakedAppPaste = <some representation of clipboard contents>
  //    action()
  //    return
  //  }
  
#if !DEBUG
  static var performingUITest: Bool { false }
  static var shouldFakeAppInteraction: Bool { false }
#else
  static var performingUITest: Bool {
    CommandLine.arguments.contains("ui-testing")
  }
  static var shouldFakeAppInteraction: Bool {
    CommandLine.arguments.contains("ui-testing")
  }
#endif
  
  // The remaining fakery is now reimplemented in Clipboard where it's unsable from unit tests 
  
#if false
  static let fakeCopyText = [ "abc", "123", "xyz", "!@#" ]
  
  static var fakeCopyCountAssocObjKey: Int8 = 0
  var fakeCopyCount: Int? {
    get {
      objc_getAssociatedObject(self, &Self.fakeCopyCountAssocObjKey) as? Int
    }
    set {
      objc_setAssociatedObject(self, &Self.fakeCopyCountAssocObjKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
  }
  
  static var fakedAppCopy: String {
    guard let self = (NSApp.delegate as? Self) else { return fakeCopyText.first ?? "" }
    let i = self.fakeCopyCount ?? 0
    self.fakeCopyCount = i + 1
    return fakeCopyText[i % fakeCopyText.count]
  }
  
  static var fakePasteAssocObjKey: Int8 = 0
  static var fakePasteBuffAssocObjKey: Int8 = 0
  var fakedPasteDescriptions: [String] {
    get {
      objc_getAssociatedObject(self, &Self.fakePasteAssocObjKey) as? [String] ?? []
    }
    set {
      objc_setAssociatedObject(self, &Self.fakePasteAssocObjKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
  }
  var fakedPasteBuffer: String {
    get {
      objc_getAssociatedObject(self, &Self.fakePasteBuffAssocObjKey) as? String ?? ""
    }
    set {
      objc_setAssociatedObject(self, &Self.fakePasteBuffAssocObjKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
  }
  
  static var fakedAppPaste: String {
    get {
      (NSApp.delegate as? Self)?.fakedPasteDescriptions.first ?? ""
    }
    set {
      guard let self = (NSApp.delegate as? Self) else { return }
      self.fakedPasteDescriptions.append(newValue)
      self.fakedPasteBuffer = self.fakedPasteBuffer + newValue
    }
  }
  
  static func putPasteHistoryOnClipboard() {
    Clipboard.shared.copy((NSApp.delegate as? Self)?.fakedPasteDescriptions.joined() ?? "")
  }
  
  // MARK: -
  
  // the test window plan didn't work, uitests weren't able to send events to the textview for some reason
  // leave code here in case its useful later though
  
  // it was intended to be hooked into fakedAppCopy / fakedAppPaste, but never did figure out exactly
  // how to make use of it, a buffer for paste output makes sense, but how does that help copying? 
  
  static var allowTestWindow: Bool {
    //CommandLine.arguments.contains("ui-testing")
    false
  }
  
  static var testWindowAssocObjKey: Int8 = 0
  var testWindow: NSWindow? {
    // thx to https://stackoverflow.com/a/73839279/592739
    get {
      objc_getAssociatedObject(self, &Self.testWindowAssocObjKey) as? NSWindow
    }
    set {
      objc_setAssociatedObject(self, &Self.testWindowAssocObjKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
  }
  
  static var isTestWindowOpen: Bool {
    if let testWindow = (NSApp.delegate as? Self)?.testWindow, testWindow.isVisible {
      return true
    }
    return false
  }
  
  static var testTextView: NSTextView? {
    if let testWindow = (NSApp.delegate as? Self)?.testWindow, testWindow.isVisible {
      return testWindow.firstResponder as? NSTextView
    }
    return nil
  }
  
  func makeTestWindow() {
    let window = NSPanel(contentRect: NSRect(x: 20, y: 20, width: 300, height: 150), styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
    //let window = NSWindow(contentRect: NSRect(x: 20, y: 20, width: 300, height: 150), styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
    window.titlebarAppearsTransparent = true
    window.hidesOnDeactivate = false
    window.isReleasedWhenClosed = true
    //window.level = .floating
    window.collectionBehavior = [.transient, .fullScreenNone, .fullScreenDisallowsTiling, .moveToActiveSpace, .ignoresCycle]
    window.title = "Cleepp Test Window"
    // using option 4 from https://github.com/lukakerr/NSWindowStyles
    let visualEffect = NSVisualEffectView()
    visualEffect.blendingMode = .behindWindow
    visualEffect.state = .active
    visualEffect.material = .underPageBackground
    window.contentView = visualEffect
    let contentView = visualEffect
    // programmatic setup somewhat according to https://stackoverflow.com/a/19176892/592739
    let scrollView = NSScrollView(frame: window.contentLayoutRect)
    scrollView.autoresizingMask = [.width, .height]
    scrollView.borderType = .noBorder
    scrollView.hasVerticalScroller = true
    contentView.addSubview(scrollView)
    let textView = NSTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
    textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
    textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = .width
    textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
    textView.textContainer?.widthTracksTextView = true
    scrollView.documentView = textView
    contentView.addSubview(scrollView)
    //
    window.makeFirstResponder(textView)
    testWindow = window
  }
  
  @objc func showTestWindow(_ sender: AnyObject) {
    if testWindow == nil {
      makeTestWindow()
    }
    testWindow?.makeKeyAndOrderFront(sender)
  }
  
  @objc func hideTestWindow(_ sender: AnyObject) {
    guard let window = testWindow else { return }
    window.close()
  }
  
#endif
  
}
