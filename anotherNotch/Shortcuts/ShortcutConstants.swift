//
//  Constants.swift
//  anotherNotch
//
//  Created by Richard Kunkli on 16/08/2024.
//

import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let clipboardHistoryPanel = Self("clipboardHistoryPanel", default: .init(.c, modifiers: [.shift, .command]))
    static let toggleMicrophone = Self("toggleMicrophone", default: .init(.f5, modifiers: [.function]))
    static let decreaseBacklight = Self("decreaseBacklight", default: .init(.f1, modifiers: [.command]))
    static let increaseBacklight = Self("increaseBacklight", default: .init(.f2, modifiers: [.command]))
    static let toggleSneakPeek = Self("toggleSneakPeek", default: .init(.h, modifiers: [.command, .shift]))
    static let toggleNotchOpen = Self("toggleNotchOpen", default: .init(.i, modifiers: [.command, .shift]))
    static let openHome = Self("openHome", default: .init(.one, modifiers: [.control, .option]))
    static let openClipboard = Self("openClipboard", default: .init(.two, modifiers: [.control, .option]))
    static let openShelf = Self("openShelf", default: .init(.three, modifiers: [.control, .option]))
    static let openCalendar = Self("openCalendar", default: .init(.four, modifiers: [.control, .option]))
    static let openCamera = Self("openCamera", default: .init(.five, modifiers: [.control, .option]))
    static let openFanControl = Self("openFanControl", default: nil)
}
