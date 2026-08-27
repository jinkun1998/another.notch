//
//  OnboardingView.swift
//  anotherNotch
//
//  Created by Alexander on 2025-06-23.
//

import SwiftUI
import CoreBluetooth
import Defaults

enum OnboardingStep {
    case welcome
    case accessibilityPermission
    case bluetoothPermission
    case musicPermission
    case finished
}

struct OnboardingBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Default(.notchTransparency) private var notchTransparency

    private let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)

    var body: some View {
        ZStack {
            shape.fill(.black.opacity(0.35))
            LiquidGlassSurface(shape: shape, opacity: notchTransparency)
            LiquidGlassEdge(shape: shape, opacity: notchTransparency)
        }
        .ignoresSafeArea()
    }
}

struct OnboardingView: View {
    @State var step: OnboardingStep = .welcome
    let onFinish: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        ZStack {
            switch step {
            case .welcome:
                WelcomeView {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        step = .accessibilityPermission
                    }
                }
                .transition(.opacity)

            case .accessibilityPermission:
                PermissionRequestView(
                    icon: Image(systemName: "hand.raised.fill"),
                    title: "Enable Accessibility Access",
                    description: "Accessibility access allows anotherNotch to replace macOS volume and brightness HUDs with dynamic notch overlays.",
                    privacyNote: "Used solely for hardware key HUD indicators. No keystrokes or private data are recorded.",
                    onAllow: {
                        Task {
                            if await requestAccessibilityPermission() {
                                Defaults[.hudReplacement] = true
                            }
                            withAnimation(.easeInOut(duration: 0.6)) {
                                step = .bluetoothPermission
                            }
                        }
                    },
                    onSkip: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .bluetoothPermission
                        }
                    }
                )
                .transition(.opacity)

            case .bluetoothPermission:
                PermissionRequestView(
                    icon: Image(systemName: "headphones"),
                    title: "Enable Bluetooth Accessories",
                    description: "anotherNotch can show when your Bluetooth audio accessories connect, including their battery level when available.",
                    privacyNote: "Bluetooth access is used only for connected accessory notifications.",
                    onAllow: {
                        Task {
                            if await requestBluetoothPermission() {
                                Defaults[.showBluetoothDeviceConnectionIndicator] = true
                            }
                            withAnimation(.easeInOut(duration: 0.6)) {
                                step = .musicPermission
                            }
                        }
                    },
                    onSkip: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .musicPermission
                        }
                    }
                )
                .transition(.opacity)
                
            case .musicPermission:
                MusicControllerSelectionView(
                    onContinue: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            AnotherNotchViewCoordinator.shared.firstLaunch = false
                            step = .finished
                        }
                    }
                )
                .transition(.opacity)

            case .finished:
                OnboardingFinishView(onFinish: onFinish, onOpenSettings: onOpenSettings)
            }
        }
        .frame(width: 400, height: 600)
    }

    // MARK: - Permission Request Logic

    func requestAccessibilityPermission() async -> Bool {
        await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: true)
    }

    func requestBluetoothPermission() async -> Bool {
        await bluetoothPermissionRequester.requestAccess()
    }
}

private let bluetoothPermissionRequester = BluetoothPermissionRequester()

private final class BluetoothPermissionRequester: NSObject, CBCentralManagerDelegate {
    private var centralManager: CBCentralManager?
    private var continuation: CheckedContinuation<Bool, Never>?

    func requestAccess() async -> Bool {
        switch CBManager.authorization {
        case .allowedAlways:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
                centralManager = CBCentralManager(delegate: self, queue: .main)
            }
        @unknown default:
            return false
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch CBManager.authorization {
        case .allowedAlways:
            finish(with: true)
        case .denied, .restricted:
            finish(with: false)
        case .notDetermined:
            break
        @unknown default:
            finish(with: false)
        }
    }

    private func finish(with granted: Bool) {
        continuation?.resume(returning: granted)
        continuation = nil
        centralManager = nil
    }
}
