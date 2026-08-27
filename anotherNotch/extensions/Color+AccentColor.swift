//
//  Color+AccentColor.swift
//  anotherNotch
//
//  Created by Alexander on 2025-10-24.
//

import SwiftUI
import Defaults

enum AccentColorResolver {
    static var customAccent: NSColor? {
        guard Defaults[.useCustomAccentColor],
              let colorData = Defaults[.customAccentColorData]
        else { return nil }

        return decode(colorData)
    }

    static func decode(_ colorData: Data) -> NSColor? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData)
    }
}

extension Color {
    static var effectiveAccent: Color {
        AccentColorResolver.customAccent.map(Color.init(nsColor:)) ?? .accentColor
    }
    
    /// Returns a darker version of the accent color suitable for backgrounds
    static var effectiveAccentBackground: Color {
        if let nsColor = AccentColorResolver.customAccent {
            return Color(nsColor: nsColor.withSystemEffect(.disabled))
        }
        return Color.effectiveAccent.opacity(0.25)
    }
}

extension NSColor {
    static var effectiveAccent: NSColor {
        AccentColorResolver.customAccent ?? .controlAccentColor
    }
    
    /// Returns a darker version of the accent color as NSColor suitable for backgrounds
    static var effectiveAccentBackground: NSColor {
        if let nsColor = AccentColorResolver.customAccent {
            return nsColor.withSystemEffect(.disabled)
        }
        return NSColor.controlAccentColor.withAlphaComponent(0.25)
    }
}
