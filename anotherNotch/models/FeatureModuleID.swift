enum FeatureModuleID: String, CaseIterable, Hashable, Identifiable {
    case home
    case clipboard
    case quickNotes
    case shelf
    case calendar
    case camera
    case fanControl

    var id: String { rawValue }

    static func tabs(
        in tabOrder: [FeatureModuleID],
        installedIDs: Set<FeatureModuleID>,
        rightSideIDs: Set<FeatureModuleID>,
        twoSidedLayoutEnabled: Bool,
        side: FeatureModuleTabSide
    ) -> [FeatureModuleID] {
        tabOrder.filter { id in
            guard id == .home || installedIDs.contains(id) else { return false }
            let isRightSide = twoSidedLayoutEnabled && id != .home && rightSideIDs.contains(id)
            return side == (isRightSide ? .right : .left)
        }
    }
}

enum FeatureModuleTabSide: String, CaseIterable, Identifiable {
    case left
    case right

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}
