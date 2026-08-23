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
    @StateObject var tvm = ShelfStateViewModel.shared
    @Default(.boringShelf) private var boringShelf
    @Default(.showCalendar) private var showCalendar
    @Default(.showMirror) private var showMirror
    var body: some View {
        HStack(spacing: 0) {
            HStack {
                if ((!tvm.isEmpty || coordinator.alwaysShowTabs) && boringShelf)
                    || showCalendar
                    || (showMirror && webcamManager.cameraAvailable)
                {
                    TabSelectionView()
                } else if vm.notchState == .open {
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .zIndex(2)

            if vm.notchState == .open {
                Rectangle()
                    .fill(NSScreen.screen(withUUID: coordinator.selectedScreenUUID)?.safeAreaInsets.top ?? 0 > 0 ? .black : .clear)
                    .frame(width: vm.closedNotchSize.width)
                    .mask {
                        NotchShape()
                    }
            }

            HStack(spacing: 4) {
                if vm.notchState == .open {
                    if isHUDType(coordinator.sneakPeek.type) && coordinator.sneakPeek.show && Defaults[.showOpenNotchHUD] {
                        OpenNotchHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    } else {
                        if showMirror && webcamManager.cameraAvailable {
                            Button(action: {
                                withAnimation(.smooth) {
                                    coordinator.currentView = .camera
                                }
                            }) {
                                Image(systemName: "web.camera")
                                    .foregroundColor(.white)
                                    .padding()
                                    .imageScale(.medium)
                                    .frame(width: 30, height: 30)
                                    .liquidGlassControl(in: Capsule())
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        if Defaults[.settingsIconInNotch] {
                            Button(action: {
                                DispatchQueue.main.async {
                                    SettingsWindowController.shared.showWindow()
                                }
                                
                            }) {
                                Image(systemName: "gear")
                                    .foregroundColor(.white)
                                    .padding()
                                    .imageScale(.medium)
                                    .frame(width: 30, height: 30)
                                    .liquidGlassControl(in: Capsule())
                            }
                            .buttonStyle(PlainButtonStyle())
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
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .zIndex(2)
        }
        .foregroundColor(.gray)
        .environmentObject(vm)
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

#Preview {
    AnotherNotchHeader().environmentObject(AnotherNotchViewModel())
}
