//
//  HistoryChoiceIntroPageViewController.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2026-06-11.
//  Copyright © 2026 Bananameter Labs. All rights reserved.
//

import AppKit

class HistoryChoiceIntroPageViewController: IntroPageController, ClickableTextFieldDelegate {
  @IBOutlet var historyChoiceNeededLabel: NSTextField?
  @IBOutlet var historyOnDescriptionLabel: NSTextField?
  @IBOutlet var historyOffDescriptionLabel: NSTextField?
  @IBOutlet var historyOnButton: NSButton?
  @IBOutlet var historyOffButton: NSButton?
  @IBOutlet var historySwitch: NSSwitch?
  @IBOutlet var historyOnLabel: ClickableTextField?
  @IBOutlet var historyOffLabel: ClickableTextField?
  
  @objc dynamic var keepHistoryChange = UserDefaults.standard.keepHistory
  private var historySavingObserver: NSKeyValueObservation?
  private var highlightChangeObserver: NSKeyValueObservation?
  
  override func viewDidLoad() {
    setupClickableLabels()
  }
  
  deinit {
    removeHistoryChoiceObservers()
  }
  
  // MARK: -
  
  override func willShow() -> NSButton? {
    showHistoryChoiceViews(forUpgradeChosen: UserDefaults.standard.keepHistoryChoicePending ? nil :
                           !UserDefaults.standard.keepHistory)
    setupHistoryChoiceObservers()
    return nil
  }
  
  override func shouldLeave() -> Bool {
    removeHistoryChoiceObservers()
    return true
  }
  
  override func shouldSkip() -> Bool {
    !UserDefaults.standard.keepHistoryChoicePending
  }
  
  // MARK: -
  
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
  
  // MARK: -
  
  private func setupClickableLabels() {
    historyOnLabel?.clickDelegate = self
    historyOffLabel?.clickDelegate = self
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
}
