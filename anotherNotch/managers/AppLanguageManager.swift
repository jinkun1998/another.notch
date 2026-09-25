//
//  AppLanguageManager.swift
//  anotherNotch
//

import Defaults
import Foundation
import SwiftUI

public enum AppLanguage: String, CaseIterable, Identifiable, Defaults.Serializable {
    case system = ""
    case en = "en"
    case vi = "vi"
    case zhHans = "zh-Hans"
    case es = "es"
    case fr = "fr"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: "System Default"
        case .en: "English"
        case .vi: "Tiếng Việt"
        case .zhHans: "简体中文"
        case .es: "Español"
        case .fr: "Français"
        }
    }
}

extension Defaults.Keys {
    public static let appLanguage = Key<AppLanguage>("appLanguage", default: .system)
}

@MainActor
public final class AppLanguageManager: ObservableObject {
    // ponytail: static language catalogue; add dynamic runtime pack download when cloud translations supported.
    public static let shared = AppLanguageManager()

    @Published public private(set) var currentLanguage: AppLanguage

    public var locale: Locale {
        currentLanguage == .system ? .autoupdatingCurrent : Locale(identifier: currentLanguage.rawValue)
    }

    public init(initialLanguage: AppLanguage? = nil) {
        self.currentLanguage = initialLanguage ?? Defaults[.appLanguage]
    }

    public func setLanguage(_ language: AppLanguage) {
        currentLanguage = language
        Defaults[.appLanguage] = language
        if language == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        }
    }
}
