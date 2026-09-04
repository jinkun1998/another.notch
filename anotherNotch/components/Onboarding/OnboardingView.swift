//
//  OnboardingView.swift
//  anotherNotch
//
//  Created by Alexander on 2025-06-23.
//

import SwiftUI
import AppKit
import CoreBluetooth
import Defaults

enum OnboardingStep {
    case welcome
    case accessibilityPermission
    case bluetoothPermission
    case musicPermission
    case moduleSelection
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

private struct OnboardingModuleSelectionView: View {
    @Binding var selectedModules: Set<FeatureModuleID>
    let onContinue: () -> Void

    private let modules = FeatureModuleRegistry.modules.filter { $0.id != .home }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()

            Text("Choose Your Tabs")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Select the modules you want in your notch. You can add or remove them later in Settings.")
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(modules) { module in
                    OnboardingModuleSelectionRow(
                        module: module,
                        isSelected: selectedModules.contains(module.id)
                    ) {
                        toggle(module.id)
                    }
                }
            }

            Spacer()

            Button("Continue", action: onContinue)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .frame(maxWidth: .infinity)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OnboardingBackground())
    }

    private func toggle(_ module: FeatureModuleID) {
        if selectedModules.contains(module) {
            selectedModules.remove(module)
        } else {
            selectedModules.insert(module)
        }
    }
}

private struct OnboardingModuleSelectionRow: View {
    let module: FeatureModule
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: module.icon)
                    .font(.title3)
                    .frame(width: 24)
                    .foregroundStyle(Color.effectiveAccent)

                Text(module.title)
                    .fontWeight(.medium)

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.effectiveAccent : Color.secondary)
            }
            .padding(14)
            .background(
                .white.opacity(isSelected ? 0.12 : 0.06),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(module.title) module")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

struct OnboardingView: View {
    @State var step: OnboardingStep = .welcome
    @State private var accessibilityGranted: Bool = AXIsProcessTrusted()
    @State private var accessibilityRequested: Bool = false
    @State private var bluetoothGranted: Bool = (CBManager.authorization == .allowedAlways)
    @State private var bluetoothRequested: Bool = false
    @State private var selectedModules = Set<FeatureModuleID>()
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
                    isGranted: accessibilityGranted,
                    hasRequested: accessibilityRequested,
                    onAllow: {
                        accessibilityRequested = true
                        XPCHelperClient.shared.requestAccessibilityAuthorization()
                        if !AXIsProcessTrusted() {
                            openPrivacySettings("Privacy_Accessibility")
                        }
                        checkAccessibility()
                    },
                    onOpenSettings: {
                        openPrivacySettings("Privacy_Accessibility")
                    },
                    onSkip: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .bluetoothPermission
                        }
                    },
                    onContinue: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .bluetoothPermission
                        }
                    }
                )
                .transition(.opacity)
                .task {
                    XPCHelperClient.shared.startMonitoringAccessibilityAuthorization()
                    checkAccessibility()
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(1))
                        checkAccessibility()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .accessibilityAuthorizationChanged)) { notification in
                    if let granted = notification.userInfo?["granted"] as? Bool {
                        handleAccessibilityStateChange(granted)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    checkAccessibility()
                }

            case .bluetoothPermission:
                PermissionRequestView(
                    icon: Image(systemName: "headphones"),
                    title: "Enable Bluetooth Accessories",
                    description: "anotherNotch can show when your Bluetooth audio accessories connect, including their battery level when available.",
                    privacyNote: "Bluetooth access is used only for connected accessory notifications.",
                    isGranted: bluetoothGranted,
                    hasRequested: bluetoothRequested,
                    onAllow: {
                        bluetoothRequested = true
                        Task {
                            let granted = await requestBluetoothPermission()
                            if granted {
                                Defaults[.showBluetoothDeviceConnectionIndicator] = true
                                bluetoothGranted = true
                                withAnimation(.easeInOut(duration: 0.6)) {
                                    step = .musicPermission
                                }
                            } else {
                                openPrivacySettings("Privacy_Bluetooth")
                            }
                        }
                    },
                    onOpenSettings: {
                        openPrivacySettings("Privacy_Bluetooth")
                    },
                    onSkip: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .musicPermission
                        }
                    },
                    onContinue: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .musicPermission
                        }
                    }
                )
                .transition(.opacity)
                .task {
                    checkBluetooth()
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(1))
                        checkBluetooth()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    checkBluetooth()
                }

            case .musicPermission:
                MusicControllerSelectionView(
                    onContinue: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .moduleSelection
                        }
                    }
                )
                .transition(.opacity)

            case .moduleSelection:
                OnboardingModuleSelectionView(selectedModules: $selectedModules) {
                    installSelectedModules()
                    withAnimation(.easeInOut(duration: 0.6)) {
                        AnotherNotchViewCoordinator.shared.firstLaunch = false
                        step = .finished
                    }
                }
                .transition(.opacity)

            case .finished:
                OnboardingFinishView(onFinish: onFinish, onOpenSettings: onOpenSettings)
            }
        }
        .frame(width: 400, height: 600)
    }

    // MARK: - Permission Request Logic

    private func checkAccessibility() {
        let authorized = AXIsProcessTrusted()
        handleAccessibilityStateChange(authorized)
    }

    private func handleAccessibilityStateChange(_ granted: Bool) {
        if granted != accessibilityGranted {
            accessibilityGranted = granted
            if granted {
                Defaults[.hudReplacement] = true
                withAnimation(.easeInOut(duration: 0.6)) {
                    step = .bluetoothPermission
                }
            }
        }
    }

    private func checkBluetooth() {
        let authorized = (CBManager.authorization == .allowedAlways)
        if authorized != bluetoothGranted {
            bluetoothGranted = authorized
            if authorized {
                Defaults[.showBluetoothDeviceConnectionIndicator] = true
                withAnimation(.easeInOut(duration: 0.6)) {
                    step = .musicPermission
                }
            }
        }
    }

    private func openPrivacySettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func installSelectedModules() {
        for module in selectedModules {
            FeatureModuleRegistry.shared.install(module)

            switch module {
            case .home:
                break
            case .clipboard:
                Defaults[.clipboardHistoryEnabled] = true
            case .shelf:
                Defaults[.boringShelf] = true
            case .calendar:
                Defaults[.showCalendar] = true
            case .camera:
                Defaults[.showMirror] = true
            }
        }
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
                centralManager = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])
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
        guard let cont = continuation else { return }
        continuation = nil
        centralManager = nil
        cont.resume(returning: granted)
    }
}
