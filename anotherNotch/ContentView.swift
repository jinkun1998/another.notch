//
//  ContentView.swift
//  anotherNotchApp
//
//  Created by Harsh Vardhan Goswami  on 02/08/24
//  Modified by Richard Kunkli on 24/08/2024.
//

import AVFoundation
import AppKit
import Combine
import Defaults
import KeyboardShortcuts
import SwiftUI
import SwiftUIIntrospect

enum NotchTabTransition {
    static let standardDuration: TimeInterval = 0.24
    static let reducedMotionDuration: TimeInterval = 0.12
}

@MainActor
struct ContentView: View {
    @EnvironmentObject var vm: AnotherNotchViewModel
    @ObservedObject var webcamManager = WebcamManager.shared

    @ObservedObject var coordinator = AnotherNotchViewCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var brightnessManager = BrightnessManager.shared
    @ObservedObject private var clipboardHistory = ClipboardHistoryStore.shared
    @ObservedObject private var modules = FeatureModuleRegistry.shared
    @State private var hoverTask: Task<Void, Never>?
    @State private var closingShellTask: Task<Void, Never>?
    @State private var openBounceTask: Task<Void, Never>?
    @State private var tabTransitionTask: Task<Void, Never>?
    @State private var isHovering: Bool = false
    @State private var isClosingShell: Bool = false
    @State private var isTabTransitioning: Bool = false
    @State private var shellExpansion: CGFloat = .zero
    @State private var openBounceScale: CGFloat = 1
    @State private var outgoingExpandedModule: FeatureModuleID?
    @State private var closingNotchSize: CGSize?
    @State private var anyDropDebounceTask: Task<Void, Never>?

    @State private var gestureProgress: CGFloat = .zero

    @State private var haptics: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Default(.useMusicVisualizer) var useMusicVisualizer
    @Default(.rotateAlbumArt) var rotateAlbumArt

    @Default(.showNotHumanFace) var showNotHumanFace
    @Default(.notchTransparency) var notchTransparency
    @Default(.notchGradientBlackCoverage) var notchGradientBlackCoverage
    @Default(.bottomCornerRadius) var bottomCornerRadius

    private var openAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.1) : .smooth(duration: 0.14, extraBounce: 0)
    }

    private var closeAnimation: Animation {
        .easeOut(duration: closeAnimationDuration)
    }

    private var closeAnimationDuration: TimeInterval {
        reduceMotion ? 0.12 : 0.24
    }

    private var interactionAnimation: Animation {
        reduceMotion ? .linear(duration: 0.1) : .easeOut(duration: 0.16)
    }

    private var resizeAnimation: Animation {
        reduceMotion
            ? .linear(duration: NotchTabTransition.reducedMotionDuration)
            : .easeInOut(duration: NotchTabTransition.standardDuration)
    }

    private var tabTransitionDuration: TimeInterval {
        reduceMotion
            ? NotchTabTransition.reducedMotionDuration
            : NotchTabTransition.standardDuration
    }

    private let extendedHoverPadding: CGFloat = 30
    private let zeroHeightHoverPadding: CGFloat = 10
    private let powerNotificationIconWidth: CGFloat = 44
    private let powerNotificationTextOuterMargin: CGFloat = 20
    private let powerNotificationNotchMargin: CGFloat = 40
    private let notchVisualTopOffset: CGFloat = -0.4
    private let closedNotchBottomExtension: CGFloat = 0.4

    private var physicalNotchWidth: CGFloat {
        max(0, vm.closedNotchSize.width - cornerRadiusInsets.closed.top)
    }

    private var physicalNotchReservation: some View {
        Rectangle()
            .fill(.clear)
            .frame(
                width: vm.closedNotchSize.width,
                height: vm.effectiveClosedNotchHeight
            )
    }

    private var clipboardNotchMaskSize: CGSize {
        .init(
            width: vm.closedNotchSize.width + cornerRadiusInsets.closed.top,
            height: vm.effectiveClosedNotchHeight + cornerRadiusInsets.closed.bottom
        )
    }

    private var powerNotificationTextWidth: CGFloat {
        let font = NSFont.preferredFont(forTextStyle: .subheadline)
        let textWidth = (batteryModel.statusText as NSString).size(withAttributes: [.font: font]).width
        return ceil(textWidth) + powerNotificationTextOuterMargin + powerNotificationNotchMargin
    }

    private func interpolate(_ from: CGFloat, _ to: CGFloat) -> CGFloat {
        from + (to - from) * shellExpansion
    }

    private func interpolate(_ from: CGSize, _ to: CGSize) -> CGSize {
        .init(
            width: interpolate(from.width, to.width),
            height: interpolate(from.height, to.height)
        )
    }

    private var openedHorizontalPadding: CGFloat {
        Defaults[.cornerRadiusScaling]
            ? cornerRadiusInsets.opened.top
            : cornerRadiusInsets.opened.bottom
    }

    private var shellHorizontalPadding: CGFloat {
        if coordinator.helloAnimationRunning {
            return 0
        }
        return interpolate(cornerRadiusInsets.closed.bottom, openedHorizontalPadding)
    }

    private var topCornerRadius: CGFloat {
        interpolate(
            cornerRadiusInsets.closed.top,
            Defaults[.cornerRadiusScaling] ? cornerRadiusInsets.opened.top : cornerRadiusInsets.closed.top
        )
    }

    private var currentNotchShape: NotchShape {
        NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: interpolate(
                cornerRadiusInsets.closed.bottom,
                bottomCornerRadius
            )
        )
    }

    private var isClosingShellActive: Bool {
        isClosingShell || vm.isClosingTransition
    }

    private var opaqueNotchCoverage: CGFloat {
        notchGradientBlackCoverage
    }

    private var sharedExpandedContentInset: CGFloat {
        expandedContentInset(screenUUID: vm.screenUUID)
    }

    private var expandedContentHeight: CGFloat {
        max(0, shellFrameSize.height - openNotchHeaderHeight)
    }

    private var shellFrameSize: CGSize {
        if vm.notchState == .open {
            return interpolate(vm.openingNotchSize ?? closedNotchShellSize, vm.notchSize)
        }
        if isClosingShellActive, let closingNotchSize {
            return interpolate(closedNotchShellSize, closingNotchSize)
        }
        return closedNotchShellSize
    }

    private var shouldRotateClosedAlbumArt: Bool {
        rotateAlbumArt && musicManager.isPlaying && !reduceMotion
    }

    private var notchBackground: some View {
        let horizontalInset = (1 - opaqueNotchCoverage) / 2
        let leadingEdgeOpacity = notchTransparency * 0.25
        let trailingEdgeOpacity = notchTransparency * 0.18

        return ZStack {
            Color.black.opacity(1 - shellExpansion)
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(leadingEdgeOpacity), location: 0),
                    .init(color: .black, location: horizontalInset),
                    .init(color: .black, location: 1 - horizontalInset),
                    .init(color: .black.opacity(trailingEdgeOpacity), location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: opaqueNotchCoverage),
                        .init(color: .black.opacity(0.3), location: min(0.98, opaqueNotchCoverage + 0.1)),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .opacity(shellExpansion)
        }
    }

    private var showsClosedSystemHUD: Bool {
        coordinator.sneakPeek.show
            && coordinator.sneakPeek.type != .music
            && coordinator.sneakPeek.type != .battery
            && vm.notchState == .closed
    }

    private var showsMusicSneakPeek: Bool {
        coordinator.sneakPeek.show
            && coordinator.sneakPeek.type == .music
            && vm.notchState == .closed
            && !vm.hideOnClosed
            && Defaults[.sneakPeekStyles] == .standard
    }

    private var showsCompactMusicActivity: Bool {
        if showsMusicSneakPeek {
            return true
        }

        let musicCanReplaceClosedContent = !coordinator.expandingView.show
            || coordinator.expandingView.type == .music

        guard vm.notchState == .closed,
              !vm.hideOnClosed,
              musicCanReplaceClosedContent
        else { return false }

        return (musicManager.isPlaying || !musicManager.isPlayerIdle)
            && coordinator.musicLiveActivityEnabled
    }

    private var sneakPeekAnimation: Animation {
        .easeInOut(duration: reduceMotion ? 0.12 : 0.24)
    }

    private var isScrollableTab: Bool {
        modules.supportsScrolling(coordinator.currentView)
    }

    private var closedNotchContentSize: CGSize {
        let baseSize = CGSize(width: vm.closedNotchSize.width, height: vm.effectiveClosedNotchHeight)
        guard baseSize.height > 0 else { return baseSize }

        if coordinator.helloAnimationRunning {
            return .init(width: baseSize.width * 1.26, height: 120)
        }

        if showsMusicSneakPeek {
            return .init(width: max(baseSize.width, 260), height: baseSize.height + 40)
        }

        if let entry = clipboardHistory.hudEntry {
            if entry.kind == .image {
                return .init(width: max(baseSize.width + 96, 260), height: max(baseSize.height, 54))
            }
            return .init(width: max(baseSize.width + 130, 280), height: max(baseSize.height, 58))
        }

        if coordinator.expandingView.type == .battery && coordinator.expandingView.show
            && vm.notchState == .closed && Defaults[.batteryFeatureEnabled] && Defaults[.showBatteryIndicator] && Defaults[.showPowerStatusNotifications]
        {
            return .init(
                width: physicalNotchWidth + powerNotificationTextWidth + powerNotificationIconWidth,
                height: baseSize.height
            )
        }

        if coordinator.expandingView.type == .bluetoothDevice && coordinator.expandingView.show
            && vm.notchState == .closed
        {
            if Defaults[.bluetoothDeviceIndicatorRows] == .two {
                return .init(
                    width: max(baseSize.width + 90, 250),
                    height: Defaults[.showBluetoothDeviceName] ? baseSize.height + 22 : baseSize.height
                )
            } else {
                return .init(
                    width: baseSize.width + (Defaults[.showBluetoothDeviceName] ? 210 : 90),
                    height: baseSize.height
                )
            }
        }

        if showsClosedSystemHUD {
            if Defaults[.closedHUDRows] == .two {
                return .init(width: max(baseSize.width + 120, 280), height: baseSize.height + 22)
            } else {
                let wingWidth = max(0, baseSize.height - 12) * 1.5
                return .init(
                    width: baseSize.width + (2 * wingWidth + 28),
                    height: baseSize.height
                )
            }
        } else if showsCompactMusicActivity
        {
            return .init(
                width: baseSize.width + (2 * max(0, baseSize.height - 12) + 22),
                height: baseSize.height
            )
        } else if !coordinator.expandingView.show && vm.notchState == .closed
            && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace]
            && !vm.hideOnClosed
        {
            return .init(
                width: baseSize.width + (2 * max(0, baseSize.height - 12) + 20),
                height: baseSize.height
            )
        }

        return baseSize
    }

    private var closedNotchShellSize: CGSize {
        let contentSize = closedNotchContentSize
        return .init(
            width: contentSize.width,
            height: contentSize.height + closedNotchBottomExtension
        )
    }

    var body: some View {
        // Calculate scale based on gesture progress only
        let gestureScale: CGFloat = {
            guard gestureProgress != 0 else { return 1.0 }
            let scaleFactor = 1.0 + gestureProgress * 0.01
            return max(0.6, scaleFactor)
        }()
        
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                notchLayout()
                    .frame(alignment: .top)
                    .padding(
                        .horizontal,
                        shellHorizontalPadding
                    )
                    .padding([.horizontal, .bottom], 12 * shellExpansion)
                    .frame(
                        width: shellFrameSize.width,
                        height: shellFrameSize.height,
                        alignment: .top
                    )
                    .background {
                        notchBackground
                    }
                    .clipShape(currentNotchShape)
                    .scaleEffect(openBounceScale, anchor: .top)
                    .shadow(
                        color: ((shellExpansion > 0 || isHovering) && Defaults[.enableShadow])
                            ? .black.opacity(0.7) : .clear, radius: Defaults[.cornerRadiusScaling] ? 6 : 4
                    )
                    .padding(
                        .bottom,
                        vm.effectiveClosedNotchHeight == 0 ? 10 : 0
                    )
                    .conditionalModifier(true) { view in
                        return view
                            .animation(sneakPeekAnimation, value: shellFrameSize)
                            .animation(interactionAnimation, value: gestureProgress)
                    }
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        handleHover(hovering)
                    }
                    .onTapGesture {
                        doOpen()
                    }
                    .conditionalModifier(Defaults[.enableGestures] && !isScrollableTab) { view in
                        view
                            .panGesture(direction: .down) { translation, phase in
                                handleDownGesture(translation: translation, phase: phase)
                            }
                    }
                    .conditionalModifier(Defaults[.closeGestureEnabled] && Defaults[.enableGestures] && !isScrollableTab) { view in
                        view
                            .panGesture(direction: .up) { translation, phase in
                                handleUpGesture(translation: translation, phase: phase)
                            }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .sharingDidFinish)) { _ in
                        if vm.notchState == .open && !isHovering && !vm.isBatteryPopoverActive {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if self.vm.notchState == .open && !self.isHovering && !self.vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose {
                                        self.vm.close()
                                    }
                                }
                            }
                        }
                    }
                    .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)) { notification in
                        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                              application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }

                        if vm.notchState == .open && !SharingStateManager.shared.preventNotchClose {
                            vm.close()
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                        if vm.notchState == .open && !SharingStateManager.shared.preventNotchClose {
                            vm.close()
                        }
                    }
                    .onChange(of: vm.notchState) { _, newState in
                        if newState == .closed && isHovering {
                            withAnimation {
                                isHovering = false
                            }
                        }

                        guard newState != .open else { return }
                        tabTransitionTask?.cancel()
                        outgoingExpandedModule = nil
                        isTabTransitioning = false
                    }
                    .onChange(of: coordinator.currentView) { oldView, view in
                        if vm.notchState == .open {
                            hoverTask?.cancel()
                            beginTabTransition(from: oldView, to: view)
                        } else {
                            hoverTask?.cancel()
                        }
                    }
                    .onChange(of: modules.installedIDs) { _, _ in
                        if vm.notchState == .open {
                            vm.notchSize = openNotchSize(
                                for: coordinator.currentView,
                                screenUUID: vm.screenUUID
                            )
                        } else {
                            let closedSize = getClosedNotchSize(screenUUID: vm.screenUUID)
                            vm.closedNotchSize = closedSize
                            vm.notchSize = closedSize
                        }
                    }
                    .onChange(of: notchGradientBlackCoverage) { _, _ in
                        guard vm.notchState == .open else { return }
                        vm.notchSize = openNotchSize(
                            for: coordinator.currentView,
                            screenUUID: vm.screenUUID
                        )
                    }
                    .onReceive(clipboardHistory.$entries) { _ in
                        guard vm.notchState == .open, coordinator.currentView == .clipboard else { return }
                        vm.notchSize = openNotchSize(for: .clipboard, screenUUID: vm.screenUUID)
                    }
                    .onChange(of: vm.isBatteryPopoverActive) {
                        if !vm.isBatteryPopoverActive && !isHovering && vm.notchState == .open && !SharingStateManager.shared.preventNotchClose {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if !self.vm.isBatteryPopoverActive && !self.isHovering && self.vm.notchState == .open && !SharingStateManager.shared.preventNotchClose {
                                        self.vm.close()
                                    }
                                }
                            }
                        }
                    }
                    .sensoryFeedback(.alignment, trigger: haptics)
                    .contextMenu {
                        Button("Settings") {
                            SettingsWindowController.present()
                        }
                        .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
                        //                    Button("Edit") { // Doesnt work....
                        //                        let dn = DynamicNotch(content: EditPanelView())
                        //                        dn.toggle()
                        //                    }
                        //                    .keyboardShortcut("E", modifiers: .command)
                    }
                if vm.chinHeight > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.01))
                        .frame(width: closedNotchContentSize.width, height: vm.chinHeight)
                }
            }
        }
        .padding(.bottom, 8)
        .frame(
            maxWidth: notchWindowSize(screenUUID: vm.screenUUID).width,
            maxHeight: max(notchWindowSize(screenUUID: vm.screenUUID).height, vm.notchSize.height + shadowPadding),
            alignment: .top
        )
        .compositingGroup()
        .scaleEffect(
            x: gestureScale,
            y: gestureScale,
            anchor: .top
        )
        .animation(.smooth, value: gestureProgress)
        .background(dragDetector)
        .preferredColorScheme(.dark)
        .environmentObject(vm)
        .onAppear {
            shellExpansion = vm.notchState == .open ? 1 : 0
            MusicManager.shared.forceUpdate()
            updateClosedNotchViewport()
        }
        .onChange(of: vm.notchState) { _, state in
            closingShellTask?.cancel()
            openBounceTask?.cancel()

            guard state == .open else {
                openBounceScale = 1
                closingNotchSize = closingNotchSize ?? vm.notchSize
                isClosingShell = !reduceMotion

                guard !reduceMotion else {
                    shellExpansion = 0
                    vm.isClosingTransition = false
                    return
                }

                withAnimation(closeAnimation) {
                    shellExpansion = 0
                }
                closingShellTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(Int(closeAnimationDuration * 1_000)))
                    guard !Task.isCancelled, vm.notchState == .closed else { return }
                    isClosingShell = false
                    closingNotchSize = nil
                    vm.isClosingTransition = false
                    updateClosedNotchViewport()
                }
                return
            }

            isClosingShell = false
            closingNotchSize = vm.notchSize
            withAnimation(openAnimation) {
                shellExpansion = 1
            }
            triggerOpenBounce()
        }
        .onChange(of: vm.notchSize) { _, size in
            if vm.notchState == .open {
                closingNotchSize = size
            }
        }
        .onChange(of: coordinator.helloAnimationRunning) { _, _ in
            updateClosedNotchViewport()
        }
        .onChange(of: coordinator.sneakPeek.show) { _, _ in
            updateClosedNotchViewport()
        }
        .onChange(of: coordinator.sneakPeek.type) { _, _ in
            updateClosedNotchViewport()
        }
        .onReceive(musicManager.$isPlaying.combineLatest(musicManager.$isPlayerIdle)) { _, _ in
            updateClosedNotchViewport()
        }
        .onChange(of: vm.anyDropZoneTargeting) { _, isTargeted in
            anyDropDebounceTask?.cancel()

            if isTargeted {
                guard modules.isAvailable(.shelf) else { return }
                if vm.notchState == .closed {
                    coordinator.currentView = .shelf
                    doOpen()
                }
                return
            }

            anyDropDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }

                if vm.dropEvent {
                    vm.dropEvent = false
                    return
                }

                vm.dropEvent = false
                if !SharingStateManager.shared.preventNotchClose {
                    vm.close()
                }
            }
        }
    }

    @ViewBuilder
    private func notchLayout() -> some View {
        VStack(alignment: .center, spacing: 0) {
            VStack(alignment: .center, spacing: 0) {
                if coordinator.helloAnimationRunning {
                    HelloAnimation(onFinish: {
                        vm.closeHello()
                    })
                    .padding(.vertical, 8)
                    .frame(
                        width: vm.closedNotchSize.width,
                        height: 72
                    )
                    .padding(.top, 38)
                } else {
                    if vm.notchState == .open || isClosingShellActive {
                        AnotherNotchHeader()
                            .frame(height: openNotchHeaderHeight)
                            .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
                    } else {
                        compactNotchContent()
                    }
                }
            }

            .overlay(alignment: .top) {
                if vm.notchState == .closed && !isClosingShellActive {
                    physicalNotchReservation
                        .allowsHitTesting(false)
                }
            }
            .zIndex(2)
            if vm.notchState == .open || isClosingShellActive {
                ZStack(alignment: .top) {
                    if let outgoingExpandedModule {
                        expandedModuleView(outgoingExpandedModule)
                            .id(outgoingExpandedModule)
                            .opacity(isTabTransitioning ? 0 : 1)
                            .transition(.opacity)
                            .allowsHitTesting(false)
                    }

                    expandedModuleView(coordinator.currentView)
                        .id(coordinator.currentView)
                        .opacity(outgoingExpandedModule == nil || isTabTransitioning ? 1 : 0)
                        .transition(.opacity)
                }
                .padding(.top, expandedContentTopInset(screenUUID: vm.screenUUID))
                .padding(.horizontal, sharedExpandedContentInset)
                .padding(.bottom, sharedExpandedContentInset)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: expandedContentHeight,
                    alignment: .top
                )
                .opacity(shellExpansion)
                .zIndex(1)
                .allowsHitTesting(vm.notchState == .open)
                .opacity(
                    gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func compactNotchContent() -> some View {
        if let entry = clipboardHistory.hudEntry, vm.notchState == .closed {
                        ClipboardHUD(entry: entry, physicalNotchMaskSize: clipboardNotchMaskSize)
                            .transition(.opacity)
                    } else if !showsMusicSneakPeek
                        && coordinator.expandingView.type == .battery && coordinator.expandingView.show
                        && vm.notchState == .closed && Defaults[.batteryFeatureEnabled] && Defaults[.showBatteryIndicator] && Defaults[.showPowerStatusNotifications]
                    {
                        HStack(spacing: 0) {
                            Text(batteryModel.statusText)
                                .font(.subheadline)
                                .foregroundStyle(.white)
                                .padding(.leading, powerNotificationTextOuterMargin)
                                .padding(.trailing, powerNotificationNotchMargin)
                                .frame(width: powerNotificationTextWidth, alignment: .trailing)

                            Rectangle()
                                .fill(.black)
                                .frame(width: physicalNotchWidth)

                            BatteryView(
                                levelBattery: batteryModel.levelBattery,
                                isPluggedIn: batteryModel.isPluggedIn,
                                isCharging: batteryModel.isCharging,
                                isInLowPowerMode: batteryModel.isInLowPowerMode,
                                batteryWidth: 30,
                                isForNotification: true
                            )
                            .frame(width: powerNotificationIconWidth, alignment: .leading)
                        }
                        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
                    } else if !showsMusicSneakPeek
                        && coordinator.expandingView.type == .bluetoothDevice && coordinator.expandingView.show
                        && vm.notchState == .closed
                    {
                        BluetoothConnectionIndicator(
                            device: coordinator.expandingView,
                            physicalNotchWidth: max(0, vm.closedNotchSize.width - cornerRadiusInsets.closed.top),
                            topRowHeight: vm.effectiveClosedNotchHeight,
                            rowCount: Defaults[.bluetoothDeviceIndicatorRows],
                            showsDeviceName: Defaults[.showBluetoothDeviceName]
                        )
                        .frame(height: closedNotchContentSize.height, alignment: .center)
                      } else if showsClosedSystemHUD {
                          SystemEventIndicatorModifier(
                              eventType: $coordinator.sneakPeek.type,
                              value: $coordinator.sneakPeek.value,
                              icon: $coordinator.sneakPeek.icon,
                              sendEventBack: { newVal in
                                  switch coordinator.sneakPeek.type {
                                  case .volume:
                                      VolumeManager.shared.setAbsolute(Float32(newVal))
                                  case .brightness:
                                      BrightnessManager.shared.setAbsolute(value: Float32(newVal))
                                  default:
                                      break
                                  }
                              }
                          )
                          .frame(height: closedNotchContentSize.height, alignment: .center)
                          .transition(.opacity)
                      } else if showsCompactMusicActivity {
                          musicLiveActivity()
                              .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
                              .background {
                                  if showsMusicSneakPeek {
                                      physicalNotchReservation
                                  }
                              }
                      } else if !coordinator.expandingView.show && vm.notchState == .closed && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace] && !vm.hideOnClosed  {
                          anotherNotchFaceAnimation()
                    } else {
                        Rectangle().fill(.clear).frame(width: vm.closedNotchSize.width - 20, height: vm.effectiveClosedNotchHeight)
                    }

                      if !isClosingShellActive && coordinator.sneakPeek.show
                          && coordinator.sneakPeek.type == .music && showsMusicSneakPeek
                      {
                          HStack(alignment: .center) {
                              Image(systemName: "music.note")
                              GeometryReader { geometry in
                                  MarqueeText(.constant(playbackSneakPeekText), textColor: Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6) : .gray, minDuration: 1, frameWidth: geometry.size.width)
                              }
                          }
                          .frame(width: max(vm.closedNotchSize.width, 260))
                          .foregroundStyle(.gray)
                          .padding(.vertical, 10)
                      }
    }

    @ViewBuilder
    private func expandedModuleView(_ view: FeatureModuleID) -> some View {
        switch view {
        case .home:
            NotchHomeView()
                .frame(maxWidth: .infinity)
                .frame(height: musicContentSize.height)
        case .clipboard:
            ClipboardHistoryView()
                .frame(maxWidth: .infinity)
        case .shelf:
            ShelfView()
        case .calendar:
            CalendarView()
                .frame(maxWidth: .infinity)
                .frame(height: calendarContentSize.height)
                .onHover { vm.isHoveringCalendar = $0 }
                .onDisappear { vm.isHoveringCalendar = false }
                .environmentObject(vm)
        case .camera:
            CameraPreviewView(webcamManager: webcamManager)
                .frame(width: 160, height: 160)
        }
    }

    private func beginTabTransition(from oldView: FeatureModuleID, to newView: FeatureModuleID) {
        tabTransitionTask?.cancel()
        outgoingExpandedModule = oldView
        isTabTransitioning = false

        withAnimation(resizeAnimation) {
            vm.notchSize = openNotchSize(for: newView, screenUUID: vm.screenUUID)
        }

        tabTransitionTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }

            withAnimation(resizeAnimation) {
                isTabTransitioning = true
            }

            try? await Task.sleep(for: .milliseconds(Int(tabTransitionDuration * 1_000)))
            guard !Task.isCancelled else { return }

            outgoingExpandedModule = nil
            isTabTransitioning = false
        }
    }

    private func updateClosedNotchViewport() {
        guard vm.notchState == .closed, !isClosingShellActive else { return }
        vm.closedViewportSize = closedNotchShellSize
    }

    private var playbackSneakPeekText: String {
        [musicManager.songTitle, musicManager.artistName]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " - ")
    }

    @ViewBuilder
    private func anotherNotchFaceAnimation() -> some View {
        HStack {
            HStack {
                Rectangle()
                    .fill(.clear)
                    .frame(
                        width: max(0, vm.effectiveClosedNotchHeight - 12),
                        height: max(0, vm.effectiveClosedNotchHeight - 12)
                    )
                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width - 20)
                MinimalFaceFeatures()
            }
        }.frame(
            height: vm.effectiveClosedNotchHeight,
            alignment: .center
        )
    }

    @ViewBuilder
    private func musicLiveActivity() -> some View {
        let compactMediaSize = max(0, vm.effectiveClosedNotchHeight - 12)

        HStack(spacing: 4) {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !shouldRotateClosedAlbumArt)) { timeline in
                Image(nsImage: musicManager.albumArt)
                    .resizable()
                    .clipped()
                    .clipShape(Circle())
                    .overlay {
                        Circle().stroke(.white.opacity(0.18), lineWidth: 1)
                    }
                    .rotationEffect(
                        .degrees(
                            shouldRotateClosedAlbumArt
                                ? timeline.date.timeIntervalSinceReferenceDate
                                    .truncatingRemainder(dividingBy: 8) / 8 * 360
                                : 0
                        )
                    )
                    .frame(
                        width: compactMediaSize,
                        height: compactMediaSize
                    )
                    .zIndex(3)
                    .padding(.leading, 10)
            }

            Rectangle()
                .fill(.black)
                .overlay(
                    HStack(alignment: .top) {
                        if coordinator.expandingView.show
                            && coordinator.expandingView.type == .music
                        {
                            MarqueeText(
                                .constant(musicManager.songTitle),
                                textColor: Defaults[.coloredSpectrogram]
                                    ? Color(nsColor: musicManager.avgColor) : Color.gray,
                                minDuration: 0.4,
                                frameWidth: 100
                            )
                            .opacity(
                                (coordinator.expandingView.show
                                    && Defaults[.sneakPeekStyles] == .inline)
                                    ? 1 : 0
                            )
                            Spacer(minLength: vm.closedNotchSize.width)
                            // Song Artist
                            Text(musicManager.artistName)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(
                                    Defaults[.coloredSpectrogram]
                                        ? Color(nsColor: musicManager.avgColor)
                                        : Color.gray
                                )
                                .opacity(
                                    (coordinator.expandingView.show
                                        && coordinator.expandingView.type == .music
                                        && Defaults[.sneakPeekStyles] == .inline)
                                        ? 1 : 0
                                )
                        }
                    }
                )
                .frame(
                    width: (coordinator.expandingView.show
                        && coordinator.expandingView.type == .music
                        && Defaults[.sneakPeekStyles] == .inline)
                        ? 380
                        : vm.closedNotchSize.width
                            + -cornerRadiusInsets.closed.top
                )

            HStack {
                if useMusicVisualizer {
                    DynamicIslandWaveform(isPlaying: musicManager.isPlaying)
                        .scaleEffect(0.68)
                        .frame(
                            width: compactMediaSize,
                            height: compactMediaSize
                        )
                } else {
                    LottieAnimationContainer()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(
                width: compactMediaSize,
                height: compactMediaSize,
                alignment: .center
            )
            .padding(.trailing, 10)
        }
        .frame(
            height: vm.effectiveClosedNotchHeight,
            alignment: .center
        )
    }

    var dragDetector: some View {
        EmptyView()
    }

    private func doOpen() {
        vm.open()
    }

    private func triggerOpenBounce() {
        guard !reduceMotion else { return }

        openBounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, vm.notchState == .open else { return }

            withAnimation(.easeOut(duration: 0.04)) {
                openBounceScale = 1.04
            }

            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled, vm.notchState == .open else { return }

            withAnimation(.spring(response: 0.12, dampingFraction: 0.8)) {
                openBounceScale = 1
            }
        }
    }

    // MARK: - Hover Management

    private func handleHover(_ hovering: Bool) {
        if coordinator.firstLaunch { return }
        hoverTask?.cancel()
        
        if hovering {
            withAnimation(interactionAnimation) {
                isHovering = true
            }
            
            if vm.notchState == .closed && Defaults[.enableHaptics] {
                haptics.toggle()
            }
            
            guard vm.notchState == .closed,
                  !coordinator.sneakPeek.show,
                  Defaults[.openNotchOnHover] else { return }
            
            hoverTask = Task {
                try? await Task.sleep(for: .seconds(Defaults[.minimumHoverDuration]))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    guard self.vm.notchState == .closed,
                          self.isHovering,
                          self.vm.isMouseHovering(),
                          !self.coordinator.sneakPeek.show else { return }
                    
                    self.doOpen()
                }
            }
        } else {
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    guard !self.vm.isMouseHovering() else { return }

                    withAnimation(interactionAnimation) {
                        self.isHovering = false
                    }
                    
                    if self.vm.notchState == .open && !self.vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose {
                        self.vm.close()
                    }
                }
            }
        }
    }

    // MARK: - Gesture Handling

    private func handleDownGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard !isScrollableTab, vm.notchState == .closed else { return }

        if phase == .ended {
            withAnimation(interactionAnimation) { gestureProgress = .zero }
            return
        }

        withAnimation(interactionAnimation) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * 20
        }

        if translation > Defaults[.gestureSensitivity] {
            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
            withAnimation(interactionAnimation) {
                gestureProgress = .zero
            }
            doOpen()
        }
    }

    private func handleUpGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard !isScrollableTab, vm.notchState == .open && !vm.isHoveringCalendar else { return }

        withAnimation(interactionAnimation) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * -20
        }

        if phase == .ended {
            withAnimation(interactionAnimation) {
                gestureProgress = .zero
            }
        }

        if translation > Defaults[.gestureSensitivity] {
            withAnimation(interactionAnimation) {
                isHovering = false
            }
            if !SharingStateManager.shared.preventNotchClose { 
                gestureProgress = .zero
                vm.close()
            }

            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
        }
    }
}

struct FullScreenDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let onDrop: () -> Void

    func dropEntered(info _: DropInfo) {
        isTargeted = true
    }

    func dropExited(info _: DropInfo) {
        isTargeted = false
    }

    func performDrop(info _: DropInfo) -> Bool {
        isTargeted = false
        onDrop()
        return true
    }

}

#Preview {
    let vm = AnotherNotchViewModel()
    vm.open()
    return ContentView()
        .environmentObject(vm)
        .frame(width: vm.notchSize.width, height: vm.notchSize.height)
}
