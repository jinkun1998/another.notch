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

@MainActor
struct ContentView: View {
    @EnvironmentObject var vm: AnotherNotchViewModel
    @ObservedObject var webcamManager = WebcamManager.shared

    @ObservedObject var coordinator = AnotherNotchViewCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var brightnessManager = BrightnessManager.shared
    @ObservedObject private var clipboardHistory = ClipboardHistoryStore.shared
    @State private var hoverTask: Task<Void, Never>?
    @State private var closingShellTask: Task<Void, Never>?
    @State private var musicHeroTransitionTask: Task<Void, Never>?
    @State private var isHovering: Bool = false
    @State private var isClosingShell: Bool = false
    @State private var shellExpansion: CGFloat = .zero
    @State private var anyDropDebounceTask: Task<Void, Never>?

    @State private var gestureProgress: CGFloat = .zero

    @State private var haptics: Bool = false
    @State private var isMusicHeroTransitionActive = false
    @Namespace var albumArtNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Default(.useMusicVisualizer) var useMusicVisualizer
    @Default(.rotateAlbumArt) var rotateAlbumArt

    @Default(.showNotHumanFace) var showNotHumanFace
    @Default(.notchTransparency) var notchTransparency
    @Default(.notchGradientBlackCoverage) var notchGradientBlackCoverage
    @Default(.bottomCornerRadius) var bottomCornerRadius

    private var openAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.18) : .interpolatingSpring(stiffness: 340, damping: 30)
    }

    private var closeAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .interpolatingSpring(stiffness: 420, damping: 38)
    }

    private var interactionAnimation: Animation {
        reduceMotion ? .linear(duration: 0.1) : .easeOut(duration: 0.16)
    }

    private let extendedHoverPadding: CGFloat = 30
    private let zeroHeightHoverPadding: CGFloat = 10
    private let powerNotificationIconWidth: CGFloat = 44
    private let powerNotificationTextOuterMargin: CGFloat = 20
    private let powerNotificationNotchMargin: CGFloat = 40

    private var physicalNotchWidth: CGFloat {
        max(0, vm.closedNotchSize.width - cornerRadiusInsets.closed.top)
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

    private var displaysExpandedContent: Bool {
        vm.notchState == .open || isClosingShell
    }

    private var expandedContentScale: CGFloat {
        reduceMotion ? 1 : 0.92 + shellExpansion * 0.08
    }

    private var expandedContentHeight: CGFloat {
        let notchHeight = isClosingShell
            ? openNotchSize(for: coordinator.currentView, screenUUID: vm.screenUUID).height
            : vm.notchSize.height
        return max(0, notchHeight - openNotchHeaderHeight)
    }

    private var albumArtTransition: Animation {
        reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.42, dampingFraction: 0.82)
    }

    private var shouldRotateClosedAlbumArt: Bool {
        rotateAlbumArt && musicManager.isPlaying && !reduceMotion
    }

    private var notchBackground: some View {
        let horizontalInset = (1 - notchGradientBlackCoverage) / 2
        let bottomFadeStart = notchGradientBlackCoverage

        return ZStack {
            Color.black.opacity(1 - shellExpansion)
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.25), location: 0),
                    .init(color: .black.opacity(0.96), location: horizontalInset),
                    .init(color: .black.opacity(0.96), location: 1 - horizontalInset),
                    .init(color: .black.opacity(0.18), location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: bottomFadeStart),
                        .init(color: .black.opacity(0.3), location: min(0.98, bottomFadeStart + 0.1)),
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

    private var isScrollableTab: Bool {
        switch coordinator.currentView {
        case .clipboard, .calendar, .shelf:
            true
        case .home, .camera:
            false
        }
    }

    private var closedNotchContentSize: CGSize {
        let baseSize = CGSize(width: vm.closedNotchSize.width, height: vm.effectiveClosedNotchHeight)
        guard baseSize.height > 0 else { return baseSize }

        if coordinator.helloAnimationRunning {
            return .init(width: baseSize.width * 1.26, height: 120)
        }

        if showsMusicSneakPeek {
            return .init(width: max(baseSize.width, 260), height: baseSize.height + 34)
        }

        if let entry = clipboardHistory.hudEntry {
            if entry.kind == .image {
                return .init(width: max(baseSize.width + 96, 260), height: max(baseSize.height, 54))
            }
            return .init(width: max(baseSize.width + 130, 280), height: max(baseSize.height, 58))
        }

        if coordinator.expandingView.type == .battery && coordinator.expandingView.show
            && vm.notchState == .closed && Defaults[.showPowerStatusNotifications]
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
                return .init(width: max(baseSize.width + 120, 280), height: max(baseSize.height, 58))
            } else {
                let wingWidth = max(0, baseSize.height - 12) * 1.5
                return .init(
                    width: baseSize.width + (2 * wingWidth + 28),
                    height: baseSize.height
                )
            }
        } else if (!coordinator.expandingView.show || coordinator.expandingView.type == .music)
            && vm.notchState == .closed && (musicManager.isPlaying || !musicManager.isPlayerIdle)
            && coordinator.musicLiveActivityEnabled && !vm.hideOnClosed
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

    var body: some View {
        // Calculate scale based on gesture progress only
        let gestureScale: CGFloat = {
            guard gestureProgress != 0 else { return 1.0 }
            let scaleFactor = 1.0 + gestureProgress * 0.01
            return max(0.6, scaleFactor)
        }()
        
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                NotchLayout()
                    .frame(alignment: .top)
                    .padding(
                        .horizontal,
                        shellHorizontalPadding
                    )
                    .padding([.horizontal, .bottom], 12 * shellExpansion)
                    .frame(
                        width: vm.notchState == .open ? vm.notchSize.width : closedNotchContentSize.width,
                        height: vm.notchState == .open ? vm.notchSize.height : closedNotchContentSize.height,
                        alignment: .top
                    )
                    .background {
                        notchBackground.clipShape(currentNotchShape)
                    }
                    .clipShape(currentNotchShape)
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
                            .animation(vm.notchState == .open ? openAnimation : closeAnimation, value: vm.notchState)
                            .animation(vm.notchState == .open ? openAnimation : closeAnimation, value: vm.notchSize)
                            .animation(.smooth(duration: 0.28), value: closedNotchContentSize)
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
                    .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)) { _ in
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
                    }
                    .onChange(of: coordinator.currentView) { _, view in
                        if vm.notchState == .open {
                            musicHeroTransitionTask?.cancel()
                            isMusicHeroTransitionActive = false
                        }

                        guard vm.notchState == .open else { return }
                        vm.notchSize = openNotchSize(for: view, screenUUID: vm.screenUUID)
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
                            DispatchQueue.main.async {
                                SettingsWindowController.shared.showWindow()
                            }
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
            maxWidth: windowSize.width,
            maxHeight: max(windowSize.height, vm.notchSize.height + shadowPadding),
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
        }
        .onChange(of: vm.notchState) { _, state in
            closingShellTask?.cancel()
            updateMusicHeroTransition(for: state)

            guard state == .open else {
                isClosingShell = !reduceMotion

                guard !reduceMotion else {
                    shellExpansion = 0
                    return
                }

                withAnimation(closeAnimation) {
                    shellExpansion = 0
                }
                closingShellTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(320))
                    guard !Task.isCancelled, vm.notchState == .closed else { return }
                    isClosingShell = false
                }
                return
            }

            isClosingShell = false
            withAnimation(openAnimation) {
                shellExpansion = 1
            }
        }
        .onChange(of: vm.anyDropZoneTargeting) { _, isTargeted in
            anyDropDebounceTask?.cancel()

            if isTargeted {
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
    func NotchLayout() -> some View {
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
                    if vm.notchState == .open || isClosingShell {
                        AnotherNotchHeader()
                            .frame(height: openNotchHeaderHeight)
                            .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
                    } else if let entry = clipboardHistory.hudEntry, vm.notchState == .closed {
                        ClipboardHUD(entry: entry, physicalNotchMaskSize: clipboardNotchMaskSize)
                            .transition(.opacity)
                    } else if coordinator.expandingView.type == .battery && coordinator.expandingView.show
                        && vm.notchState == .closed && Defaults[.showPowerStatusNotifications]
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
                    } else if coordinator.expandingView.type == .bluetoothDevice && coordinator.expandingView.show
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
                      } else if (!coordinator.expandingView.show || coordinator.expandingView.type == .music) && vm.notchState == .closed && (musicManager.isPlaying || !musicManager.isPlayerIdle) && coordinator.musicLiveActivityEnabled && !vm.hideOnClosed {
                          MusicLiveActivity()
                              .frame(alignment: .center)
                      } else if !coordinator.expandingView.show && vm.notchState == .closed && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace] && !vm.hideOnClosed  {
                          AnotherNotchFaceAnimation()
                    } else {
                        Rectangle().fill(.clear).frame(width: vm.closedNotchSize.width - 20, height: vm.effectiveClosedNotchHeight)
                    }

                      if !isClosingShell && coordinator.sneakPeek.show {
                          // Old sneak peek music
                          if coordinator.sneakPeek.type == .music {
                              if showsMusicSneakPeek {
                                  HStack(alignment: .center) {
                                      Image(systemName: "music.note")
                                      GeometryReader { geometry in
                                          MarqueeText(.constant(playbackSneakPeekText), textColor: Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6) : .gray, minDuration: 1, frameWidth: geometry.size.width)
                                      }
                                  }
                                  .frame(width: max(vm.closedNotchSize.width, 260))
                                  .foregroundStyle(.gray)
                                  .padding(.bottom, 10)
                              }
                          }
                      }
                  }
              }
              .conditionalModifier(!isClosingShell && coordinator.sneakPeek.show && coordinator.sneakPeek.type == .music && vm.notchState == .closed && !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard) { view in
                  view
                      .fixedSize()
              }
              .zIndex(2)
            if displaysExpandedContent {
                VStack {
                    switch coordinator.currentView {
                    case .home:
                        NotchHomeView(
                            albumArtNamespace: albumArtNamespace,
                            isHeroTransitionActive: isMusicHeroTransitionActive
                        )
                            .frame(width: musicContentSize.width, height: musicContentSize.height)
                    case .clipboard:
                        ClipboardHistoryView()
                            .frame(maxWidth: .infinity)
                            .frame(maxHeight: max(0, vm.notchSize.height - openNotchHeaderHeight), alignment: .top)
                    case .shelf:
                        ShelfView()
                            .padding(.vertical, 8)
                    case .calendar:
                        CalendarView()
                            .frame(width: calendarContentSize.width, height: calendarContentSize.height)
                            .onHover { vm.isHoveringCalendar = $0 }
                            .onDisappear { vm.isHoveringCalendar = false }
                            .environmentObject(vm)
                    case .camera:
                        CameraPreviewView(webcamManager: webcamManager)
                            .frame(width: 160, height: 160)
                            .padding(8)
                    }
                }
                .animation(nil, value: coordinator.currentView)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: expandedContentHeight,
                    alignment: .center
                )
                .scaleEffect(expandedContentScale, anchor: .top)
                .zIndex(1)
                .allowsHitTesting(vm.notchState == .open)
                .opacity(
                    gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], delegate: GeneralDropTargetDelegate(isTargeted: $vm.generalDropTargeting))
    }

    private var playbackSneakPeekText: String {
        [musicManager.songTitle, musicManager.artistName]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " - ")
    }

    @ViewBuilder
    func AnotherNotchFaceAnimation() -> some View {
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
    func MusicLiveActivity() -> some View {
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
                    .conditionalModifier(isMusicHeroTransitionActive) { view in
                        view
                            .matchedGeometryEffect(
                                id: "albumArt",
                                in: albumArtNamespace,
                                properties: .frame,
                                anchor: .center
                            )
                            .animation(albumArtTransition, value: vm.notchState)
                    }
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
                        .conditionalModifier(isMusicHeroTransitionActive) { view in
                            view
                                .matchedGeometryEffect(
                                    id: "spectrum",
                                    in: albumArtNamespace,
                                    properties: .frame,
                                    anchor: .center
                                )
                                .animation(albumArtTransition, value: vm.notchState)
                        }
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

    private func updateMusicHeroTransition(for notchState: NotchState) {
        musicHeroTransitionTask?.cancel()

        guard !reduceMotion, coordinator.currentView == .home else {
            isMusicHeroTransitionActive = false
            return
        }

        isMusicHeroTransitionActive = true
        musicHeroTransitionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(notchState == .open ? 500 : 700))
            guard !Task.isCancelled else { return }
            isMusicHeroTransitionActive = false
        }
    }

    @ViewBuilder
    var dragDetector: some View {
        if Defaults[.boringShelf] && vm.notchState == .closed {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
            vm.dropEvent = true
            ShelfStateViewModel.shared.load(providers)
            return true
        }
        } else {
            EmptyView()
        }
    }

    private func doOpen() {
        vm.open()
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

private struct BluetoothConnectionIndicator: View {
    let device: ExpandedItem
    let physicalNotchWidth: CGFloat
    let topRowHeight: CGFloat
    let rowCount: BluetoothDeviceIndicatorRows
    let showsDeviceName: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isIconTilted = false

    private var hasBattery: Bool {
        (0...1).contains(device.value)
    }

    var body: some View {
        Group {
            if rowCount == .two {
                VStack(spacing: 0) {
                    indicatorRow(showsDeviceName: false)
                        .frame(height: topRowHeight)
                    if showsDeviceName {
                        HStack(spacing: 0) {
                            Color.clear.frame(maxWidth: .infinity)
                            Text(device.subtitle)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(width: physicalNotchWidth)
                            Color.clear.frame(maxWidth: .infinity)
                        }
                        .frame(height: 22)
                    }
                }
            } else {
                indicatorRow(showsDeviceName: showsDeviceName)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.16)) {
                isIconTilted = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isIconTilted = false
                }
            }
        }
    }

    private var icon: some View {
        Image(systemName: device.icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .rotationEffect(.degrees(isIconTilted ? 9 : 0))
    }

    private func indicatorRow(showsDeviceName: Bool) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                icon
                if showsDeviceName {
                    Text(device.subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 12)

            Rectangle()
                .fill(.black)
                .frame(width: physicalNotchWidth)

            batteryStatus
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 12)
        }
    }

    @ViewBuilder
    private var batteryStatus: some View {
        if hasBattery {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.2), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: device.value)
                    .stroke(.green, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(device.value * 100))%")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
            }
            .frame(width: 24, height: 24)
        } else {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.green)
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

struct GeneralDropTargetDelegate: DropDelegate {
    @Binding var isTargeted: Bool

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .cancel)
    }

    func performDrop(info: DropInfo) -> Bool {
        return false
    }
}

#Preview {
    let vm = AnotherNotchViewModel()
    vm.open()
    return ContentView()
        .environmentObject(vm)
        .frame(width: vm.notchSize.width, height: vm.notchSize.height)
}
