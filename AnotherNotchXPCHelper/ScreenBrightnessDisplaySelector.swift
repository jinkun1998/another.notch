import CoreGraphics

enum ScreenBrightnessDisplaySelector {
    static func selectedDisplayID() -> CGDirectDisplayID {
        let mainDisplayID = CGMainDisplayID()
        var displayCount: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &displayCount) == .success, displayCount > 0 else {
            return mainDisplayID
        }

        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        guard CGGetOnlineDisplayList(displayCount, &displayIDs, &displayCount) == .success else {
            return mainDisplayID
        }

        return select(
            from: displayIDs,
            mainDisplayID: mainDisplayID,
            isBuiltIn: { CGDisplayIsBuiltin($0) != 0 }
        )
    }

    static func select(
        from displayIDs: [CGDirectDisplayID],
        mainDisplayID: CGDirectDisplayID,
        isBuiltIn: (CGDirectDisplayID) -> Bool
    ) -> CGDirectDisplayID {
        displayIDs.first(where: isBuiltIn) ?? mainDisplayID
    }
}
