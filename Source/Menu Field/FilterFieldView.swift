//
//  FilterFieldView.swift
//  Batch Clipboard
//
//  Created by Pierre Houston on 2024-07-10.
//  Portions Copyright © 2024 Bananameter Labs. All rights reserved.
//
//  Based on MenuHeaderView.swift from the Maccy project
//  Portions are copyright © 2024 Alexey Rodionov. All rights reserved.
//

import AppKit
import Carbon
import Sauce

class FilterFieldView: NSView, NSSearchFieldDelegate {
  @IBOutlet weak var queryField: NSSearchField!
  @IBOutlet weak var titleField: NSTextField!
  
  @IBOutlet weak var horizontalLeftPadding: NSLayoutConstraint!
  @IBOutlet weak var horizontalRightPadding: NSLayoutConstraint!
  @IBOutlet weak var titleAndSearchSpacing: NSLayoutConstraint!
  
  private let macOSXLeftPadding: CGFloat = 20.0
  private let macOSXRightPadding: CGFloat = 10.0
  private let searchThrottler = Throttler(minimumDelay: 0.2)
  
  private var characterPickerVisible: Bool { NSApp.characterPickerWindow?.isVisible ?? false }
  
  private lazy var eventMonitor = RunLoopLocalEventMonitor(runLoopMode: .eventTracking) { event in
    if self.processInterceptedEvent(event) {
      return nil
    } else {
      return event
    }
  }
  
  private lazy var customMenu: AppMenu? = self.enclosingMenuItem?.menu as? AppMenu
  private lazy var headerHeight = 28
  private lazy var headerSize = NSSize(width: AppMenu.menuWidth, height: headerHeight)
  
  override func awakeFromNib() {
    if #unavailable(macOS 11) {
      horizontalLeftPadding.constant = macOSXLeftPadding
      horizontalRightPadding.constant = macOSXRightPadding
    }
  }
  
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    
    if window != nil {
      eventMonitor.start()
    } else {
      // Ensure header view was not simply scrolled out of the menu.
      guard NSApp.menuWindow?.isVisible != true else { return }
      
      eventMonitor.stop()
    }
  }
  
  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    
    if #unavailable(macOS 13) {
      if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ||
          NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
        NSColor(named: "MenuColor")?.setFill()
        dirtyRect.fill()
      }
    }
    
    queryField.refusesFirstResponder = false
  }
  
  // Process query when search field was focused (i.e. user clicked on it).
  func controlTextDidChange(_ obj: Notification) {
    fireNotification()
  }
  
  func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
    if commandSelector == #selector(insertTab(_:)) {
      // Switch to main window if Tab is pressed when search is focused.
      window?.makeFirstResponder(window)
      return true
    }
    
    return false
  }
  
  private func fireNotification(throttle: Bool = true) {
    if throttle {
      searchThrottler.throttle {
        self.customMenu?.updateFilter(filter: self.queryField.stringValue)
      }
    } else {
      self.customMenu?.updateFilter(filter: self.queryField.stringValue)
    }
  }
  
  public func setQuery(_ newQuery: String, throttle: Bool = true) {
    guard queryField.stringValue != newQuery else {
      return
    }
    
    queryField.stringValue = newQuery
    fireNotification(throttle: throttle)
  }
  
  public func queryChanged(throttle: Bool = true) {
    fireNotification(throttle: throttle)
  }
  
  private func processInterceptedEvent(_ event: NSEvent) -> Bool {
    if event.type != NSEvent.EventType.keyDown {
      return false
    }
    
    guard let key = Sauce.shared.key(for: Int(event.keyCode)) else {
      return false
    }
    let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
    let chars = event.charactersIgnoringModifiers
    
    return processKeyDownEvent(key: key, modifierFlags: modifierFlags, chars: chars)
  }
  
  private func processKeyDownEvent(key: Key, modifierFlags: NSEvent.ModifierFlags, chars: String?) -> Bool {
    switch FilterFieldKeyCmd(key, modifierFlags) {
    case .clearSearch:
      if queryField.stringValue.isEmpty {
        return false
      }
      setQuery("")
      return true
    case .deleteOneCharFromSearch:
      return processDeletion()
    case .deleteLastWordFromSearch:
      removeLastWordInSearchField()
      return true
    case .moveToNext:
      customMenu?.selectNext()
      return true
    case .moveToPrevious:
      customMenu?.selectPrevious()
      return true
    case .cut:
      guard let e = queryField.currentEditor(), e.selectedRange.length > 0, let r = Range(e.selectedRange, in: e.string) else {
        return true
      }
      let s = String(e.string[r])
      Clipboard.shared.copy(s, excludeFromHistory: true)
      // delete selection
      let selectionNSRange = e.selectedRange
      e.selectedRange = NSRange(location: selectionNSRange.location, length: 0)
      e.replaceCharacters(in: selectionNSRange, with: "")
      return true
    case .copy:
      guard let e = queryField.currentEditor(), e.selectedRange.length > 0, let r = Range(e.selectedRange, in: e.string) else {
        return true
      }
      let s = String(e.string[r])
      Clipboard.shared.copy(s, excludeFromHistory: true)
      return true
    case .paste:
      queryField.currentEditor()?.paste(nil)
      return true
    case .selectCurrentItem:
      customMenu?.select(queryField.stringValue)
      return true
    case .ignored:
      return false
    default:
      break
    }
    
    return processSingleCharacter(chars)
  }
  
  private func processSingleCharacter(_ chars: String?) -> Bool {
    guard !characterPickerVisible else {
      return false
    }
    
    guard let char = chars, char.count == 1 else {
      return false
    }
    
    // Sometimes even though we attempt to activate Maccy,
    // it doesn't get active. This happens particularly with
    // password fields in Safari. Let's at least allow
    // search to work in these cases.
    // See https://github.com/p0deje/Maccy/issues/473.
    if UserDefaults.standard.avoidTakingFocus || !NSApp.isActive {
      // append character to the search field to trigger
      // and stop event from being propagated
      if let editor = queryField.currentEditor() {
        editor.replaceCharacters(in: editor.selectedRange, with: "\(char)")
        queryChanged()
      } else {
        setQuery("\(queryField.stringValue)\(char)")
      }
      return true
    } else {
      // make the search field first responder
      // and propagate event to it
      focusQueryField()
      return false
    }
  }
  
  private func processDeletion() -> Bool {
    guard !characterPickerVisible else {
      return false
    }
    
    if queryField.stringValue.isEmpty {
      return true
    }
    
    if UserDefaults.standard.avoidTakingFocus || !NSApp.isActive {
      if let editor = queryField.currentEditor() {
        let selection = editor.selectedRange
        if selection.length > 0 {
          editor.delete(self)
          queryChanged()
        } else if selection.location > 0 {
          let previousCharRange = (editor.string as NSString).rangeOfComposedCharacterSequence(at: selection.location - 1)
          editor.replaceCharacters(in: previousCharRange, with: "")
          queryChanged()
        }
      } else {
        setQuery(String(queryField.stringValue.dropLast()))
      }
      return true
    } else {
      // make the search field first responder
      // and propagate event to it
      focusQueryField()
      return false
    }
  }
  
  private func focusQueryField() {
    // If the field is already focused, there is no need for force-focus it.
    // Worse, it breaks Korean input handling.
    // See https://github.com/p0deje/Maccy/issues/476 for details.
    guard queryField.currentEditor() == nil else {
      return
    }
    
    queryField.window?.makeFirstResponder(queryField) // why did i switch from becomeFirstResponder to this?
    
    // Making text field a first responder selects all the text by default.
    // We need to make sure events are appended to existing text.
    if let fieldEditor = queryField.currentEditor() {
      fieldEditor.selectedRange = NSRange(location: fieldEditor.selectedRange.length, length: 0)
    }
  }
  
  private func removeLastWordInSearchField() {
    let searchValue = queryField.stringValue
    let newValue = searchValue.split(separator: " ").dropLast().joined(separator: " ")
    
    if newValue.isEmpty {
      setQuery("")
    } else {
      setQuery("\(newValue) ")
    }
  }
  
}
