//
//  Intro.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-03-01.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//

import AppKit
import os.log

extension NSWindow.FrameAutosaveName {
  static let introWindow: NSWindow.FrameAutosaveName = "lol.bananameter.batchclip.intro.FrameAutosaveName"
}

class IntroWindowController: PagedWindowController {
  @IBOutlet var welcomePageController: WelcomeIntroPageViewController!
  @IBOutlet var checkAuthPageController: CheckAuthIntroPageViewController!
  @IBOutlet var setAuthPageController: SetAuthIntroPageViewController!
  @IBOutlet var historyChoicePageController: HistoryChoiceIntroPageViewController!
  @IBOutlet var demoPageController: DemoIntroPageViewController!
  @IBOutlet var menuPageController: MenuIntroPageViewController!
  @IBOutlet var morePageController: MoreIntroPageViewController!
  @IBOutlet var linksPageController: LinksIntroPageViewController!
  
  var pageViewControllers: [IntroPageController] = []
  var pagesController: IntroPagesController?
  
  // if pageControllerOutlets/Instances are in the desired order its just coincidence
  lazy var pageControllerOutlets: [IntroPageController?] = [ welcomePageController,
                                                             checkAuthPageController, setAuthPageController,
                                                             historyChoicePageController, demoPageController,
                                                             menuPageController, morePageController,
                                                             linksPageController ]
  lazy var pageControllerInstances: [IntroPageController] = pageControllerOutlets.compactMap({ $0 })
  
  enum Page: Int, CaseIterable {
    case welcome = 0, checkAuth, setAuth, historyChoice, demo, aboutMenu, aboutMore, links
    var pageType: (some IntroPageController).Type {
      switch self {
      case .welcome: WelcomeIntroPageViewController.self
      case .checkAuth: CheckAuthIntroPageViewController.self
      case .setAuth: SetAuthIntroPageViewController.self
      case .historyChoice: HistoryChoiceIntroPageViewController.self
      case .demo: DemoIntroPageViewController.self
      case .aboutMenu: MenuIntroPageViewController.self
      case .aboutMore: MoreIntroPageViewController.self
      case .links: LinksIntroPageViewController.self
      }
    }
  }
  
  convenience init() {
    self.init(windowNibName: "Intro")
  }
  
  func openIntro(atPage page: Page? = nil, with object: AppModel) {
    // if already loaded then also check if already onscreen, if so being to the front and that's all
    // (continuing anyway works, except for the restoreWindowPosition() call, until the window is
    // closed there's no cached window position and its reset to the center of the screen below)
    if isWindowLoaded, let window = window, window.isVisible {
      window.orderFrontRegardless()
      return
    }
    
    // accessing window triggers loading from nib, do this before showWindow so we can setup before showing
    guard let window = window, pageControllerInstances.count == pageControllerOutlets.count else {
      return
    }
    
    if pagesController == nil {
      // only initialize pagesController and the window's sub views _once_
      pageViewControllers = [] // build pageViewControllers in the order of thge Page enum cases
      Page.allCases.forEach { page in
        if let instance = pageControllerInstances.first(where: { type(of: $0) == page.pageType }) {
          pageViewControllers.append(instance)
        }
      }
      
      pagesController = IntroPagesController(withApp: object, pageControllers: pageViewControllers)
      pageDelegate = pagesController
      useViews(pagesController!.pageViews, withHeightScaling: heightScaleForLanguage())
    }
    
    pagesController?.startPage = if let page = page {
      pagesController?.pageIndex(for:  page.pageType)
    } else {
      nil 
    }
    
    reset()
    
    showWindow(self)
    restoreWindowPosition()
    #if compiler(>=5.9) && canImport(AppKit)
    if #available(macOS 14, *) {
      NSApp.activate()
    } else {
      NSApp.activate(ignoringOtherApps: true)
    }
    #else
    NSApp.activate(ignoringOtherApps: true)
    #endif
    
    window.collectionBehavior.formUnion(.moveToActiveSpace)
    window.orderFrontRegardless()
    
    #if DEBUG
    addDebugButton()
    #endif
  }
  
  var historyPageController: HistoryChoiceIntroPageViewController? {
    pagesController?.pageController(for: HistoryChoiceIntroPageViewController.self)
  }
  
  func advanceFromPage(_ page: Page) {
    if isOpen && currentPageNumber == page.rawValue {
      advance(self)
    }
  }
  
  private func restoreWindowPosition() {
    guard let window else {
      return
    }
    
    window.center()
    window.setFrameUsingName(.introWindow)
    window.setFrameAutosaveName(.introWindow)
  }
  
  private func heightScaleForLanguage() -> Double {
    let introResizePerLanguage = UserDefaults.standard.introResizeFactors // default is ["en": 1.0]
    let appLanguageCode = Bundle.main.preferredLocalizations.first
    let resizeFactor: Double = if appLanguageCode == nil {
      1.0
    } else if let lang = appLanguageCode, let factorForAppLocalization = introResizePerLanguage[lang.prefix(2).lowercased()] {
      factorForAppLocalization > 1.0 ? factorForAppLocalization : 1.0
    } else {
      1.25
    }
    return resizeFactor
  }
  
  #if DEBUG
  func addDebugButton() {
    let buttonAction = Selector(("debugButtonPressed:")) 
    guard responds(to: buttonAction) else { return }
    // use Selector with funny syntax to avoid a compiler warning when the action function is commented out,
    // although it causes a warning when the function is present suggesting change to #selector syntax. oh well
    let button = NSButton(title: "Debug", target: self, action: buttonAction)
    let v = window!.contentView!
    let b = v.bounds
    button.frame = NSRect(x: b.minX+12, y: b.minY+22, width: 100, height: 16)
    v.addSubview(button)
  }
  
  // Originally to exercise the batch name alerts. The above code will add its button in debug builds
  // whenever this function is defined: `@objc func debugButtonPressed(_ sender: AnyObject)`
//  //import KeyboardShortcuts // this debug code requires this import
//  let alerts = Alerts()
//  let excludeNames = Set(["aa", "xx"])
//  var count = 0
//  @objc func debugButtonPressed(_ sender: AnyObject) {
//    if count % 3 == 0 {
//      alerts.withRenameBatchAlert(withCurrentName: "fred", shortcut: nil, excludingNames: excludeNames) { name, shortcut in
//        print("\(name ?? "no name"), \(shortcut != nil ? String(describing: shortcut!) : "no shortcut")")
//        if let shortcut = shortcut { KeyboardShortcuts.setShortcut(nil, for: KeyboardShortcuts.Name("fred")) } // needed to clean up UserDefaults
//      }
//    } else {
//      let isCurrent = (count % 3 == 1) 
//      alerts.withSaveBatchAlert(forCurrentBatch: isCurrent, showingCount: 5, excludingNames: excludeNames) { name, shortcut in
//        print("\(name ?? "no name"), \(shortcut != nil ? String(describing: shortcut!) : "no shortcut")")
//        if let name = name, let shortcut = shortcut { KeyboardShortcuts.setShortcut(nil, for: KeyboardShortcuts.Name(name)) } // needed to clean up UserDefaults
//      }
//    }
//    count += 1
//  }
  #endif

}

// MARK: -

class IntroPageController: NSViewController {
  var app: AppModel!
  
  func willOpen() {}
  func willShow() -> NSButton? { nil }
  func shouldLeave() -> Bool { true }
  func shouldSkip() -> Bool { false }
  func willClose() {}
  
  static func styleLabels(_ labels: [NSTextField]) {
    for case let label? in labels {
      let styled = NSMutableAttributedString(attributedString: label.attributedStringValue)
      styled.applySimpleStyles(basedOnFont: label.font ?? NSFont.labelFont(ofSize: NSFont.labelFontSize))
      label.attributedStringValue = styled
    }
  }
}

// MARK: -

class IntroPagesController: PagedWindowControllerDelegate {
  var app: AppModel
  var pageControllers: [IntroPageController]
  var startPage: Int?
  var skipSetAuthorizationPage = false
  var visited: Set<Int> = []
  
  init(withApp app: AppModel, pageControllers: [IntroPageController]) {
    self.app = app
    self.startPage = nil
    self.pageControllers = pageControllers
    
    for pageController in pageControllers {
      pageController.app = app
    }
  }
  
  var pageViews: [NSView] {
    pageControllers.map(\.view)
  }
  
  // note: for some reason `pageIndex(for: IntroWindowController.Page.demo.pageType)` et al
  // don't work for some reason to do with the `pageType` return type `(some IntroPageController).Type`
  
  func pageIndex<T: IntroPageController>(for _: T.Type) -> Int {
    pageControllers.firstIndex { $0 is T } ?? 0
  }
  
  func pageController<T: IntroPageController>(for _: T.Type) -> T? {
    if let index = pageControllers.firstIndex(where: { $0 is T }), let controller = pageControllers[index] as? T {
      controller
    } else {
      nil
    }
  }
  
  func pageControllerAndIndex<T: IntroPageController>(for _: T.Type) -> (T, Int)? {
    if let index = pageControllers.firstIndex(where: { $0 is T }), let controller = pageControllers[index] as? T {
      (controller, index)
    } else {
      nil
    }
  }
  
  // PagedWindowControllerDelegate protocol:
  
  func willOpen() -> Int {
    pageControllers.forEach { $0.willOpen() }
    return startPage ?? pageIndex(for: WelcomeIntroPageViewController.self)
  }
  
  func willShowPage(_ number: Int) -> NSButton? {
    guard number.isWithin(range: pageControllers.indices) else {
      return nil
    }
    let result = pageControllers[number].willShow()
    visited.insert(number)
    return result
  }
  
  func shouldLeavePage(_ number: Int) -> Bool {
    // when leaving, if this is the check-auth page then use it to determine if we want to skip the next page
    if case let (authPageController, authPageIndex)? = pageControllerAndIndex(for: CheckAuthIntroPageViewController.self), number == authPageIndex {
      skipSetAuthorizationPage = authPageController.isAuthorized
    }
    return if number.isWithin(range: pageControllers.indices) {
      pageControllers[number].shouldLeave()
    } else {
      true
    }
  }
  
  func shouldSkipPage(_ number: Int) -> Bool {
    return if startPage == number {
      false
    } else if number == pageIndex(for: SetAuthIntroPageViewController.self) {
      skipSetAuthorizationPage
    } else if number.isWithin(range: pageControllers.indices) {
      pageControllers[number].shouldSkip()
    } else {
      false
    }
  }
  
  func willClose() {
    pageControllers.forEach { $0.willClose() }
    
    // If leaving without visiting past the first page then launching app code should
    // auto-open again next time based on this flag. It expected to also open directly
    // to the permission page if that wasn't setup on launch, or got reset.
    // I thought about requiring that the user visit every page, but decided against it.
    if !UserDefaults.standard.completedIntro && visited.count > 1 {
      UserDefaults.standard.completedIntro = true
    }
    
    visited.removeAll()
  }
}
