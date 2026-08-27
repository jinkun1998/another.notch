//
//  sizeMatters.swift
//  anotherNotch
//
//  Created by Harsh Vardhan  Goswami  on 05/08/24.
//

import Defaults
import Foundation
import SwiftUI

let downloadSneakSize: CGSize = .init(width: 65, height: 1)
let batterySneakSize: CGSize = .init(width: 160, height: 1)

let shadowPadding: CGFloat = 20
let tabBarMinimumOpenWidth: CGFloat = 416
let moduleTabWidth: CGFloat = 40
let moduleTabLeadingPadding: CGFloat = 6
let moduleTabNotchGap: CGFloat = 10
let notchOuterHorizontalPadding: CGFloat = 19 + 12
let openNotchHeaderHeight: CGFloat = 30
let calendarContentSize: CGSize = .init(width: 504, height: 160)
let calendarOpenNotchSize: CGSize = .init(
    width: calendarContentSize.width + 72,
    height: max(190, calendarContentSize.height + 12)
)
let shelfOpenNotchSize: CGSize = .init(width: 640, height: 190)
let clipboardOpenNotchWidth: CGFloat = calendarOpenNotchSize.width
let musicOpenNotchSize: CGSize = calendarOpenNotchSize
let baseMaximumOpenNotchSize: CGSize = .init(
    width: max(shelfOpenNotchSize.width, musicOpenNotchSize.width, calendarOpenNotchSize.width),
    height: max(shelfOpenNotchSize.height, musicOpenNotchSize.height, calendarOpenNotchSize.height)
)

@MainActor
func maxClipboardOpenNotchHeight(screenUUID: String? = nil) -> CGFloat {
    let screen = screenUUID.flatMap { NSScreen.screen(withUUID: $0) } ?? NSScreen.main
    return max(190, (screen?.frame.height ?? 900) / 2)
}

@MainActor
func clipboardOpenNotchSize(screenUUID: String? = nil) -> CGSize {
    let store = ClipboardHistoryStore.shared
    let maxAllowed = maxClipboardOpenNotchHeight(screenUUID: screenUUID)
    if store.entries.isEmpty {
        return .init(width: clipboardOpenNotchWidth, height: min(220, maxAllowed))
    }
    let entryCount = store.entries.count
    let listHeight = CGFloat(entryCount * 56 + max(0, entryCount - 1) * 8 + 18)
    let dynamicHeight = openNotchHeaderHeight + listHeight
    return .init(width: clipboardOpenNotchWidth, height: max(160, min(dynamicHeight, maxAllowed)))
}
let cornerRadiusInsets: (opened: (top: CGFloat, bottom: CGFloat), closed: (top: CGFloat, bottom: CGFloat)) = (opened: (top: 19, bottom: 24), closed: (top: 6, bottom: 14))

@MainActor
func tabHeaderMinimumOpenWidth(screenUUID: String? = nil) -> CGFloat {
    let tabCount = CGFloat(FeatureModuleRegistry.shared.installedModules.count)
    let tabStripWidth = tabCount * moduleTabWidth
    let requiredInnerWingWidth = moduleTabLeadingPadding + tabStripWidth + moduleTabNotchGap
    let physicalWidth = getClosedNotchSize(screenUUID: screenUUID).width
    let dynamicWidth = physicalWidth + (requiredInnerWingWidth * 2) + (notchOuterHorizontalPadding * 2)
    return max(tabBarMinimumOpenWidth, dynamicWidth)
}

@MainActor
func moduleTabWingWidth() -> CGFloat {
    moduleTabLeadingPadding
        + CGFloat(FeatureModuleRegistry.shared.installedModules.count) * moduleTabWidth
}

@MainActor
func maximumOpenNotchSize(screenUUID: String? = nil) -> CGSize {
    .init(
        width: max(baseMaximumOpenNotchSize.width, tabHeaderMinimumOpenWidth(screenUUID: screenUUID)),
        height: baseMaximumOpenNotchSize.height
    )
}

@MainActor
func notchWindowSize(screenUUID: String? = nil) -> CGSize {
    let maximumSize = maximumOpenNotchSize(screenUUID: screenUUID)
    return .init(width: maximumSize.width, height: maximumSize.height + shadowPadding)
}

@MainActor
func openNotchSize(for view: NotchViews, screenUUID: String? = nil) -> CGSize {
    let minWidth = tabHeaderMinimumOpenWidth(screenUUID: screenUUID)
    let contentWidth: CGFloat
    let contentHeight: CGFloat

    switch view {
    case .home:
        contentWidth = max(musicOpenNotchSize.width, minWidth)
        contentHeight = musicOpenNotchSize.height
    case .clipboard:
        let size = clipboardOpenNotchSize(screenUUID: screenUUID)
        return .init(width: max(size.width, minWidth), height: size.height)
    case .shelf:
        contentWidth = max(shelfOpenNotchSize.width, minWidth)
        contentHeight = shelfOpenNotchSize.height
    case .calendar:
        contentWidth = max(calendarOpenNotchSize.width, minWidth)
        contentHeight = calendarOpenNotchSize.height
    case .camera:
        contentWidth = max(256, minWidth)
        contentHeight = 190
    }

    return .init(
        width: contentWidth,
        height: contentHeight
    )
}

enum MusicPlayerImageSizes {
    static let cornerRadiusInset: (opened: CGFloat, closed: CGFloat) = (opened: 13.0, closed: 4.0)
    static let size = (opened: CGSize(width: 90, height: 90), closed: CGSize(width: 20, height: 20))
}

@MainActor func getScreenFrame(_ screenUUID: String? = nil) -> CGRect? {
    var selectedScreen = NSScreen.main

    if let uuid = screenUUID {
        selectedScreen = NSScreen.screen(withUUID: uuid)
    }
    
    if let screen = selectedScreen {
        return screen.frame
    }
    
    return nil
}

@MainActor func getClosedNotchSize(screenUUID: String? = nil) -> CGSize {
    // Default notch size, to avoid using optionals
    var notchHeight: CGFloat = Defaults[.nonNotchHeight]
    var notchWidth: CGFloat = 185

    var selectedScreen = NSScreen.main

    if let uuid = screenUUID {
        selectedScreen = NSScreen.screen(withUUID: uuid)
    }

    // Check if the screen is available
    if let screen = selectedScreen {
        // Calculate and set the exact width of the notch
        if let topLeftNotchpadding: CGFloat = screen.auxiliaryTopLeftArea?.width,
           let topRightNotchpadding: CGFloat = screen.auxiliaryTopRightArea?.width
        {
            notchWidth = screen.frame.width - topLeftNotchpadding - topRightNotchpadding + 4
        }

        // Check if the Mac has a notch
        if screen.safeAreaInsets.top > 0 {
            // This is a display WITH a notch - use notch height settings
            notchHeight = Defaults[.notchHeight]
            if Defaults[.notchHeightMode] == .matchRealNotchSize {
                notchHeight = screen.safeAreaInsets.top
            } else if Defaults[.notchHeightMode] == .matchMenuBar {
                notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
            }
        } else {
            // This is a display WITHOUT a notch - use non-notch height settings
            notchHeight = Defaults[.nonNotchHeight]
            if Defaults[.nonNotchHeightMode] == .matchMenuBar {
                notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
            }
        }
    }

    return .init(width: notchWidth, height: notchHeight)
}
let musicContentSize: CGSize = .init(width: 504, height: 120)
