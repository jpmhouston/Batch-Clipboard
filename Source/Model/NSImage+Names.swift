//
//  NSImage+Names.swift
//  Cleepp
//
//  Created by Pierre Houston on 2024-03-21.
//  Portions Copyright © 2024 Bananameter Labs. All rights reserved.
//
//  Based on GlobalHotKey from Maccy which is
//  Copyright © 2024 Alexey Rodionov. All rights reserved.
//

import Cocoa

extension NSImage.Name {
  static let menuIcon = NSImage.Name("menuNormal")
  static let menuIconEmpty = NSImage.Name("menuFilled")
  static let menuIconEmptyPlus = NSImage.Name("menuFilledPlus")
  static let menuIconNonempty = NSImage.Name("menuList")
  static let menuIconNonemptyPlus = NSImage.Name("menuListPlus")
  static let menuIconNonemptyMinus = NSImage.Name("menuListMinus")
  #if !CLEEPP
  static let maccyStatusBar = NSImage.Name("StatusBarMenuImage")
  #endif
  
  static let externalDrive = loadName("externaldrive")
  static let gear = loadName("gearshape")
  static let doubleGear = loadName("gearshape.2")
  static let gift = loadName("gift")
  static let negationSign = loadName("nosign")
  static let paintPalette = loadName("paintpalette")

  internal static func loadName(_ name: String) -> NSImage.Name {
    if #available(macOS 11, *) {
      return NSImage.Name("\(name).svg")
    } else {
      return NSImage.Name("\(name).png")
    }
  }
}
