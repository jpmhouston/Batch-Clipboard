//
//  StorageSettingsViewController.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-07-10.
//  Portions Copyright © 2025 Bananameter Labs. All rights reserved.
//
//  Based on StorageSettingsViewController.swift from the Maccy project
//  Portions Copyright © 2024 Alexey Rodionov. All rights reserved.
//

import AppKit
import Settings

class StorageSettingsViewController: NSViewController, SettingsPane {
  let paneIdentifier = Settings.PaneIdentifier.storage
  let paneTitle = NSLocalizedString("preferences_storage", comment: "")
  let toolbarItemIcon = NSImage(named: .externalDrive)!

  override var nibName: NSNib.Name? { "StorageSettingsViewController" }
  
  @objc dynamic var keepHistoryChange = UserDefaults.standard.keepHistory
  
  @IBOutlet weak var storeFilesButton: NSButton!
  @IBOutlet weak var storeImagesButton: NSButton!
  @IBOutlet weak var storeTextButton: NSButton!
  @IBOutlet weak var keepHistorySwitch: NSSwitch!
  @IBOutlet weak var keepHistoryOnDescription: NSTextField!
  @IBOutlet weak var keepHistoryOffDescription: NSTextField!
  @IBOutlet weak var numberOfItemsField: NSTextField!
  @IBOutlet weak var numberOfItemsStepper: NSStepper!
  @IBOutlet weak var numberOfItemsDescription: NSTextField!
  @IBOutlet weak var numberOfItemsExtendedDescription: NSTextField!
  @IBOutlet weak var numberOfItemsEmptyDescription: NSTextField!
  @IBOutlet weak var numberOfItemsDisabledDescription: NSTextField!
  @IBOutlet weak var numberOfItemsFieldRow: NSGridRow!
  @IBOutlet weak var numberOfItemsDescriptionRow: NSGridRow!
  @IBOutlet weak var historySizeField: NSTextField!
  @IBOutlet weak var historySizeStepper: NSStepper!
  @IBOutlet weak var historySizeDescription: NSTextField!
  @IBOutlet weak var historySizeOnlyDescription: NSTextField!
  @IBOutlet weak var historySizeDisabledDescription: NSTextField!
  @IBOutlet weak var historySizeFieldRow: NSGridRow!
  @IBOutlet weak var historySizeDescriptionRow: NSGridRow!
  
  private var historySavingObserver: NSKeyValueObservation?
  
  private let numberOfItemsMin = AppMenu.minNumMenuItems
  private let numberOfItemsMax = 99
  private var numberOfItemsFormatter: NumberFormatter!
  
  private let historySizeMin = AppMenu.minNumMenuItems
  private let historySizeMax = 999
  private var historySizeFormatter: NumberFormatter!
  
  override func viewDidLoad() {
    super.viewDidLoad()
    setNumberOfItemsRange()
    setHistorySizeRange()
  }
  
  override func viewWillAppear() {
    super.viewWillAppear()
    populateStoredTypes()
    
    populateClipboardHistoryToggle()
    updateClipboardHistoryDependencies()
    addObservers()
  }
  
  override func viewWillDisappear() {
    super.viewWillDisappear()
    removeObservers()
  }
  
  private func updateClipboardHistoryDependencies() {
    updateVisibleClipboardHistoryDescription()
    
    if AppModel.allowDictinctStorageSize {
      showHistorySizeOptions(AppModel.allowDictinctStorageSize)
      
      populateHistorySize()
      updateVisibleHistorySizeDescription()
    } else {
      showHistorySizeOptions(false)
    }
    
    populateNumberOfItems()
    updateNumberOfItemsEmptyAllowed()
    updateVisibleNumberOfItemsDescription()
  }
  
  private func addObservers() {
    // need to obsevre this because shortly after setting keepHistory to false,
    // a subsequent confirmation alert can turn it back to true
    historySavingObserver = UserDefaults.standard.observe(\.keepHistory, options: [.old, .new]) { [weak self] _, change in
      guard let self = self else { return }
      //print("keepHistory observer, old = \(change.oldValue == nil ? "nil" : String(describing: change.oldValue!)),, new = \(change.newValue == nil ? "nil" : String(describing: change.newValue!)), old=new: \(change.newValue == change.oldValue)")
      // always set the switch to match `keepHistory`, and the observable flag
      populateClipboardHistoryToggle()
      keepHistoryChange = UserDefaults.standard.keepHistory
      
      // only update the UI if the value has truly changed
      if change.newValue != change.oldValue {
        updateClipboardHistoryDependencies()
        forceRelayout()
      }
    }
  }
  
  private func removeObservers() {
    historySavingObserver?.invalidate()
    historySavingObserver = nil
  }
  
  private func forceRelayout() {
    guard let layer = view.window?.contentView?.layer else {
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.000_001) {
      layer.setNeedsLayout()
    }
  }
  
  // MARK: -
  
  @IBAction func storeFilesChanged(_ sender: NSButton) {
    let types: Set = [NSPasteboard.PasteboardType.fileURL]
    sender.state == .on ? addEnabledTypes(types) : removeEnabledTypes(types)
  }
  
  @IBAction func storeImagesChanged(_ sender: NSButton) {
    let types: Set = [NSPasteboard.PasteboardType.tiff, NSPasteboard.PasteboardType.png]
    sender.state == .on ? addEnabledTypes(types) : removeEnabledTypes(types)
  }
  
  @IBAction func storeTextChanged(_ sender: NSButton) {
    let types: Set = [
      NSPasteboard.PasteboardType.html,
      NSPasteboard.PasteboardType.rtf,
      NSPasteboard.PasteboardType.string
    ]
    sender.state == .on ? addEnabledTypes(types) : removeEnabledTypes(types)
  }
  
  @IBAction func clipboardHistoryToggleChanged(_ sender: NSSwitch) {
    // if testing stand-along would change this directly (although in that case
    // defaults would have an injected abstraction...)
    //UserDefaults.standard.keepHistory = (sender.state == .on)
    
    // assume this will be observed, and keepHistory in defauts will be
    // changed on our behalf (which we must observe to detect that change)
    keepHistoryChange = (sender.state == .on)
  }
  
  @IBAction func numberOfItemsFieldChanged(_ sender: NSTextField) {
    if sender.stringValue.isEmpty {
      UserDefaults.standard.maxMenuItems = 0
    } else {
      UserDefaults.standard.maxMenuItems = sender.integerValue
      numberOfItemsStepper.integerValue = sender.integerValue
    }
    updateVisibleNumberOfItemsDescription()
    updateVisibleHistorySizeDescription()
  }
  
  @IBAction func numberOfItemsStepperChanged(_ sender: NSStepper) {
    UserDefaults.standard.maxMenuItems = sender.integerValue
    numberOfItemsField.integerValue = sender.integerValue
    updateVisibleNumberOfItemsDescription()
    updateVisibleHistorySizeDescription()
  }
  
  @IBAction func historySizeFieldChanged(_ sender: NSTextField) {
    UserDefaults.standard.historySize = sender.integerValue
    historySizeStepper.integerValue = sender.integerValue
  }
  
  @IBAction func historySizeStepperChanged(_ sender: NSStepper) {
    UserDefaults.standard.historySize = sender.integerValue
    historySizeField.integerValue = sender.integerValue
  }
  
  // MARK: -
  
  private func addEnabledTypes(_ types: Set<NSPasteboard.PasteboardType>) {
    UserDefaults.standard.enabledPasteboardTypes = UserDefaults.standard.enabledPasteboardTypes.union(types)
  }
  
  private func removeEnabledTypes(_ types: Set<NSPasteboard.PasteboardType>) {
    UserDefaults.standard.enabledPasteboardTypes = UserDefaults.standard.enabledPasteboardTypes.subtracting(types)
  }
  
  private func populateStoredTypes() {
    let types = UserDefaults.standard.enabledPasteboardTypes
    storeFilesButton.state = types.contains(.fileURL) ? .on : .off
    storeImagesButton.state = types.isSuperset(of: [.tiff, .png]) ? .on : .off
    storeTextButton.state = types.contains(.string) ? .on : .off
  }
  
  private func populateClipboardHistoryToggle() {
    keepHistorySwitch.state = UserDefaults.standard.keepHistory ? .on : .off
  }
  
  private func updateVisibleClipboardHistoryDescription() {
    keepHistoryOnDescription.isHidden = !UserDefaults.standard.keepHistory
    keepHistoryOffDescription.isHidden = UserDefaults.standard.keepHistory
  }
  
  private func setNumberOfItemsRange() {
    numberOfItemsFormatter = EmptyPermittingNumberFormatter()
    numberOfItemsFormatter.minimum = numberOfItemsMin as NSNumber
    numberOfItemsFormatter.maximum = numberOfItemsMax as NSNumber
    numberOfItemsFormatter.maximumFractionDigits = 0
    numberOfItemsField.formatter = numberOfItemsFormatter
    
    numberOfItemsStepper.minValue = Double(numberOfItemsMin)
    numberOfItemsStepper.maxValue = Double(numberOfItemsMax)
  }
  
  func updateNumberOfItemsEmptyAllowed() {
    guard let formatter = numberOfItemsField.formatter as? EmptyPermittingNumberFormatter else {
      return
    }  
    formatter.emptyPermitted = AppModel.allowDictinctStorageSize
  }
  
  private func populateNumberOfItems() {
    var value = UserDefaults.standard.maxMenuItems
    // only when allowing separate storage setting do we expect value can be 0
    if AppModel.allowDictinctStorageSize && value == 0 {
      numberOfItemsField.stringValue = ""
      numberOfItemsStepper.integerValue = numberOfItemsMin
    } else {
      value = min(max(value, numberOfItemsMin), numberOfItemsMax)
      numberOfItemsField.integerValue = value
      numberOfItemsStepper.integerValue = value
    }
    numberOfItemsField.isEnabled = UserDefaults.standard.keepHistory
    numberOfItemsStepper.isEnabled = UserDefaults.standard.keepHistory
  }
  
  private func updateVisibleNumberOfItemsDescription() {
    if UserDefaults.standard.keepHistory {
      let fullHistoryAllowed = AppModel.allowFullyExpandedHistory
      let useStorageSize = AppModel.allowDictinctStorageSize && UserDefaults.standard.maxMenuItems == 0
      
      numberOfItemsDescription.isHidden = useStorageSize || fullHistoryAllowed
      numberOfItemsExtendedDescription.isHidden = useStorageSize || !fullHistoryAllowed
      numberOfItemsEmptyDescription.isHidden = !useStorageSize
      numberOfItemsDisabledDescription.isHidden = true
    } else {
      numberOfItemsDescription.isHidden = true
      numberOfItemsExtendedDescription.isHidden = true
      numberOfItemsEmptyDescription.isHidden = true
      numberOfItemsDisabledDescription.isHidden = false
    }
  }
  
  private func setHistorySizeRange() {
    let effectiveMin = min(max(UserDefaults.standard.maxMenuItems, historySizeMin), historySizeMax)
    historySizeFormatter = NumberFormatter()
    historySizeFormatter.minimum = effectiveMin as NSNumber
    historySizeFormatter.maximum = historySizeMax as NSNumber
    historySizeFormatter.maximumFractionDigits = 0
    historySizeField.formatter = historySizeFormatter
    
    historySizeStepper.minValue = Double(effectiveMin)
    historySizeStepper.maxValue = Double(historySizeMax)
  }
  
  private func populateHistorySize() {
    let effectiveSize = max(UserDefaults.standard.historySize, UserDefaults.standard.maxMenuItems)
    historySizeField.integerValue = effectiveSize
    historySizeStepper.integerValue = effectiveSize
    
    historySizeField.isEnabled = UserDefaults.standard.keepHistory
    historySizeStepper.isEnabled = UserDefaults.standard.keepHistory
  }
  
  private func updateVisibleHistorySizeDescription() {
    if UserDefaults.standard.keepHistory {
      let useStorageMax = AppModel.allowDictinctStorageSize && UserDefaults.standard.maxMenuItems == 0
      
      historySizeDescription.isHidden = !useStorageMax
      historySizeOnlyDescription.isHidden = useStorageMax
      historySizeDisabledDescription.isHidden = true
    } else {
      historySizeDescription.isHidden = true
      historySizeOnlyDescription.isHidden = true
      historySizeDisabledDescription.isHidden = false
    }
  }
  
  // MARK: -
  
  private func showHistorySizeOptions(_ show: Bool) {
    historySizeFieldRow.isHidden = !show
    historySizeDescriptionRow.isHidden = !show
  }
  
}
