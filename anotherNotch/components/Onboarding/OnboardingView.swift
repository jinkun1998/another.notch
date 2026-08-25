//
//  OnboardingView.swift
//  anotherNotch
//
//  Created by Alexander on 2025-06-23.
//

import SwiftUI
import AVFoundation
import CoreBluetooth
import Defaults

enum OnboardingStep {
    case welcome
    case accessibilityPermission
    case cameraPermission
    case calendarPermission
    case remindersPermission
    case bluetoothPermission
    case musicPermission
    case finished
}

private let calendarService = CalendarService()

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
                                step = .cameraPermission
                            }
                        }
                    },
                    onSkip: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .cameraPermission
                        }
                    }
                )
                .transition(.opacity)

            case .cameraPermission:
                PermissionRequestView(
                    icon: Image(systemName: "camera.fill"),
                    title: "Enable Camera Access",
                    description: "anotherNotch includes a mirror feature that lets you quickly check your appearance using your camera, right from the notch. Camera access is required only to show this live preview. You can turn the mirror feature on or off at any time in the app.",
                    privacyNote: "Your camera is never used without your consent, and nothing is recorded or stored.",
                    onAllow: {
                        Task {
                            await requestCameraPermission()
                            withAnimation(.easeInOut(duration: 0.6)) {
                                step = .calendarPermission
                            }
                        }
                    },
                    onSkip: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .calendarPermission
                        }
                    }
                )
                .transition(.opacity)

            case .calendarPermission:
                PermissionRequestView(
                    icon: Image(systemName: "calendar"),
                    title: "Enable Calendar Access",
                    description: "anotherNotch can show all your upcoming events in one place. Access to your calendar is needed to display your schedule.",
                    privacyNote: "Your calendar data is only used to show your events and is never shared.",
                    onAllow: {
                            Task {
                                if await requestCalendarPermission() {
                                    Defaults[.showCalendar] = true
                                }
                                withAnimation(.easeInOut(duration: 0.6)) {
                                    step = .remindersPermission
                                }
                        }
                    },
                    onSkip: {
                            withAnimation(.easeInOut(duration: 0.6)) {
                                step = .remindersPermission
                            }
                    }
                )
                .transition(.opacity)

                case .remindersPermission:
                    PermissionRequestView(
                        icon: Image(systemName: "checklist"),
                        title: "Enable Reminders Access",
                        description: "anotherNotch can show your scheduled reminders alongside your calendar events. Access to Reminders is needed to display your reminders.",
                        privacyNote: "Your reminders data is only used to show your reminders and is never shared.",
                        onAllow: {
                            Task {
                                await requestRemindersPermission()
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

    func requestCameraPermission() async {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    func requestCalendarPermission() async -> Bool {
        (try? await calendarService.requestAccess(to: .event)) ?? false
    }

    func requestRemindersPermission() async {
        _ = try? await calendarService.requestAccess(to: .reminder)
    }
    
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
