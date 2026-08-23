//
//  TabSelectionView.swift
//  anotherNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import Defaults
import SwiftUI

struct TabModel: Identifiable {
    let id: NotchViews
    let label: String
    let icon: String
    let view: NotchViews
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = AnotherNotchViewCoordinator.shared
    @ObservedObject private var webcamManager = WebcamManager.shared
    @StateObject private var shelfState = ShelfStateViewModel.shared
    @Default(.boringShelf) private var boringShelf
    @Default(.showCalendar) private var showCalendar
    @Default(.showMirror) private var showMirror
    @Namespace var animation

    private var tabs: [TabModel] {
        var result = [TabModel(id: .home, label: "Home", icon: "house.fill", view: .home)]

        if boringShelf && (!shelfState.isEmpty || coordinator.alwaysShowTabs) {
            result.append(TabModel(id: .shelf, label: "Shelf", icon: "tray.fill", view: .shelf))
        }
        if showCalendar {
            result.append(TabModel(id: .calendar, label: "Calendar", icon: "calendar", view: .calendar))
        }
        if showMirror && webcamManager.cameraAvailable {
            result.append(TabModel(id: .camera, label: "Camera", icon: "web.camera", view: .camera))
        }

        return result
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                    TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view) {
                        coordinator.currentView = tab.view
                    }
                    .frame(height: 26)
                    .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                    .background {
                        if tab.view == coordinator.currentView {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                        } else {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                                .hidden()
                        }
                    }
            }
        }
        .clipShape(Capsule())
        .animation(.smooth, value: coordinator.currentView)
        .onAppear(perform: ensureSelectionIsAvailable)
        .onChange(of: coordinator.currentView) { oldValue, newValue in
            if oldValue == .camera && newValue != .camera {
                webcamManager.stopSession()
            }
        }
        .onChange(of: showCalendar) { _, _ in ensureSelectionIsAvailable() }
        .onChange(of: showMirror) { _, _ in ensureSelectionIsAvailable() }
        .onChange(of: boringShelf) { _, _ in ensureSelectionIsAvailable() }
        .onChange(of: webcamManager.cameraAvailable) { _, _ in ensureSelectionIsAvailable() }
        .onChange(of: shelfState.isEmpty) { _, _ in ensureSelectionIsAvailable() }
        .onChange(of: coordinator.alwaysShowTabs) { _, _ in ensureSelectionIsAvailable() }
    }

    private func ensureSelectionIsAvailable() {
        guard !tabs.contains(where: { $0.view == coordinator.currentView }) else { return }
        if coordinator.currentView == .camera {
            webcamManager.stopSession()
        }
        coordinator.currentView = .home
    }
}

#Preview {
    AnotherNotchHeader().environmentObject(AnotherNotchViewModel())
}
