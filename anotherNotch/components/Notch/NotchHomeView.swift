//
//  NotchHomeView.swift
//  anotherNotch
//
//  Created by Hugo Persson on 2024-08-18.
//  Modified by Harsh Vardhan Goswami & Richard Kunkli & Mustafa Ramadan
//

import Combine
import Defaults
import AppKit
import SwiftUI

// MARK: - Music Player Components

struct MusicPlayerView: View {
    @EnvironmentObject var vm: AnotherNotchViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let albumArtNamespace: Namespace.ID
    let isHeroTransitionActive: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            AlbumArtView(albumArtNamespace: albumArtNamespace)
                .frame(width: 100, height: 100)
                .conditionalModifier(isHeroTransitionActive) { view in
                    view
                        .matchedGeometryEffect(
                            id: "albumArt",
                            in: albumArtNamespace,
                            properties: .frame,
                            anchor: .center
                        )
                        .animation(
                            reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.42, dampingFraction: 0.82),
                            value: vm.notchState
                        )
                }
                .zIndex(3)
            MusicControlsView(
                albumArtNamespace: albumArtNamespace,
                isHeroTransitionActive: isHeroTransitionActive
            )
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct AlbumArtView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @Default(.rotateAlbumArt) private var rotateAlbumArt
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let albumArtNamespace: Namespace.ID

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if Defaults[.lightingEffect] {
                albumArtBackground
            }
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !shouldRotate)) { timeline in
                albumArtButton(rotation: rotation(at: timeline.date))
            }
        }
    }

    private var albumArtBackground: some View {
        Image(nsImage: musicManager.albumArt)
            .resizable()
            .clipped()
            .clipShape(Circle())
            .aspectRatio(1, contentMode: .fit)
            .scaleEffect(x: 1.3, y: 1.4)
            .rotationEffect(.degrees(92))
            .blur(radius: 40)
            .opacity(musicManager.isPlaying ? 0.5 : 0)
    }

    private var shouldRotate: Bool {
        rotateAlbumArt && musicManager.isPlaying && !reduceMotion
    }

    private func rotation(at date: Date) -> Double {
        guard shouldRotate else { return 0 }
        return date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: 8) / 8 * 360
    }

    private func albumArtButton(rotation: Double) -> some View {
        Button {
            musicManager.openMusicApp()
        } label: {
            albumArtImage
        }
        .buttonStyle(.plain)
        .scaleEffect(musicManager.isPlaying ? 1 : 0.85)
        .rotationEffect(.degrees(rotation))
    }
                

    private var albumArtImage: some View {
        Image(nsImage: musicManager.albumArt)
            .resizable()
            .aspectRatio(1, contentMode: .fit)
            .clipped()
            .clipShape(Circle())
    }

}

struct MusicControlsView: View {
    @EnvironmentObject var vm: AnotherNotchViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var musicManager = MusicManager.shared
    let albumArtNamespace: Namespace.ID
    @State private var sliderValue: Double = 0
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast
    @Default(.musicControlSlots) private var slotConfig
    @Default(.useMusicVisualizer) private var useMusicVisualizer
    let isHeroTransitionActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            songInfoAndSlider
            slotToolbar
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var songInfoAndSlider: some View {
        VStack(alignment: .leading, spacing: 4) {
            songInfo
            musicSlider
        }
    }

    private var songInfo: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    MarqueeText(
                        $musicManager.songTitle,
                        font: .headline,
                        nsFont: .headline,
                        textColor: .white,
                        frameWidth: 320
                    )
                    MarqueeText(
                        $musicManager.artistName,
                        font: .subheadline,
                        nsFont: .subheadline,
                        textColor: Defaults[.playerColorTinting]
                            ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6)
                            : .gray,
                        frameWidth: 320
                    )
                    .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {}
                if useMusicVisualizer {
                    DynamicIslandWaveform(isPlaying: musicManager.isPlaying)
                        .frame(width: 28, height: 18)
                        .conditionalModifier(isHeroTransitionActive) { view in
                            view
                                .matchedGeometryEffect(
                                    id: "spectrum",
                                    in: albumArtNamespace,
                                    properties: .frame,
                                    anchor: .center
                                )
                                .animation(
                                    reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.42, dampingFraction: 0.82),
                                    value: vm.notchState
                                )
                        }
                        .padding(.leading, 10)
                }
            }
            if Defaults[.enableLyrics] {
                TimelineView(.animation(minimumInterval: 0.25)) { timeline in
                    let currentElapsed: Double = {
                        guard musicManager.isPlaying else { return musicManager.elapsedTime }
                        let delta = timeline.date.timeIntervalSince(musicManager.timestampDate)
                        let progressed = musicManager.elapsedTime + (delta * musicManager.playbackRate)
                        return min(max(progressed, 0), musicManager.songDuration)
                    }()
                    let line: String = {
                        if musicManager.isFetchingLyrics { return "Loading lyrics…" }
                        if !musicManager.syncedLyrics.isEmpty {
                            return musicManager.lyricLine(at: currentElapsed)
                        }
                        let trimmed = musicManager.currentLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
                        return trimmed.isEmpty ? "No lyrics found" : trimmed.replacingOccurrences(of: "\n", with: " ")
                    }()
                    let isPersian = line.unicodeScalars.contains { scalar in
                        let v = scalar.value
                        return v >= 0x0600 && v <= 0x06FF
                    }
                    MarqueeText(
                        .constant(line),
                        font: .subheadline,
                        nsFont: .subheadline,
                        textColor: musicManager.isFetchingLyrics ? .gray.opacity(0.7) : .gray,
                        frameWidth: 400
                    )
                    .font(isPersian ? .custom("Vazirmatn-Regular", size: NSFont.preferredFont(forTextStyle: .subheadline).pointSize) : .subheadline)
                    .lineLimit(1)
                    .opacity(musicManager.isPlaying ? 1 : 0)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var musicSlider: some View {
        TimelineView(.animation(minimumInterval: musicManager.playbackRate > 0 ? 0.1 : nil)) { timeline in
            MusicSliderView(
                sliderValue: $sliderValue,
                duration: $musicManager.songDuration,
                lastDragged: $lastDragged,
                color: musicManager.avgColor,
                dragging: $dragging,
                currentDate: timeline.date,
                timestampDate: musicManager.timestampDate,
                elapsedTime: musicManager.elapsedTime,
                playbackRate: musicManager.playbackRate,
                isPlaying: musicManager.isPlaying,
                isEnabled: canSeek
            ) { newValue in
                MusicManager.shared.seek(to: newValue)
            }
            .frame(height: 16)
        }
    }

    private var slotToolbar: some View {
        let slots = activeSlots.filter { $0 != .none }
        return HStack(spacing: 0) {
            ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                slotView(for: slot)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 52)
    }

    private var activeSlots: [MusicControlButton] {
        Array(slotConfig.padded(to: MusicControlButton.maxSlotCount, filler: .none).prefix(MusicControlButton.maxSlotCount))
    }

    private var canSeek: Bool {
        musicManager.bundleIdentifier != nil && musicManager.songDuration.isFinite && musicManager.songDuration > 0
    }

    @ViewBuilder
    private func slotView(for slot: MusicControlButton) -> some View {
        switch slot {
        case .shuffle:
            DynamicIslandMusicButton(
                icon: "shuffle",
                tint: musicManager.isShuffled ? .white : .gray
            ) {
                MusicManager.shared.toggleShuffle()
            }
        case .previous:
            DynamicIslandMusicButton(icon: "backward.fill") {
                MusicManager.shared.previousTrack()
            }
        case .playPause:
            DynamicIslandMusicButton(
                icon: musicManager.isPlaying ? "pause.fill" : "play.fill",
                isPrimary: true
            ) {
                MusicManager.shared.togglePlay()
            }
        case .next:
            DynamicIslandMusicButton(icon: "forward.fill") {
                MusicManager.shared.nextTrack()
            }
        case .repeatMode:
            DynamicIslandMusicButton(icon: repeatIcon, tint: repeatIconColor) {
                MusicManager.shared.toggleRepeat()
            }
        case .volume:
            VolumeControlView()
        case .airPlay:
            OutputDeviceSelectorButton {
                OutputDeviceIcon()
                    .font(.system(size: 22, weight: .bold))
                    .contentTransition(.symbolEffect)
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
            }
        case .favorite:
            FavoriteControlButton()
        case .goBackward:
            DynamicIslandMusicButton(icon: "gobackward.10") {
                MusicManager.shared.skip(seconds: -10)
            }
            .disabled(!canSeek)
            .opacity(canSeek ? 1 : 0.35)
        case .goForward:
            DynamicIslandMusicButton(icon: "goforward.10") {
                MusicManager.shared.skip(seconds: 10)
            }
            .disabled(!canSeek)
            .opacity(canSeek ? 1 : 0.35)
        case .none:
            Color.clear.frame(width: 40, height: 40)
        }
    }

    private var repeatIcon: String {
        switch musicManager.repeatMode {
        case .off:
            return "repeat"
        case .all:
            return "repeat"
        case .one:
            return "repeat.1"
        }
    }

    private var repeatIconColor: Color {
        switch musicManager.repeatMode {
        case .off:
            return .primary
        case .all, .one:
            return .red
        }
    }

}

struct DynamicIslandWaveform: View {
    @ObservedObject private var musicManager = MusicManager.shared
    @Default(.waveformMatchesAlbumArt) private var waveformMatchesAlbumArt
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isPlaying: Bool

    private let heights: [CGFloat] = [0.45, 0.8, 1, 0.65, 0.35]

    private var colors: [Color] {
        guard waveformMatchesAlbumArt else { return [.purple, .pink] }

        let albumColor = Color(nsColor: musicManager.avgColor)
        return [
            albumColor.ensureMinimumBrightness(factor: 0.8),
            albumColor.ensureMinimumBrightness(factor: 0.35)
        ]
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: isPlaying && !reduceMotion ? 1 / 30 : nil)) { timeline in
            HStack(spacing: 2) {
                ForEach(heights.indices, id: \.self) { index in
                    Capsule()
                        .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                        .frame(width: 2, height: 18 * heights[index])
                        .scaleEffect(y: level(for: index, at: timeline.date), anchor: .center)
                }
            }
        }
        .onChange(of: waveformMatchesAlbumArt) { _, matchesAlbumArt in
            if matchesAlbumArt {
                musicManager.calculateAverageColor()
            }
        }
    }

    private func level(for index: Int, at date: Date) -> CGFloat {
        guard isPlaying else { return 0.45 }
        guard !reduceMotion else { return 0.65 }

        let phase = date.timeIntervalSinceReferenceDate * 5 + Double(index) * 0.9
        return 0.55 + CGFloat((sin(phase) + 1) / 2) * 0.45
    }
}

private struct DynamicIslandMusicButton: View {
    let icon: String
    var tint: Color = .white
    var isPrimary = false
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: isPrimary ? 32 : 22, weight: .bold))
                .contentTransition(.symbolEffect)
                .foregroundStyle(tint.opacity(isHovering ? 1 : isPrimary ? 1 : 0.82))
                .frame(width: isPrimary ? 52 : 40, height: isPrimary ? 52 : 40)
                .contentShape(Circle())
                .scaleEffect(!reduceMotion && isHovering ? 1.08 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: icon)
    }
}

struct FavoriteControlButton: View {
    @ObservedObject var musicManager = MusicManager.shared

    var body: some View {
        DynamicIslandMusicButton(icon: iconName, tint: iconColor) {
            MusicManager.shared.toggleFavoriteTrack()
        }
        .disabled(!musicManager.canFavoriteTrack)
        .opacity(musicManager.canFavoriteTrack ? 1 : 0.35)
    }

    private var iconName: String {
        musicManager.isFavoriteTrack ? "heart.fill" : "heart"
    }

    private var iconColor: Color {
        musicManager.isFavoriteTrack ? .white : .gray
    }
}

private extension Array where Element == MusicControlButton {
    func padded(to length: Int, filler: MusicControlButton) -> [MusicControlButton] {
        if count >= length { return self }
        return self + Array(repeating: filler, count: length - count)
    }
}

// MARK: - Volume Control View

struct VolumeControlView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @State private var volumeSliderValue: Double = 0.5
    @State private var dragging: Bool = false
    @State private var showVolumeSlider: Bool = false
    @State private var lastVolumeUpdateTime: Date = Date.distantPast
    private let volumeUpdateThrottle: TimeInterval = 0.1
    
    var body: some View {
        HStack(spacing: 4) {
            Button(action: {
                if musicManager.volumeControlSupported {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        showVolumeSlider.toggle()
                    }
                }
            }) {
                Image(systemName: volumeIcon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(musicManager.volumeControlSupported ? .white : .gray)
                    .frame(width: 30, height: 30)
                    .liquidGlassControl(in: Capsule(), fallback: .black.opacity(0.45))
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!musicManager.volumeControlSupported)

            if showVolumeSlider && musicManager.volumeControlSupported {
                CustomSlider(
                    value: $volumeSliderValue,
                    range: 0.0...1.0,
                    color: .white,
                    dragging: $dragging,
                    lastDragged: .constant(Date.distantPast),
                    isEnabled: true,
                    onValueChange: { newValue in
                        MusicManager.shared.setVolume(to: newValue)
                    },
                    onDragChange: { newValue in
                        let now = Date()
                        if now.timeIntervalSince(lastVolumeUpdateTime) > volumeUpdateThrottle {
                            MusicManager.shared.setVolume(to: newValue)
                            lastVolumeUpdateTime = now
                        }
                    }
                )
                .frame(width: 48, height: 8)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .clipped()
        .onReceive(musicManager.$volume) { volume in
            if !dragging {
                volumeSliderValue = volume
            }
        }
        .onReceive(musicManager.$volumeControlSupported) { supported in
            if !supported {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showVolumeSlider = false
                }
            }
        }
        .onChange(of: showVolumeSlider) { _, isShowing in
            if isShowing {
                // Sync volume from app when slider appears
                Task {
                    await MusicManager.shared.syncVolumeFromActiveApp()
                }
            }
        }
        .onDisappear {
            // volumeUpdateTask?.cancel() // No longer needed
        }
    }
    
    
    private var volumeIcon: String {
        if !musicManager.volumeControlSupported {
            return "speaker.slash"
        } else if volumeSliderValue == 0 {
            return "speaker.slash.fill"
        } else if volumeSliderValue < 0.33 {
            return "speaker.1.fill"
        } else if volumeSliderValue < 0.66 {
            return "speaker.2.fill"
        } else {
            return "speaker.3.fill"
        }
    }
}

// MARK: - Main View

struct NotchHomeView: View {
    @ObservedObject var coordinator = AnotherNotchViewCoordinator.shared
    let albumArtNamespace: Namespace.ID
    let isHeroTransitionActive: Bool

    var body: some View {
        Group {
            if !coordinator.firstLaunch {
                mainContent
            }
        }
    }

    private var mainContent: some View {
        MusicPlayerView(
            albumArtNamespace: albumArtNamespace,
            isHeroTransitionActive: isHeroTransitionActive
        )
    }
}

struct MusicSliderView: View {
    @Binding var sliderValue: Double
    @Binding var duration: Double
    @Binding var lastDragged: Date
    var color: NSColor
    @Binding var dragging: Bool
    let currentDate: Date
    let timestampDate: Date
    let elapsedTime: Double
    let playbackRate: Double
    let isPlaying: Bool
    let isEnabled: Bool
    var onValueChange: (Double) -> Void


    var body: some View {
        HStack(spacing: 10) {
            Text(timeString(from: sliderValue))
                .frame(width: 34, alignment: .leading)
            CustomSlider(
                value: $sliderValue,
                range: 0...max(0, duration),
                color: .white.opacity(0.85),
                dragging: $dragging,
                lastDragged: $lastDragged,
                isEnabled: isEnabled,
                onValueChange: onValueChange
            )
            .frame(height: 8, alignment: .center)
            Text("-\(timeString(from: max(0, duration - sliderValue)))")
                .frame(width: 40, alignment: .trailing)
        }
        .fontWeight(.medium)
        .foregroundColor(.gray)
        .font(.caption)
        .onChange(of: currentDate) {
            guard isEnabled, !dragging, timestampDate.timeIntervalSince(lastDragged) > -1 else { return }
            sliderValue = MusicManager.shared.estimatedPlaybackPosition(at: currentDate)
        }
    }

    func timeString(from seconds: Double) -> String {
        let totalMinutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        } else {
            return String(format: "%d:%02d", minutes, remainingSeconds)
        }
    }
}

struct CustomSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var color: Color = .white
    @Binding var dragging: Bool
    @Binding var lastDragged: Date
    let isEnabled: Bool
    var onValueChange: ((Double) -> Void)?
    var onDragChange: ((Double) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = CGFloat(dragging && isEnabled ? 6 : 4)
            let rangeSpan = range.upperBound - range.lowerBound

            let progress = rangeSpan == .zero ? 0 : (value - range.lowerBound) / rangeSpan
            let filledTrackWidth = min(max(progress, 0), 1) * width

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.white.opacity(0.18))
                    .frame(height: height)

                Rectangle()
                    .fill(color)
                    .frame(width: filledTrackWidth, height: height)

                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .offset(x: min(max(filledTrackWidth - 4, 0), max(width - 8, 0)))
            }
            .cornerRadius(height / 2)
            .frame(height: 12)
            .contentShape(Rectangle())
            .allowsHitTesting(isEnabled)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard width > 0 else { return }
                        withAnimation {
                            dragging = true
                        }
                        let newValue = range.lowerBound + Double(gesture.location.x / width) * rangeSpan
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                        onDragChange?(value)
                    }
                    .onEnded { _ in
                        onValueChange?(value)
                        dragging = false
                        lastDragged = Date()
                    }
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: dragging)
        }
    }
}
