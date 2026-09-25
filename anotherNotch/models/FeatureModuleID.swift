enum FeatureModuleID: String, CaseIterable, Hashable, Identifiable {
    case home
    case clipboard
    case quickNotes
    case shelf
    case calendar
    case camera
    case fanControl

    var id: String { rawValue }
}
