//
//  AnotherNotchHeader.swift
//  anotherNotch
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Defaults
import SwiftUI

struct AnotherNotchHeader: View {
    @EnvironmentObject var vm: AnotherNotchViewModel
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = AnotherNotchViewCoordinator.shared
    @ObservedObject private var clipboardHistory = ClipboardHistoryStore.shared
    @ObservedObject private var modules = FeatureModuleRegistry.shared

    var body: some View {
        let tabCount = CGFloat(modules.installedModules.count)
        let tabContentWidth = tabCount * moduleTabWidth

        ZStack {
            Rectangle()
                .fill(notchBackgroundColor)
                .frame(width: vm.closedNotchSize.width)
                .frame(maxHeight: .infinity, alignment: .top)
                .mask { NotchShape() }

            HStack(spacing: 0) {
                TabSelectionView(tabWidth: moduleTabWidth)
                    .frame(width: tabContentWidth, alignment: .leading)
                    .padding(.leading, moduleTabLeadingPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .notchHeaderVisibility(vm.notchState != .closed)

                Color.clear
                    .frame(width: vm.closedNotchSize.width)

                HStack(spacing: 4) {
                if vm.notchState == .open {
                    if isHUDType(coordinator.sneakPeek.type) && coordinator.sneakPeek.show && Defaults[.showOpenNotchHUD] {
                        OpenNotchHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    } else {
                        if coordinator.currentView == .clipboard {
                            Button(role: .destructive) {
                                clipboardHistory.clear()
                            } label: {
                                Label("Clear", systemImage: "trash")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .buttonStyle(.plain)
                            .disabled(clipboardHistory.entries.isEmpty)
                        }
                        if Defaults[.settingsIconInNotch] {
                            HoverButton(
                                icon: "gear",
                                iconColor: .white,
                                showsHoverHighlight: false,
                                accessibilityLabel: "Open settings",
                                action: SettingsWindowController.present
                            )
                        }
                        if Defaults[.batteryFeatureEnabled] && Defaults[.showBatteryIndicator] {
                            AnotherNotchBatteryView(
                                batteryWidth: 30,
                                isCharging: batteryModel.isCharging,
                                isInLowPowerMode: batteryModel.isInLowPowerMode,
                                isPluggedIn: batteryModel.isPluggedIn,
                                levelBattery: batteryModel.levelBattery,
                                maxCapacity: batteryModel.maxCapacity,
                                timeToFullCharge: batteryModel.timeToFullCharge,
                                isForNotification: false
                            )
                        }
                    }
                    }
                }
                .font(.system(.headline, design: .rounded))
                .padding(.trailing, 10)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .notchHeaderVisibility(vm.notchState != .closed)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: openNotchHeaderHeight)
        .foregroundColor(.gray)
        .environmentObject(vm)
    }

    private var notchBackgroundColor: Color {
        NSScreen.screen(withUUID: coordinator.selectedScreenUUID)?.safeAreaInsets.top ?? 0 > 0
            ? .black : .clear
    }

    func isHUDType(_ type: SneakContentType) -> Bool {
        switch type {
        case .volume, .brightness, .backlight, .mic:
            return true
        default:
            return false
        }
    }
}

private extension View {
    func notchHeaderVisibility(_ isVisible: Bool) -> some View {
        opacity(isVisible ? 1 : 0)
            .blur(radius: isVisible ? 0 : 20)
            .zIndex(2)
    }
}

#Preview {
    AnotherNotchHeader().environmentObject(AnotherNotchViewModel())
}
