enum FeatureModuleAvailability {
    static func isAvailable(
        moduleIsAvailable: Bool,
        isInstalled: Bool,
        isMainFeatureEnabled: Bool
    ) -> Bool {
        moduleIsAvailable && isInstalled && isMainFeatureEnabled
    }

    static func isMainFeatureEnabled(
        for module: FeatureModuleID,
        clipboardHistoryEnabled: Bool,
        shelfEnabled: Bool,
        calendarEnabled: Bool,
        cameraEnabled: Bool
    ) -> Bool {
        switch module {
        case .home:
            true
        case .clipboard:
            clipboardHistoryEnabled
        case .shelf:
            shelfEnabled
        case .calendar:
            calendarEnabled
        case .camera:
            cameraEnabled
        }
    }
}
