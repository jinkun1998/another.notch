//
//  LockscreenMusicWidget.swift
//  anotherNotch
//

import AppKit
import Combine
import Defaults
import SkyLightWindow
import SwiftUI

// MARK: - Lockscreen Music Widget View

struct LockscreenMusicWidgetView: View {
    @ObservedObject private var musicManager = MusicManager.shared
    @ObservedObject private var volumeManager = VolumeManager.shared
    @Default(.lockscreenMusicWidgetSize) private var widgetSize
    @State private var dragging: Bool = false
    @State private var dragPosition: Double = 0
    @State private var lastDragged: Date = .distantPast
    @State private var showAudioSources: Bool = false

    var body: some View {
        let dim = widgetSize.dimensions
        let shape = RoundedRectangle(cornerRadius: dim.cornerRadius, style: .continuous)

        ZStack {
            VStack(spacing: widgetSize == .compact ? 8 : (widgetSize == .standard ? 10 : 12)) {
                headerRow(artSize: dim.artworkSize)
                timelineRow
                controlsRow
            }
            .padding(.horizontal, widgetSize == .large ? 18 : 16)
            .padding(.vertical, widgetSize == .large ? 14 : 12)
            .frame(width: dim.width, height: dim.height)
            .background {
                ZStack {
                    LiquidGlassSurface(shape: shape, opacity: 0.9, interactive: true)
                    RadialGradient(
                        colors: [Color(nsColor: musicManager.avgColor).opacity(0.32), .clear],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: dim.width * 0.6
                    )
                    .clipShape(shape)
                }
            }
            .overlay {
                shape.stroke(Color.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.4), radius: 18, y: 8)

            if showAudioSources {
                audioSourcesOverlay(dim: dim, shape: shape)
            }
        }
    }

    private func audioSourcesOverlay(dim: (width: CGFloat, height: CGFloat, artworkSize: CGFloat, cornerRadius: CGFloat), shape: RoundedRectangle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Audio Output")
                    .font(.system(size: widgetSize.titleSize, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        showAudioSources = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 24, height: 24)
                        .liquidGlassControl(in: Circle(), fallback: .white.opacity(0.12))
                }
                .buttonStyle(.plain)
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 3) {
                    ForEach(volumeManager.availableOutputDevices) { device in
                        let isSelected = device.id == volumeManager.currentOutputDevice?.id
                        Button {
                            volumeManager.selectOutputDevice(device)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: device.audioSourceIcon)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(isSelected ? .white : .white.opacity(0.75))
                                    .frame(width: 18)

                                Text(device.name)
                                    .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .rounded))
                                    .foregroundStyle(isSelected ? .white : .white.opacity(0.85))
                                    .lineLimit(1)

                                Spacer()

                                if let battery = device.bluetoothBatteryPercentage {
                                    HStack(spacing: 2) {
                                        Image(systemName: "battery.75")
                                            .font(.system(size: 9))
                                        Text("\(battery)%")
                                            .font(.system(size: 9, weight: .medium).monospacedDigit())
                                    }
                                    .foregroundStyle(.white.opacity(0.65))
                                }

                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Color.effectiveAccent)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color.white.opacity(0.15))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, widgetSize == .large ? 18 : 16)
        .padding(.vertical, widgetSize == .large ? 14 : 12)
        .frame(width: dim.width, height: dim.height)
        .background {
            LiquidGlassSurface(shape: shape, opacity: 0.95, interactive: true)
        }
        .clipShape(shape)
        .overlay {
            shape.stroke(Color.white.opacity(0.2), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    private func headerRow(artSize: CGFloat) -> some View {
        HStack(spacing: widgetSize == .large ? 14 : 12) {
            Image(nsImage: musicManager.albumArt)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: artSize, height: artSize)
                .clipShape(RoundedRectangle(cornerRadius: artSize > 50 ? 12 : 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: artSize > 50 ? 12 : 10, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(musicManager.songTitle)
                    .font(.system(size: widgetSize.titleSize, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(musicManager.artistName)
                    .font(.system(size: widgetSize.artistSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)

                if !musicManager.album.isEmpty {
                    Text(musicManager.album)
                        .font(.system(size: widgetSize == .large ? 12 : 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.60))
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                volumeManager.refreshOutputDevices()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    showAudioSources.toggle()
                }
            } label: {
                Image(systemName: volumeManager.currentOutputDevice?.audioSourceIcon ?? "airplayaudio")
                    .font(.system(size: widgetSize == .large ? 13 : 11, weight: .bold))
                    .foregroundStyle(showAudioSources ? Color.effectiveAccent : .white)
                    .frame(width: widgetSize == .large ? 30 : 26, height: widgetSize == .large ? 30 : 26)
                    .liquidGlassControl(in: Circle(), fallback: .white.opacity(0.1))
            }
            .buttonStyle(.plain)
        }
    }

    private var timelineRow: some View {
        TimelineView(.animation(minimumInterval: 0.5)) { timeline in
            let currentTime = musicManager.estimatedPlaybackPosition(at: timeline.date)
            let duration = max(0, musicManager.songDuration)
            let displayPos = dragging ? dragPosition : currentTime

            HStack(spacing: 8) {
                Text(formatTime(displayPos))
                    .font(.system(size: widgetSize == .large ? 11 : 10, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.70))
                    .frame(width: widgetSize == .large ? 38 : 34, alignment: .leading)

                CustomSlider(
                    value: Binding(
                        get: { dragging ? dragPosition : currentTime },
                        set: { dragPosition = $0 }
                    ),
                    range: 0...max(1, duration),
                    color: .white,
                    dragging: $dragging,
                    lastDragged: $lastDragged,
                    isEnabled: duration > 0,
                    onValueChange: { newPos in
                        musicManager.seek(to: newPos)
                    }
                )
                .frame(height: 8)

                Text("-\(formatTime(max(0, duration - displayPos)))")
                    .font(.system(size: widgetSize == .large ? 11 : 10, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.70))
                    .frame(width: widgetSize == .large ? 44 : 40, alignment: .trailing)
            }
        }
    }

    private var controlsRow: some View {
        HStack(spacing: widgetSize.controlsSpacing) {
            Button {
                musicManager.previousTrack()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: widgetSize.transportIconSize, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Button {
                musicManager.togglePlay()
            } label: {
                Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: widgetSize.playIconSize, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: widgetSize.playButtonSize, height: widgetSize.playButtonSize)
                    .liquidGlassControl(in: Circle(), fallback: .white.opacity(0.22))
            }
            .buttonStyle(.plain)

            Button {
                musicManager.nextTrack()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: widgetSize.transportIconSize, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        let minutes = total / 60
        let remaining = total % 60
        return String(format: "%d:%02d", minutes, remaining)
    }
}

// MARK: - Lockscreen Music Widget Window

final class LockscreenMusicWidgetWindow: NSWindow {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        canBecomeVisibleWithoutLogin = true
        level = .init(rawValue: .init(Int32.max - 2))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Lockscreen Music Widget Controller

@MainActor
final class LockscreenMusicWidgetController: ObservableObject {
    static let shared = LockscreenMusicWidgetController()

    private var window: LockscreenMusicWidgetWindow?
    private var isScreenLocked: Bool = false
    private var isSkyLightAttached: Bool = false
    private var cancellables = Set<AnyCancellable>()

    private init() {
        setupObservers()
    }

    private func setupObservers() {
        Publishers.MergeMany(
            MusicManager.shared.$isPlaying.map { _ in () }.eraseToAnyPublisher(),
            MusicManager.shared.$isPlayerIdle.map { _ in () }.eraseToAnyPublisher(),
            MusicManager.shared.$songTitle.map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.lockscreenMusicWidgetEnabled).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.lockscreenMusicWidgetSize).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.lockscreenMusicWidgetPosition).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.lockscreenMusicWidgetYOffset).map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.updateVisibility()
        }
        .store(in: &cancellables)

        let wsCenter = NSWorkspace.shared.notificationCenter
        wsCenter.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.onScreenLocked() }
        }
        wsCenter.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.onScreenUnlocked() }
        }
        wsCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.onScreenLocked() }
        }
        wsCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.onScreenUnlocked() }
        }

        let distCenter = DistributedNotificationCenter.default()
        distCenter.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.onScreenLocked() }
        }
        distCenter.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.onScreenUnlocked() }
        }
    }

    func onScreenLocked() {
        isScreenLocked = true
        updateVisibility()
    }

    func onScreenUnlocked() {
        isScreenLocked = false
        updateVisibility()
    }

    func updateVisibility() {
        let hasTrack = MusicManager.shared.isPlaying
            || !MusicManager.shared.isPlayerIdle
            || !MusicManager.shared.songTitle.isEmpty

        let shouldShow = isScreenLocked
            && Defaults[.lockscreenMusicWidgetEnabled]
            && hasTrack

        if shouldShow {
            showWidget()
        } else {
            hideWidget()
        }
    }

    // ponytail: single primary-screen lockscreen widget anchored above login controls; upgrade to NSScreen enumeration if multi-display widget requested.
    private func showWidget() {
        guard let screen = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main else { return }

        let dim = Defaults[.lockscreenMusicWidgetSize].dimensions
        let position = Defaults[.lockscreenMusicWidgetPosition]
        let yOffset = CGFloat(Defaults[.lockscreenMusicWidgetYOffset])
        let padding: CGFloat = 32

        let x: CGFloat
        switch position {
        case .leading:
            x = screen.frame.minX + padding
        case .center:
            x = screen.frame.midX - dim.width / 2
        case .trailing:
            x = screen.frame.maxX - dim.width - padding
        }
        let y = screen.frame.minY + yOffset

        let rect = NSRect(x: x, y: y, width: dim.width, height: dim.height)

        if window == nil {
            let newWindow = LockscreenMusicWidgetWindow(contentRect: rect)
            newWindow.contentView = NSHostingView(rootView: LockscreenMusicWidgetView())
            self.window = newWindow
        }

        guard let window = window else { return }
        window.setFrame(rect, display: true)

        if !isSkyLightAttached {
            SkyLightOperator.shared.delegateWindow(window)
            isSkyLightAttached = true
        }

        window.alphaValue = 1
        window.orderFrontRegardless()
    }

    private func hideWidget() {
        guard let window = window else { return }
        if isSkyLightAttached {
            SkyLightOperator.shared.undelegateWindow(window)
            isSkyLightAttached = false
        }
        window.orderOut(nil)
        self.window = nil
    }
}
