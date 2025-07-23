//
//  AppearanceSettingsViewController.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-07-10.
//  Portions Copyright © 2025 Bananameter Labs. All rights reserved.
//
//  Based on AppearanceSettingsViewController.swift from the Maccy project
//  Portions Copyright © 2024 Alexey Rodionov. All rights reserved.
//

import AppKit
import Settings

class AppearanceSettingsViewController: NSViewController, SettingsPane, NSTextFieldDelegate {
  let paneIdentifier = Settings.PaneIdentifier.appearance
  let paneTitle = NSLocalizedString("preferences_appearance", comment: "")
  let toolbarItemIcon = NSImage(named: .paintPalette)!
  
  override var nibName: NSNib.Name? { "AppearanceSettingsViewController" }
  
  @IBOutlet weak var imageHeightField: NSTextField!
  @IBOutlet weak var imageHeightStepper: NSStepper!
  @IBOutlet weak var titleLengthField: NSTextField!
  @IBOutlet weak var titleLengthStepper: NSStepper!
  @IBOutlet weak var previewDelayField: NSTextField!
  @IBOutlet weak var previewDelayStepper: NSStepper!
  @IBOutlet weak var showSpecialSymbolsButton: NSButton!
  @IBOutlet weak var filterFieldVisibleCheckbox: NSButton!
  @IBOutlet weak var filterModeButton: NSPopUpButton!
  @IBOutlet weak var filterFieldVisibleRow: NSGridRow!
  @IBOutlet weak var filterModeRow: NSGridRow!
  
  private let imageHeightMin = 1
  private let imageHeightMax = 200
  private var imageHeightFormatter: NumberFormatter!
  
  private let titleLengthMin = 30
  private let titleLengthMax = 200
  private var titleLengthFormatter: NumberFormatter!
  
  private let previewDelayMin = 0
  private let previewDelayMax = 100_000
  private var previewDelayFormatter: NumberFormatter!
  
  override func viewDidLoad() {
    super.viewDidLoad()
    setImageHeightRange()
    setTitleLengthRange()
    setPreviewDelayRange()
  }
  
  override func viewWillAppear() {
    super.viewWillAppear()
    populateImageHeight()
    populateTitleLength()
    populatePreviewDelay()
    populateShowSpecialSymbols()
    
    if AppModel.allowHistorySearch {
      showFilterFieldOptions(true)
      populateFilterFieldVisibility()
      populateFilterMode()
      updateFilterModeEnabled()
    } else {
      showFilterFieldOptions(false)
    }
  }
  
  // MARK: -
  
  @IBAction func imageHeightFieldChanged(_ sender: NSTextField) {
    UserDefaults.standard.imageMaxHeight = sender.integerValue
    imageHeightStepper.integerValue = sender.integerValue
  }
  
  @IBAction func imageHeightStepperChanged(_ sender: NSStepper) {
    UserDefaults.standard.imageMaxHeight = sender.integerValue
    imageHeightField.integerValue = sender.integerValue
  }
  
  @IBAction func titleLengthFieldChanged(_ sender: NSTextField) {
    UserDefaults.standard.maxTitleLength = sender.integerValue
    titleLengthStepper.integerValue = sender.integerValue
  }
  
  @IBAction func titleLengthStepperChanged(_ sender: NSStepper) {
    UserDefaults.standard.maxTitleLength = sender.integerValue
    titleLengthField.integerValue = sender.integerValue
  }
  
  @IBAction func previewDelayFieldChanged(_ sender: NSTextField) {
    UserDefaults.standard.previewDelay = Int(sender.doubleValue * 1000) 
    previewDelayStepper.doubleValue = sender.doubleValue
  }
  
  @IBAction func previewDelayStepperChanged(_ sender: NSStepper) {
    UserDefaults.standard.previewDelay = Int(sender.doubleValue * 1000)
    previewDelayField.doubleValue = sender.doubleValue
  }
  
  @IBAction func specialSymbolsVisibilityChanged(_ sender: NSButton) {
    UserDefaults.standard.showSpecialSymbols = (sender.state == .on)
  }
  
  @IBAction func filterFieldVisiblityChanged(_ sender: NSButton) {
    UserDefaults.standard.hideSearch = (sender.state == .off)
    updateFilterModeEnabled()
  }
  
  @IBAction func filterModeChanged(_ sender: NSPopUpButton) {
    switch sender.selectedTag() {
    case 0:
      UserDefaults.standard.searchMode = Searcher.Mode.exact.rawValue
    case 1:
      UserDefaults.standard.searchMode = Searcher.Mode.fuzzy.rawValue
    case 2:
      UserDefaults.standard.searchMode = Searcher.Mode.regexp.rawValue
    case 3:
      UserDefaults.standard.searchMode = Searcher.Mode.mixed.rawValue
    default:
      break
    }
  }
  
  // MARK: -
  
  private func populateImageHeight() {
    imageHeightField.integerValue =  UserDefaults.standard.imageMaxHeight
    imageHeightStepper.integerValue =  UserDefaults.standard.imageMaxHeight
  }
  
  private func setImageHeightRange() {
    imageHeightFormatter = NumberFormatter()
    imageHeightFormatter.minimum = imageHeightMin as NSNumber
    imageHeightFormatter.maximum = imageHeightMax as NSNumber
    imageHeightFormatter.maximumFractionDigits = 0
    imageHeightField.formatter = imageHeightFormatter
    
    imageHeightStepper.minValue = Double(imageHeightMin)
    imageHeightStepper.maxValue = Double(imageHeightMax)
  }
  
  private func setTitleLengthRange() {
    titleLengthFormatter = NumberFormatter()
    titleLengthFormatter.minimum = titleLengthMin as NSNumber
    titleLengthFormatter.maximum = titleLengthMax as NSNumber
    titleLengthFormatter.maximumFractionDigits = 0
    titleLengthField.formatter = titleLengthFormatter
    titleLengthStepper.minValue = Double(titleLengthMin)
    titleLengthStepper.maxValue = Double(titleLengthMax)
  }
  
  private func populateTitleLength() {
    titleLengthField.integerValue = UserDefaults.standard.maxTitleLength
    titleLengthStepper.integerValue = UserDefaults.standard.maxTitleLength
  }
  
  private func setPreviewDelayRange() {
    let minSeconds = Double(previewDelayMin) / 1000.0
    let maxSeconds = Double(previewDelayMax) / 1000.0
    previewDelayFormatter = NumberFormatter()
    previewDelayFormatter.minimum = minSeconds as NSNumber
    previewDelayFormatter.maximum = maxSeconds as NSNumber
    previewDelayFormatter.maximumFractionDigits = 2
    previewDelayField.formatter = previewDelayFormatter
    previewDelayStepper.minValue = minSeconds
    previewDelayStepper.maxValue = maxSeconds
    previewDelayStepper.increment = 0.05
  }
  
  private func populatePreviewDelay() {
    let delaySeconds = Double(UserDefaults.standard.previewDelay) / 1000.0
    previewDelayField.doubleValue = delaySeconds
    previewDelayStepper.doubleValue = delaySeconds
  }
  
  private func populateShowSpecialSymbols() {
    showSpecialSymbolsButton.state = UserDefaults.standard.showSpecialSymbols ? .on : .off
  }
  
  private func populateFilterFieldVisibility() {
    filterFieldVisibleCheckbox.state = UserDefaults.standard.hideSearch ? .off : .on
  }
  
  private func updateFilterModeEnabled() {
    filterModeButton.isEnabled = !UserDefaults.standard.hideSearch
  } 
  
  private func populateFilterMode() {
    switch Searcher.Mode(rawValue: UserDefaults.standard.searchMode) {
    case .exact:
      filterModeButton.selectItem(withTag: 0)
    case .fuzzy:
      filterModeButton.selectItem(withTag: 1)
    case .regexp:
      filterModeButton.selectItem(withTag: 2)
    case .mixed:
      filterModeButton.selectItem(withTag: 3)
    default:
      filterModeButton.selectItem(withTag: 0) // when no setting use .exact 
    }
  }
  
  // MARK: -
  
  private func showFilterFieldOptions(_ show: Bool) {
    filterFieldVisibleRow?.isHidden = !show
    filterModeRow?.isHidden = !show
  }
  
}
