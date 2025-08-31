//
//  Intro.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-03-01.
//  Copyright © 2025 Bananameter Labs. All rights reserved.
//

// swiftlint:disable file_length
import AppKit
import SDWebImage
import os.log

import KeyboardShortcuts // delete this once debug code is deleted

extension NSWindow.FrameAutosaveName {
  static let introWindow: NSWindow.FrameAutosaveName = "lol.bananameter.batchclip.intro.FrameAutosaveName"
}

class IntroWindowController: PagedWindowController {
  @IBOutlet var viewController: IntroViewController!
  
  convenience init() {
    self.init(windowNibName: "Intro")
  }
  
  func openIntro(atPage page: IntroViewController.Pages? = nil, with object: AppModel) {
    // if already loaded then also check if already onscreen, if so being to the front and that's all
    // (continuing anyway works, except for the restoreWindowPosition() call, until the window is
    // closed there's no cached window position and its reset to the center of the screen below)
    if isWindowLoaded, let window = window, window.isVisible {
      window.orderFrontRegardless()
      return
    }
    
    // accessing window triggers loading from nib, do this before showWindow so we can setup before showing
    guard let window = window, let viewController = viewController else {
      return
    }
    
    viewController.model = object
    viewController.startPage = page
    
    // these might be redundant, ok to do either way
    pageDelegate = viewController
    useView(viewController.view)
    
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
  
  private func restoreWindowPosition() {
    guard let window else {
      return
    }
    
    window.center()
    window.setFrameUsingName(.introWindow)
    window.setFrameAutosaveName(.introWindow)
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

class IntroViewController: NSViewController, PagedWindowControllerDelegate, ClickableTextFieldDelegate {
  @IBOutlet var staticLogoImage: NSImageView?
  @IBOutlet var animatedLogoImage: SDAnimatedImageView?
  @IBOutlet var logoStopButton: NSButton?
  @IBOutlet var logoRestartButton: NSButton?
  @IBOutlet var setupNeededLabel: NSTextField?
  @IBOutlet var openSecurityPanelButton: NSButton?
  @IBOutlet var openSecurityPanelSpinner: NSProgressIndicator?
  @IBOutlet var hasAuthorizationEmoji: NSTextField?
  @IBOutlet var needsAuthorizationEmoji: NSTextField?
  @IBOutlet var hasAuthorizationLabel: NSTextField?
  @IBOutlet var needsAuthorizationLabel: NSTextField?
  @IBOutlet var nextAuthorizationDirectionsLabel: NSTextField?
  @IBOutlet var authorizationVerifiedEmoji: NSTextField?
  @IBOutlet var authorizationDeniedEmoji: NSTextField?
  @IBOutlet var historyChoiceNeededLabel: NSTextField?
  @IBOutlet var historyOnDescriptionLabel: NSTextField?
  @IBOutlet var historyOffDescriptionLabel: NSTextField?
  @IBOutlet var historyOnButton: NSButton?
  @IBOutlet var historyOffButton: NSButton?
  @IBOutlet var historySwitch: NSSwitch?
  @IBOutlet var historyOnLabel: ClickableTextField?
  @IBOutlet var historyOffLabel: ClickableTextField?
  @IBOutlet var demoImage: NSImageView?
  @IBOutlet var demoCopyBubble: NSView?
  @IBOutlet var demoPasteBubble: NSView?
  @IBOutlet var specialCopyPasteBehaviorLabel: NSTextField?
  @IBOutlet var filledIconLabel: NSTextField?
  @IBOutlet var manuallyEnterQueueModeLabel: NSTextField?
  @IBOutlet var manuallyStartReplayingLabel: NSTextField?
  @IBOutlet var inAppPurchageTitle: NSTextField?
  @IBOutlet var inAppPurchageLabel: NSView?
  @IBOutlet var appStorePromoTitle: NSTextField?
  @IBOutlet var appStorePromoLabel: NSView?
  @IBOutlet var openDocsLinkButton: NSButton?
  @IBOutlet var copyDocsLinkButton: NSButton?
  @IBOutlet var sendSupportEmailButton: NSButton?
  @IBOutlet var copySupportEmailButton: NSButton?
  @IBOutlet var openDonationLinkButton: NSButton?
  @IBOutlet var copyDonationLinkButton: NSButton?
  @IBOutlet var openPrivacyPolicyLinkButton: NSButton?
  @IBOutlet var openAppStoreEULALinkButton: NSButton?
  //@IBOutlet var sendL10nEmailButton: NSButton?
  //@IBOutlet var copyL10nEmailButton: NSButton?
  @IBOutlet var aboutGitHubLabel: NSTextField?
  @IBOutlet var appStoreAboutGitHubLabel: NSTextField?
  @IBOutlet var openGitHubLinkButton: NSButton?
  @IBOutlet var copyGitHubLinkButton: NSButton?
  @IBOutlet var openMaccyLinkButton: NSButton?
  @IBOutlet var copyMaccyLinkButton: NSButton?
  
  private var labelsToStyle: [NSTextField] { [
    specialCopyPasteBehaviorLabel, filledIconLabel, manuallyEnterQueueModeLabel, manuallyStartReplayingLabel
  ].compactMap({$0}) }
  
  private var preAuthorizationPageFirsTime = true
  private var skipSetAuthorizationPage = false
  private var skipHistoryChoicePage = false
  private var optionKeyEventMonitor: Any?
  private var logoTimer: DispatchSourceTimer?
  private var demoTimer: DispatchSourceTimer?
  private var demoCanceled = false
  var model: AppModel!
  var startPage: Pages?
  
  enum Pages: Int {
    case welcome = 0, checkAuth, setAuth, historyChoice, demo, aboutMenu, aboutMore, links
  }
  private var visited: Set<Pages> = []
  
  @objc dynamic var keepHistoryChange = UserDefaults.standard.keepHistory
  private var historySavingObserver: NSKeyValueObservation?
  private var highlightChangeObserver: NSKeyValueObservation?
  
  override func viewDidLoad() {
    styleLabels()
    setupLogo()
    setupClickableLabels()
  }
  
  deinit {
    removeOptionKeyObserver()
    removeHistoryChoiceObservers()
    cancelDemo()
  }
  
  // MARK: -
  
  func willOpen() -> Int {
    // Unlike `skipSetAuthorizationPage` flag that's set as we go, decide whether or not
    // to show this page up front and keep that until window closed and opened again. 
    skipHistoryChoicePage = !(UserDefaults.standard.keepHistoryChoicePending || startPage == .historyChoice)
    
    return startPage?.rawValue ?? Pages.welcome.rawValue
  }
  
  func willClose() {
    // If leaving without visiting past the first page then launching app code should
    // auto-open again next time based on this flag. It expected to also open directly
    // to the permission page if that wasn't setup on launch, or got reset.
    // I thought about requiring that the user visit every page, but decided against it.
    if !UserDefaults.standard.completedIntro && visited.count > 1 {
      UserDefaults.standard.completedIntro = true
    }
    
    visited.removeAll()
  }
  
  func willShowPage(_ number: Int) -> NSButton? {
    guard let page = Pages(rawValue: number) else {
      return nil
    }
    
    var customDefaultButtonResult: NSButton? = nil
    
    switch page {
    case .welcome:
      #if INTRO_ANIMATED_LOGO
      if !visited.contains(page) {
        startAnimatedLogo(withDelay: true)
      } else {
        resetAnimatedLogo()
      }
      #endif
      if model.hasAccessibilityPermissionBeenGranted() {
        setupNeededLabel?.isHidden = true
      }
    
    case .checkAuth:
      let isAuthorized = model.hasAccessibilityPermissionBeenGranted()
      hasAuthorizationEmoji?.isHidden = !isAuthorized
      needsAuthorizationEmoji?.isHidden = isAuthorized
      hasAuthorizationLabel?.isHidden = !isAuthorized
      needsAuthorizationLabel?.isHidden = isAuthorized
      nextAuthorizationDirectionsLabel?.isHidden = isAuthorized
      openSecurityPanelButton?.isEnabled = !isAuthorized
      customDefaultButtonResult = !isAuthorized ? openSecurityPanelButton : nil
      skipSetAuthorizationPage = isAuthorized
    
    case .setAuth:
      authorizationVerifiedEmoji?.isHidden = true
      authorizationDeniedEmoji?.isHidden = true
    
    case .historyChoice:
      showHistoryChoiceViews(forUpgradeChosen: UserDefaults.standard.keepHistoryChoicePending ? nil :
                             !UserDefaults.standard.keepHistory)
      setupHistoryChoiceObservers()
    
    case .demo:
      runDemo()
    
    case .links:
      #if APP_STORE
      inAppPurchageTitle?.isHidden = false
      inAppPurchageLabel?.isHidden = false
      appStorePromoTitle?.isHidden = true
      appStorePromoLabel?.isHidden = true
      openDonationLinkButton?.isHidden = true
      copyDonationLinkButton?.isHidden = true
      openPrivacyPolicyLinkButton?.isHidden = false
      openAppStoreEULALinkButton?.isHidden = false
      aboutGitHubLabel?.isHidden = true
      appStoreAboutGitHubLabel?.isHidden = false
      #else
      inAppPurchageTitle?.isHidden = true
      inAppPurchageLabel?.isHidden = true
      appStorePromoTitle?.isHidden = false
      appStorePromoLabel?.isHidden = false
      openPrivacyPolicyLinkButton?.isHidden = true
      openAppStoreEULALinkButton?.isHidden = true
      aboutGitHubLabel?.isHidden = false
      appStoreAboutGitHubLabel?.isHidden = true
      #endif
      showAltCopyEmailButtons(false)
      setupOptionKeyObserver() { [weak self] event in
        self?.showAltCopyEmailButtons(event.modifierFlags.contains(.option))
      }
    
    default:
      break
    }
    
    visited.insert(page)
    return customDefaultButtonResult
  }
  
  func shouldLeavePage(_ number: Int) -> Bool {
    guard let page = Pages(rawValue: number) else {
      return true
    }
    
    switch page {
    case .welcome:
      #if INTRO_ANIMATED_LOGO
      stopAnimatedLogo()
      #endif
    case .checkAuth:
      openSecurityPanelSpinner?.stopAnimation(self)
    case .historyChoice:
      removeHistoryChoiceObservers()
    case .demo:
      cancelDemo()
    case .links:
      removeOptionKeyObserver()
    default:
      break
    }
    
    return true
  }
  
  func shouldSkipPage(_ number: Int) -> Bool {
    switch Pages(rawValue: number) {
    case .setAuth: skipSetAuthorizationPage
    case .historyChoice: skipHistoryChoicePage
    default: false
    }
  }
  
  // MARK: -
  
  private func styleLabels() {
    for label in labelsToStyle {
      let styled = NSMutableAttributedString(attributedString: label.attributedStringValue)
      styled.applySimpleStyles(basedOnFont: label.font ?? NSFont.labelFont(ofSize: NSFont.labelFontSize))
      label.attributedStringValue = styled
    }
  }
  
  private func setupLogo() {
    #if INTRO_ANIMATED_LOGO // note, app currently has no animated logo
    animatedLogoImage?.autoPlayAnimatedImage = false
    animatedLogoImage?.isHidden = true
    logoStopButton?.isHidden = true
    
    // replace NSImage loaded from the nib with a SDAnimatedImage
    guard let name = animatedLogoImage?.image?.name(), let sdImage = SDAnimatedImage(named: name + ".gif") else {
      logoRestartButton?.isHidden = true
      return
    }
    animatedLogoImage?.image = sdImage
    logoRestartButton?.isHidden = false
    #else
    animatedLogoImage?.isHidden = true
    logoStopButton?.isHidden = true
    logoRestartButton?.isHidden = true
    #endif
  }
  
  #if INTRO_ANIMATED_LOGO
  private func resetAnimatedLogo() {
    stopAnimatedLogo() // show static logo initially
  }
  
  private func stopAnimatedLogo() {
    cancelLogoTimer()
    animatedLogoImage?.player?.stopPlaying()
    animatedLogoImage?.isHidden = true
    logoStopButton?.isHidden = true
    logoRestartButton?.isHidden = false
  }
  
  private func startAnimatedLogo(withDelay useDelay: Bool = false) {
    let initialDelay = 2.0
    
    // reset player to the start and setup to stop after a loop completes
    guard let gifPlayer = animatedLogoImage?.player else {
      return
    }
    gifPlayer.seekToFrame(at: 0, loopCount: 0)
    gifPlayer.animationLoopHandler = { [weak self] loop in
      self?.stopAnimatedLogo()
    }
    
    // start with gif hidden, for a few seconds if useDelay is true
    animatedLogoImage?.isHidden = true
    logoStopButton?.isHidden = false
    logoRestartButton?.isHidden = true
    
    if !useDelay {
      animatedLogoImage?.isHidden = false
      gifPlayer.startPlaying()
    } else {
      runOnLogoDelayTimer(withDelay: initialDelay) { [weak self] in
        self?.animatedLogoImage?.isHidden = false
        self?.animatedLogoImage?.player?.startPlaying()
      }
    }
  }
  #endif // INTRO_ANIMATED_LOGO
  
  private func setupOptionKeyObserver(_ observe: @escaping (NSEvent) -> Void) {
    if let previousMonitor = optionKeyEventMonitor {
      NSEvent.removeMonitor(previousMonitor)
    }
    optionKeyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
      observe(event)
      return event
    }
  }
  
  private func setupClickableLabels() {
    historyOnLabel?.clickDelegate = self
    historyOffLabel?.clickDelegate = self
  }
  
  private func removeOptionKeyObserver() {
    if let eventMonitor = optionKeyEventMonitor {
      NSEvent.removeMonitor(eventMonitor)
      optionKeyEventMonitor = nil
    }
  }
  
  private func showAltCopyEmailButtons(_ showCopy: Bool) {
    openDocsLinkButton?.isHidden = showCopy
    copyDocsLinkButton?.isHidden = !showCopy
    sendSupportEmailButton?.isHidden = showCopy
    copySupportEmailButton?.isHidden = !showCopy
    //sendL10nEmailButton?.isHidden = showCopy  // for now i've removed the translation buttons
    //copyL10nEmailButton?.isHidden = !showCopy  // until i form some l10n plans
    #if !APP_STORE
    openDonationLinkButton?.isHidden = showCopy
    copyDonationLinkButton?.isHidden = !showCopy
    #endif
    openGitHubLinkButton?.isHidden = showCopy
    copyGitHubLinkButton?.isHidden = !showCopy
    openMaccyLinkButton?.isHidden = showCopy
    copyMaccyLinkButton?.isHidden = !showCopy
  }
  
  private func showHistoryChoiceViews(forUpgradeChosen upgrade: Bool?) {
    if let upgrade = upgrade {
      historyChoiceNeededLabel?.isHidden = true
      historyOnDescriptionLabel?.isHidden = upgrade
      historyOffDescriptionLabel?.isHidden = !upgrade
      historyOnButton?.state = upgrade ? .off : .on
      historyOffButton?.state = upgrade ? .on : .off
      //historySwitch?.state = upgrade ? .on : .off
      //styleLabel(historyOnLabel, toShowSelected: !upgrade)
      //styleLabel(historyOffLabel, toShowSelected: upgrade)
    } else {
      historyChoiceNeededLabel?.isHidden = false
      historyOnDescriptionLabel?.isHidden = true
      historyOffDescriptionLabel?.isHidden = true
      historyOnButton?.state = .off
      historyOffButton?.state = .off
      //historySwitch?.state = .off
      //styleLabel(historyOnLabel, toShowSelected: false)
      //styleLabel(historyOffLabel, toShowSelected: false)
    }
  }
  
  //private func styleLabel(_ label: NSTextField?, toShowSelected selected: Bool) {
  //  guard let label = label else { return }
  //  let activeStyle: [NSAttributedString.Key: Any] = [.underlineStyle: NSUnderlineStyle.single.rawValue]
  //  var selectedStyle: [NSAttributedString.Key: Any] = [:]
  //  if let font = label.font, let bold = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(.bold), size: font.pointSize) {
  //    selectedStyle = [.font: bold]
  //  }
  //  label.attributedStringValue = NSAttributedString(string: label.stringValue, attributes: selected ? selectedStyle : activeStyle)
  //}
  
  private func changeKeepHistory(to newValue: Bool) {
    if newValue != UserDefaults.standard.keepHistory {
      // assume this var is observed, and `keepHistory` in defaults will be changed on
      // our behalf to match if its confirmed (which we must observe to detect that change)
      keepHistoryChange = newValue 
    } else {
      UserDefaults.standard.keepHistoryChoicePending = false
      showHistoryChoiceViews(forUpgradeChosen: !newValue)
    }
  }
  
  private func setupHistoryChoiceObservers() {
    // Need to obsevre `keepHistory` in defaults because we set it only indirectly,
    // by first setting our var `keepHistoryChange` which the app model itself observes
    // and potentially opens a confirmation alert before finally setting `keepHistory`.
    historySavingObserver = UserDefaults.standard.observe(\.keepHistory, options: .new) { [weak self] _, change in
      guard let self = self, let newValue = change.newValue else { return }
      keepHistoryChange = newValue
      
      UserDefaults.standard.keepHistoryChoicePending = false
      DispatchQueue.main.async {
        self.showHistoryChoiceViews(forUpgradeChosen: !newValue)
      }
    }
    highlightChangeObserver = NSApplication.shared.observe(\.effectiveAppearance, options: []) { [weak self] _, _ in
      nop()
      DispatchQueue.main.async {
        self?.showHistoryChoiceViews(forUpgradeChosen: UserDefaults.standard.keepHistoryChoicePending ? nil :
                                     !UserDefaults.standard.keepHistory)
      }
    }
  }
  
  private func removeHistoryChoiceObservers() {
    historySavingObserver?.invalidate()
    historySavingObserver = nil
    highlightChangeObserver?.invalidate()
    highlightChangeObserver = nil
  }
  
  // swiftlint:disable nesting
  // swiftlint:disable colon
  private func runDemo() {
    let startInterval: Double = 2.5
    let normalFrameInterval: Double = 2.0
    let cursorMoveFrameInterval: Double = 1.0
    let swapFrameInterval: Double = 2.5
    let copyBalloonTime: Double = 0.75
    let prePasteBalloonTime: Double = 0.25
    let postPasteBalloonTime: Double = 0.5
    let endHoldInterval: Double = 5.0
    let repeatTransitionInterval: Double = 1.0
    
    enum Frame {
      case img(_ name: String?, keepBubble: Bool = false, _ interval: Double)
      case copybubble(show: Bool = true, _ interval: Double)
      case pastebubble(show: Bool = true, _ interval: Double)
    }
    let frames: [Frame] = [
      .img("introDemo1", startInterval),
      .img("introDemo2", copyBalloonTime), .copybubble(normalFrameInterval - copyBalloonTime),
      .img("introDemo3", copyBalloonTime), .copybubble(normalFrameInterval - copyBalloonTime),
      .img("introDemo4", copyBalloonTime), .copybubble(normalFrameInterval - copyBalloonTime),
      .img("introDemo5", swapFrameInterval), .pastebubble(prePasteBalloonTime),
      .img("introDemo6", keepBubble:true, postPasteBalloonTime), .pastebubble(show:false, normalFrameInterval - postPasteBalloonTime),
      .img("introDemo7", cursorMoveFrameInterval - prePasteBalloonTime), .pastebubble(prePasteBalloonTime),
      .img("introDemo8", keepBubble:true, postPasteBalloonTime), .pastebubble(show:false, normalFrameInterval - postPasteBalloonTime),
      .img("introDemo9", cursorMoveFrameInterval - prePasteBalloonTime), .pastebubble(prePasteBalloonTime),
      .img("introDemo10", keepBubble:true, postPasteBalloonTime), .pastebubble(show:false, endHoldInterval - postPasteBalloonTime),
      .img(nil, repeatTransitionInterval)
    ]
    
    // sanity check frames array not empty here so no need to check anywhere below
    guard frames.count > 0 else {
      return
    }
    
    func showFrame(_ index: Int) {
      let interval: Double
      switch frames[index] {
      case .img(let name, let keepBubble, let t):
        if !keepBubble {
          demoCopyBubble?.isHidden = true
          demoPasteBubble?.isHidden = true
        }
        if let name = name {
          demoImage?.image = NSImage(named: name)
        } else {
          demoImage?.image = nil
        }
        interval = t
        
      case .copybubble(let show, let t):
        demoCopyBubble?.isHidden = !show
        interval = t
        
      case .pastebubble(let show, let t):
        demoPasteBubble?.isHidden = !show
        interval = t
      }
      
      guard !self.demoCanceled else {
        return
      }
      runOnDemoTimer(afterDelay: interval) { [weak self] in
        guard let self = self, !self.demoCanceled else {
          return
        }
        if index + 1 < frames.count {
          showFrame(index + 1)
        } else {
          showFrame(0)
        }
      }
    }
    
    // kick off perpetual sequence
    demoCopyBubble?.isHidden = true
    demoPasteBubble?.isHidden = true
    demoCanceled = false
    showFrame(0)
  }
  // swiftlint:enable nesting
  // swiftlint:enable colon
  
  private func cancelDemo() {
    // If this func is called from the main thread, the runDemo sequence must be now blocked by the timer.
    // If this cancel is too late and callback within runDemo runs anyhow, it will stop safely because
    // either a) self not nil but demoCanceled flag will cause abort, or b) self=nil and closure aborts.
    // When called from deinit it must be that all strong references to self are gone so it's again
    // in the timer or the async dispatch in the timerFor.. method below, so will have case b). A-ok.
    demoCanceled = true
    cancelDemoTimer()
  }
  
  // MARK: -
  
  @IBAction func stopLogoAnimation(_ sender: AnyObject) {
    #if INTRO_ANIMATED_LOGO
    stopAnimatedLogo()
    #endif
  }
  
  @IBAction func restartLogoAnimation(_ sender: AnyObject) {
    #if INTRO_ANIMATED_LOGO
    startAnimatedLogo()
    #endif
  }
  
  @IBAction func openGeneralSettings(_ sender: AnyObject) {
    model.showSettings(selectingPane: .general)
  }
  
  @IBAction func openInAppPurchaceSettings(_ sender: AnyObject) {
    model.showSettings(selectingPane: .purchase)
  }
  
  @IBAction func checkAccessibilityAuthorization(_ sender: AnyObject) {
    let isAuthorized = model.hasAccessibilityPermissionBeenGranted()
    authorizationVerifiedEmoji?.isHidden = !isAuthorized
    authorizationDeniedEmoji?.isHidden = isAuthorized
  }
  
  @IBAction func openSettingsAppSecurityPanel(_ sender: AnyObject) {
    let openSecurityPanelSpinnerTime = 1.25
    
    model.openSecurityPanel()
    
    // make window controller skip ahead to the next page after a delay
    guard let windowController = (self.view.window?.windowController as? IntroWindowController) else {
      return
    }
    
    openSecurityPanelSpinner?.startAnimation(sender)
    DispatchQueue.main.asyncAfter(deadline: .now() + openSecurityPanelSpinnerTime) { [weak self, weak windowController] in
      guard let self = self, let wc = windowController, wc.isOpen else {
        return
      }
      self.openSecurityPanelSpinner?.stopAnimation(sender)
      
      if wc.isOpen && Pages(rawValue: wc.currentPageNumber) == .checkAuth {
        wc.advance(self)
      }
    }
  }
  
  @IBAction func historyOn(_ sender: AnyObject) {
    if historyOnButton?.state == .on {
      historyOffButton?.state = .off
      changeKeepHistory(to: true)
      
    } else if historyOffButton?.state != .on {
      UserDefaults.standard.keepHistoryChoicePending = true
      showHistoryChoiceViews(forUpgradeChosen: nil)
    }
  }
  
  @IBAction func historyOff(_ sender: AnyObject) {
    if historyOffButton?.state == .on {
      historyOnButton?.state = .off
      changeKeepHistory(to: false)
      
    } else if historyOnButton?.state != .on {
      UserDefaults.standard.keepHistoryChoicePending = true
      showHistoryChoiceViews(forUpgradeChosen: nil)
    }
  }
  
  // historySwitch hidden for now and instead using just buttons
  @IBAction func historySwitched(_ sender: AnyObject) {
    guard let switchControl = sender as? NSSwitch else { return }
    changeKeepHistory(to: switchControl.state == .off)
  }

  // clickable historyOnLabel & historyOffLabel are hidden for now and instead using just buttons
  func clickDidOccur(on field: ClickableTextField) {
    if field == historyOnLabel {
      changeKeepHistory(to: true)
    } else if field == historyOffLabel {
      changeKeepHistory(to: false)
    }
  }
  
  @IBAction func openAppInMacAppStore(_ sender: AnyObject) {
    openURL(string: AppModel.macAppStoreURL)
  }
  
  @IBAction func openDocumentationWebpage(_ sender: AnyObject) {
    openURL(string: AppModel.homepageURL)
  }
  
  @IBAction func copyDocumentationWebpage(_ sender: AnyObject) {
    Clipboard.shared.copy(AppModel.homepageURL, excludeFromHistory: false)
  }
  
  @IBAction func openGitHubWebpage(_ sender: AnyObject) {
    openURL(string: AppModel.githubURL)
  }
  
  @IBAction func copyGitHubWebpage(_ sender: AnyObject) {
    Clipboard.shared.copy(AppModel.githubURL, excludeFromHistory: false)
  }
  
  @IBAction func openDonationWebpage(_ sender: AnyObject) {
    openURL(string: AppModel.donationURL)
  }
  
  @IBAction func copyDonationWebpage(_ sender: AnyObject) {
    Clipboard.shared.copy(AppModel.donationURL, excludeFromHistory: false)
  }
  
  @IBAction func openPrivacyPolicyWebpage(_ sender: AnyObject) {
    openURL(string: AppModel.privacyPolicyURL)
  }
  
  @IBAction func openAppStoreEULAWebpage(_ sender: AnyObject) {
    openURL(string: AppModel.appStoreUserAgreementURL)
  }
  
  @IBAction func openMaccyWebpage(_ sender: AnyObject) {
    openURL(string: AppModel.maccyURL)
  }
  
  @IBAction func copyMaccyWebpage(_ sender: AnyObject) {
    Clipboard.shared.copy(AppModel.maccyURL, excludeFromHistory: false)
  }
  
  @IBAction func sendSupportEmail(_ sender: AnyObject) {
    openURL(string: AppModel.supportEmailURL)
  }
  
  @IBAction func copySupportEmail(_ sender: AnyObject) {
    Clipboard.shared.copy(AppModel.supportEmailAddress, excludeFromHistory: false)
  }
  
  @IBAction func sendLocalizeVolunteerEmail(_ sender: AnyObject) {
    openURL(string: AppModel.localizeVolunteerEmailURL)
  }
  
  @IBAction func copyLocalizeVolunteerEmail(_ sender: AnyObject) {
    Clipboard.shared.copy(AppModel.localizeVolunteerEmailAddress, excludeFromHistory: false)
  }
  
  // MARK: -
  
  private func runOnLogoDelayTimer(withDelay delay: Double, _ action: @escaping () -> Void) {
    logoTimer?.cancel()
    logoTimer = DispatchSource.scheduledTimerForRunningOnMainQueue(afterDelay: delay) { [weak self] in
      self?.logoTimer = nil
      action()
    }
  }
  
  func cancelLogoTimer() {
    logoTimer?.cancel()
    logoTimer = nil
  }
  
  private func runOnDemoTimer(afterDelay delay: Double, _ action: @escaping () -> Void) {
    demoTimer?.cancel()
    demoTimer = DispatchSource.scheduledTimerForRunningOnMainQueue(afterDelay: delay) { [weak self] in
      self?.demoTimer = nil // doing this before calling closure supports closure itself calling runOnDemoTimer
      action()
    }
  }
  
  private func cancelDemoTimer() {
    demoTimer?.cancel()
    demoTimer = nil
  }
  
  private func openURL(string: String) {
    guard let url = URL(string: string) else {
      os_log(.default, "failed to create URL %@", string)
      return
    }
    if !NSWorkspace.shared.open(url) {
      os_log(.default, "failed to open URL %@", string)
    }
  }
  
}
// swiftlint:enable file_length
