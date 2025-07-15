//
//  StorageSettingsViewController.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-07-10.
//  Portions Copyright © 2024 Bananameter Labs. All rights reserved.
//
//  Based on StorageSettingsViewController.swift from the Maccy project
//  Portions are copyright © 2024 Alexey Rodionov. All rights reserved.
//

import AppKit
import Settings

class StorageSettingsViewController: NSViewController, SettingsPane {
  let paneIdentifier = Settings.PaneIdentifier.storage
  let paneTitle = NSLocalizedString("preferences_storage", comment: "")
  let toolbarItemIcon = NSImage(named: .externalDrive)!

  let sizeMin = AppMenu.minNumMenuItems
  let sizeMax = 999

  override var nibName: NSNib.Name? { "StorageSettingsViewController" }

  @IBOutlet weak var storeFilesButton: NSButton!
  @IBOutlet weak var storeImagesButton: NSButton!
  @IBOutlet weak var storeTextButton: NSButton!
  @IBOutlet weak var sizeTextField: NSTextField!
  @IBOutlet weak var sizeStepper: NSStepper!
  @IBOutlet weak var sizeDescription: NSTextField!
  @IBOutlet weak var sizeAltDescription: NSTextField!
  @IBOutlet weak var sizeMootDescription: NSTextField!
  @IBOutlet weak var sizeSeparatorRow: NSGridRow!
  @IBOutlet weak var sizeTextFieldRow: NSGridRow!
  @IBOutlet weak var sizeDescriptionRow: NSGridRow!
  
  private var sizeFormatter: NumberFormatter!
  
  override func viewDidLoad() {
    super.viewDidLoad()
    setMinAndMaxSize()
  }
  
  override func viewWillAppear() {
    super.viewWillAppear()
    populateStoredTypes()
    populateSize()
    showSizeDescription()
    showSizeOptions(AppModel.allowDictinctStorageSize)
  }
  
  // MARK: -
  
  @IBAction func sizeFieldChanged(_ sender: NSTextField) {
    UserDefaults.standard.size = sender.integerValue
    sizeStepper.integerValue = sender.integerValue
  }
  
  @IBAction func sizeStepperChanged(_ sender: NSStepper) {
    UserDefaults.standard.size = sender.integerValue
    sizeTextField.integerValue = sender.integerValue
  }
  
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
  
  // MARK: -
  
  private func setMinAndMaxSize() {
    let effectiveMin = min(max(UserDefaults.standard.maxMenuItems, sizeMin), sizeMax)
    sizeFormatter = NumberFormatter()
    sizeFormatter.minimum = effectiveMin as NSNumber
    sizeFormatter.maximum = sizeMax as NSNumber
    sizeFormatter.maximumFractionDigits = 0
    sizeTextField.formatter = sizeFormatter
    
    sizeStepper.minValue = Double(effectiveMin)
    sizeStepper.maxValue = Double(sizeMax)
  }
  
  private func populateSize() {
    if !UserDefaults.standard.keepHistory {
      sizeTextField.stringValue = ""
      sizeTextField.isEnabled = false
      sizeStepper.isEnabled = false
    } else {
      let effectiveSize = max(UserDefaults.standard.size, UserDefaults.standard.maxMenuItems)
      sizeTextField.integerValue = effectiveSize
      sizeStepper.integerValue = effectiveSize
    }
  }
  
  private func showSizeDescription() {
    let historyEnabled = UserDefaults.standard.keepHistory
    //let fullHistoryAllowed = AppModel.allowFullyExpandedHistory -- have another alt blurb if this is set vs not?
    let useStorageMax = AppModel.allowDictinctStorageSize && UserDefaults.standard.maxMenuItems == 0
    
    sizeDescription.isHidden = !(historyEnabled && !useStorageMax)
    sizeAltDescription.isHidden = !(historyEnabled && useStorageMax)
    sizeMootDescription.isHidden = historyEnabled
  }
  
  private func populateStoredTypes() {
    let types = UserDefaults.standard.enabledPasteboardTypes
    storeFilesButton.state = types.contains(.fileURL) ? .on : .off
    storeImagesButton.state = types.isSuperset(of: [.tiff, .png]) ? .on : .off
    storeTextButton.state = types.contains(.string) ? .on : .off
  }
  
  private func addEnabledTypes(_ types: Set<NSPasteboard.PasteboardType>) {
    UserDefaults.standard.enabledPasteboardTypes = UserDefaults.standard.enabledPasteboardTypes.union(types)
  }
  
  private func removeEnabledTypes(_ types: Set<NSPasteboard.PasteboardType>) {
    UserDefaults.standard.enabledPasteboardTypes = UserDefaults.standard.enabledPasteboardTypes.subtracting(types)
  }
  
  // MARK: -
  
  private func showSizeOptions(_ show: Bool) {
    sizeSeparatorRow.isHidden = !show
    sizeTextFieldRow.isHidden = !show
    sizeDescriptionRow.isHidden = !show
  }
  
}
