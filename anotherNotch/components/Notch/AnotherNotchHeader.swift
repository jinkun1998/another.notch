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
    @ObservedObject var webcamManager = WebcamManager.shared
    @ObservedObject private var clipboardHistory = ClipboardHistoryStore.shared
    @Default(.showMirror) private var showMirror

    var body: some View {
        HStack(spacing: 0) {
            TabSelectionView()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 10)
                .notchHeaderVisibility(vm.notchState != .closed)

            Rectangle()
                .fill(notchDebugColor)
                .frame(width: vm.closedNotchSize.width)
                .frame(maxHeight: .infinity, alignment: .top)
                .mask { NotchShape() }

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
                        if showMirror && webcamManager.cameraAvailable {
                            HoverButton(
                                icon: "web.camera",
                                iconColor: .white,
                                showsHoverHighlight: false,
                                accessibilityLabel: "Show camera"
                            ) {
                                withAnimation(.smooth) {
                                    coordinator.currentView = .camera
                                }
                            }
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
                        if Defaults[.showBatteryIndicator] {
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
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 10)
            .notchHeaderVisibility(vm.notchState != .closed)
        }
        .foregroundColor(.gray)
        .environmentObject(vm)
    }

    private var notchDebugColor: Color {
        #if DEBUG
        .red.opacity(0.9)
        #else
        NSScreen.screen(withUUID: coordinator.selectedScreenUUID)?.safeAreaInsets.top ?? 0 > 0
            ? .black : .clear
        #endif
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
