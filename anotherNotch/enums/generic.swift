//
//  generic.swift
//  anotherNotch
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Combine
import Defaults
import Foundation
import SwiftUI

public enum Style {
    case notch
    case floating
}

public enum ContentType: Int, Codable, Hashable, Equatable {
    case normal
    case menu
    case settings
}

public enum NotchState {
    case closed
    case open
}

typealias NotchViews = FeatureModuleID

struct FeatureModule: Identifiable {
    let id: FeatureModuleID
    let title: String
    let icon: String
    let tabDestination: FeatureModuleID
    let settingsDestination: FeatureModuleID
    let installedByDefault: Bool
    let isAvailable: Bool
    let supportsScrolling: Bool
}

@MainActor
final class FeatureModuleRegistry: ObservableObject {
    static let shared = FeatureModuleRegistry()

    static let modules = [
        FeatureModule(
            id: .home,
            title: "Home",
            icon: "house.fill",
            tabDestination: .home,
            settingsDestination: .home,
            installedByDefault: true,
            isAvailable: true,
            supportsScrolling: false
        ),
        FeatureModule(
            id: .clipboard,
            title: "Clipboard",
            icon: "clipboard.fill",
            tabDestination: .clipboard,
            settingsDestination: .clipboard,
            installedByDefault: false,
            isAvailable: true,
            supportsScrolling: true
        ),
        FeatureModule(
            id: .shelf,
            title: "Shelf",
            icon: "tray.fill",
            tabDestination: .shelf,
            settingsDestination: .shelf,
            installedByDefault: false,
            isAvailable: true,
            supportsScrolling: true
        ),
        FeatureModule(
            id: .calendar,
            title: "Calendar",
            icon: "calendar",
            tabDestination: .calendar,
            settingsDestination: .calendar,
            installedByDefault: false,
            isAvailable: true,
            supportsScrolling: true
        ),
        FeatureModule(
            id: .camera,
            title: "Camera",
            icon: "web.camera",
            tabDestination: .camera,
            settingsDestination: .camera,
            installedByDefault: false,
            isAvailable: true,
            supportsScrolling: false
        )
    ]

    @Published private(set) var installedIDs: Set<FeatureModuleID>
    @Published private(set) var tabOrder: [FeatureModuleID]

    private init() {
        if !Defaults[.featureModuleStateMigrated] {
            Defaults[.installedFeatureModuleIDs] = Self.hasExistingProfile
                ? FeatureModuleID.allCases.filter { !$0.isHome }.map(\.rawValue)
                : []
            Defaults[.featureModuleStateMigrated] = true
        }

        installedIDs = Set(
            Defaults[.installedFeatureModuleIDs].compactMap(FeatureModuleID.init(rawValue:))
        )
        tabOrder = Self.normalizedTabOrder(Defaults[.featureModuleTabOrder])
        persistTabOrder()
    }

    var installedModules: [FeatureModule] {
        tabOrder.compactMap { id in
            guard isInstalled(id), isAvailable(id) else { return nil }
            return Self.modules.first { $0.id == id }
        }
    }

    var orderedModules: [FeatureModule] {
        tabOrder.compactMap { id in Self.modules.first { $0.id == id } }
    }

    func isInstalled(_ id: FeatureModuleID) -> Bool {
        id.isHome || installedIDs.contains(id)
    }

    func isAvailable(_ id: FeatureModuleID) -> Bool {
        FeatureModuleAvailability.isAvailable(
            moduleIsAvailable: Self.modules.first(where: { $0.id == id })?.isAvailable == true,
            isInstalled: isInstalled(id),
            isMainFeatureEnabled: FeatureModuleAvailability.isMainFeatureEnabled(
                for: id,
                clipboardHistoryEnabled: Defaults[.clipboardHistoryEnabled],
                shelfEnabled: Defaults[.boringShelf],
                calendarEnabled: Defaults[.showCalendar],
                cameraEnabled: Defaults[.showMirror]
            )
        )
    }

    func supportsScrolling(_ id: FeatureModuleID) -> Bool {
        Self.modules.first(where: { $0.id == id })?.supportsScrolling == true && isAvailable(id)
    }

    func install(_ id: FeatureModuleID) {
        guard !id.isHome else { return }
        installedIDs.insert(id)
        persist()

        if id == .clipboard {
            ClipboardHistoryStore.shared.startMonitoring()
        }
    }

    func remove(_ id: FeatureModuleID) {
        guard !id.isHome else { return }
        installedIDs.remove(id)
        deactivate(id)
        persist()

        if AnotherNotchViewCoordinator.shared.currentView == id {
            AnotherNotchViewCoordinator.shared.currentView = .home
        }
    }

    func moveTab(_ id: FeatureModuleID, before destination: FeatureModuleID) {
        guard id != .home,
            destination != .home,
            id != destination,
            let sourceIndex = tabOrder.firstIndex(of: id),
            let destinationIndex = tabOrder.firstIndex(of: destination)
        else { return }

        var reordered = tabOrder
        reordered.remove(at: sourceIndex)
        reordered.insert(id, at: destinationIndex)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            tabOrder = reordered
        }
        persistTabOrder()
    }

    func startInstalledServices() {
        if isInstalled(.clipboard) {
            ClipboardHistoryStore.shared.startMonitoring()
        }
    }

    func activate(_ id: FeatureModuleID) {
        guard isAvailable(id) else { return }

        switch id {
        case .home, .shelf:
            break
        case .clipboard:
            ClipboardHistoryStore.shared.startMonitoring()
        case .calendar:
            Task { await CalendarManager.shared.checkCalendarAuthorization() }
        case .camera:
            WebcamManager.shared.checkAndRequestVideoAuthorization()
        }
    }

    func deactivate(_ id: FeatureModuleID) {
        switch id {
        case .clipboard:
            ClipboardHistoryStore.shared.stopMonitoring()
        case .camera:
            WebcamManager.shared.stopSession()
        case .home, .shelf, .calendar:
            break
        }
    }

    private static var hasExistingProfile: Bool {
        let defaults = UserDefaults.standard
        let legacyKeys = [
            "onboardingCompleted",
            "firstLaunch",
            "clipboardHistoryEnabled",
            "showCalendar",
            "showMirror",
            "boringShelf"
        ]
        return legacyKeys.contains { defaults.object(forKey: $0) != nil }
    }

    private func persist() {
        Defaults[.installedFeatureModuleIDs] = installedIDs.map(\.rawValue).sorted()
    }

    private static func normalizedTabOrder(_ storedIDs: [String]) -> [FeatureModuleID] {
        let stored = storedIDs.compactMap(FeatureModuleID.init(rawValue:))
        let uniqueStored = stored.reduce(into: [FeatureModuleID]()) { result, id in
            if !result.contains(id) {
                result.append(id)
            }
        }
        let orderedNonHome = uniqueStored.filter { !$0.isHome }
        return [.home] + orderedNonHome + FeatureModuleID.allCases.filter {
            !$0.isHome && !orderedNonHome.contains($0)
        }
    }

    private func persistTabOrder() {
        Defaults[.featureModuleTabOrder] = tabOrder.map(\.rawValue)
    }
}

private extension FeatureModuleID {
    var isHome: Bool { self == .home }
}

enum SettingsEnum {
    case general
    case about
    case charge
    case download
    case mediaPlayback
    case hud
    case shelf
    case extensions
}

enum DownloadIndicatorStyle: String, Defaults.Serializable {
    case progress = "Progress"
    case percentage = "Percentage"
}

enum DownloadIconStyle: String, Defaults.Serializable {
    case onlyAppIcon = "Only app icon"
    case onlyIcon = "Only download icon"
    case iconAndAppIcon = "Icon and app icon"
}

enum MirrorShapeEnum: String, Defaults.Serializable {
    case rectangle = "Rectangular"
    case circle = "Circular"
}

enum WindowHeightMode: String, Defaults.Serializable {
    case matchMenuBar = "Match menubar height"
    case matchRealNotchSize = "Match real notch height"
    case custom = "Custom height"
}

enum SliderColorEnum: String, CaseIterable, Defaults.Serializable {
    case white = "White"
    case albumArt = "Match album art"
    case accent = "Accent color"
}
