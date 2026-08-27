//
//  TabSelectionView.swift
//  anotherNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import SwiftUI

struct TabSelectionView: View {
    let tabWidth: CGFloat
    @ObservedObject private var coordinator = AnotherNotchViewCoordinator.shared
    @ObservedObject private var modules = FeatureModuleRegistry.shared

    init(tabWidth: CGFloat = moduleTabWidth) {
        self.tabWidth = tabWidth
    }

    var body: some View {
        let installedModules = modules.installedModules
        let selectedIndex = installedModules.firstIndex {
            $0.tabDestination == coordinator.currentView
        } ?? 0

        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color(nsColor: .secondarySystemFill))
                .frame(width: tabWidth, height: 26)
                .offset(x: CGFloat(selectedIndex) * tabWidth)

            HStack(spacing: 0) {
                ForEach(installedModules) { module in
                    TabButton(
                        label: module.title,
                        icon: module.icon,
                        selected: coordinator.currentView == module.tabDestination
                    ) {
                        coordinator.currentView = module.tabDestination
                    }
                    .frame(width: tabWidth, height: 26)
                    .foregroundStyle(module.tabDestination == coordinator.currentView ? .white : .gray)
                }
            }
        }
        .frame(width: CGFloat(installedModules.count) * tabWidth, height: 26, alignment: .leading)
        .clipShape(Capsule())
        .animation(.smooth, value: coordinator.currentView)
        .onAppear(perform: ensureSelectionIsAvailable)
        .onChange(of: modules.installedIDs) { _, _ in ensureSelectionIsAvailable() }
    }

    private func ensureSelectionIsAvailable() {
        guard !modules.isAvailable(coordinator.currentView) else {
            return
        }
        coordinator.currentView = .home
    }
}

#Preview {
    AnotherNotchHeader().environmentObject(AnotherNotchViewModel())
}
