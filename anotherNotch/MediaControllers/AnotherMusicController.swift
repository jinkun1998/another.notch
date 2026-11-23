//
//  AnotherMusicController.swift
//  anotherNotch
//
//  Created by Antigravity on 2026-11-23.
//

import AppKit
import Combine
import Foundation

@MainActor
final class AnotherMusicController: ObservableObject, MediaControllerProtocol {
    static let shared = AnotherMusicController()

    static let downloadURL = URL(string: "https://github.com/jinkun1998/another.Music/releases")!

    static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.jinkun1998.anothermusic") != nil
            || FileManager.default.fileExists(atPath: "/Applications/anotherMusic.app")
    }

    @Published private(set) var playbackState: PlaybackState = PlaybackState(
        bundleIdentifier: "com.jinkun1998.anothermusic"
    )

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var supportsVolumeControl: Bool { true }
    var supportsFavorite: Bool { true }

    private let commandNotification = NSNotification.Name("com.jinkun1998.anothermusic.command")
    private let stateNotification = NSNotification.Name("com.jinkun1998.anothermusic.playbackState")
    private var notificationObserver: AnyObject?
    private var appActivateObserver: AnyObject?
    private var appLaunchObserver: AnyObject?
    private var ownAppActivateObserver: AnyObject?
    private var artworkTask: Task<Void, Never>?
    private var lastArtworkUrl: String?

    init() {
        notificationObserver = DistributedNotificationCenter.default().addObserver(
            forName: stateNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor [weak self] in
                self?.handleStateNotification(note)
            }
        }

        appActivateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.bundleIdentifier == "com.jinkun1998.anothermusic" {
                Task { @MainActor [weak self] in
                    self?.sendCommand("requestState")
                }
            }
        }

        appLaunchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.bundleIdentifier == "com.jinkun1998.anothermusic" {
                Task { @MainActor [weak self] in
                    self?.sendCommand("requestState")
                }
            }
        }

        ownAppActivateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sendCommand("requestState")
            }
        }

        // Request initial playback state from anotherMusic on startup
        sendCommand("requestState")
    }

    deinit {
        if let observer = notificationObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        if let observer = appActivateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        if let observer = appLaunchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        if let observer = ownAppActivateObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        artworkTask?.cancel()
    }

    private func sendCommand(_ action: String, extra: [String: Any] = [:]) {
        var payload = extra
        payload["action"] = action
        DistributedNotificationCenter.default().postNotificationName(
            commandNotification,
            object: nil,
            userInfo: payload,
            deliverImmediately: true
        )
    }

    private func handleStateNotification(_ notification: Notification) {
        guard let info = notification.userInfo as? [String: Any] else { return }

        var state = playbackState
        state.bundleIdentifier = "com.jinkun1998.anothermusic"
        if let isPlaying = info["isPlaying"] as? Bool { state.isPlaying = isPlaying }
        if let title = info["title"] as? String { state.title = title }
        if let artist = info["artist"] as? String { state.artist = artist }
        if let album = info["album"] as? String { state.album = album }
        if let trackId = info["trackId"] as? String { state.trackId = trackId }
        if let duration = info["duration"] as? Double { state.duration = duration }
        if let pos = (info["position"] as? Double) ?? (info["currentTime"] as? Double) {
            state.currentTime = pos
        }
        if let playbackRate = info["playbackRate"] as? Double { state.playbackRate = playbackRate }
        if let volume = info["volume"] as? Double { state.volume = volume }
        if let isFav = info["isFavorite"] as? Bool { state.isFavorite = isFav }
        if let isShuffled = info["isShuffled"] as? Bool { state.isShuffled = isShuffled }
        if let repInt = info["repeatMode"] as? Int {
            state.repeatMode = RepeatMode(rawValue: repInt) ?? .off
        }
        if let transMode = info["transitionMode"] as? String {
            state.transitionMode = transMode
        }
        state.lastUpdated = Date()

        // Fetch artwork if URL updated
        if let artUrlStr = info["artworkUrl"] as? String, !artUrlStr.isEmpty {
            if artUrlStr != lastArtworkUrl {
                lastArtworkUrl = artUrlStr
                artworkTask?.cancel()
                artworkTask = Task { [weak self] in
                    guard let url = URL(string: artUrlStr),
                          let (data, _) = try? await URLSession.shared.data(from: url),
                          !Task.isCancelled else { return }
                    await MainActor.run {
                        self?.playbackState.artwork = data
                    }
                }
            }
        } else if info["artworkUrl"] == nil {
            state.artwork = nil
            lastArtworkUrl = nil
        }

        self.playbackState = state
    }

    // MARK: - MediaControllerProtocol Implementation
    func play() async {
        sendCommand("play")
    }

    func pause() async {
        sendCommand("pause")
    }

    func togglePlay() async {
        sendCommand("togglePlay")
    }

    func nextTrack() async {
        sendCommand("next")
    }

    func previousTrack() async {
        sendCommand("previous")
    }

    func seek(to time: Double) async {
        sendCommand("seek", extra: ["position": time])
    }

    func setVolume(_ level: Double) async {
        playbackState.volume = level
        sendCommand("setVolume", extra: ["volume": level])
    }

    func toggleLike() async {
        playbackState.isFavorite.toggle()
        sendCommand("toggleLike")
    }

    func setFavorite(_ favorite: Bool) async {
        playbackState.isFavorite = favorite
        sendCommand("setFavorite", extra: ["favorite": favorite])
    }

    func toggleFavorite() async {
        await toggleLike()
    }

    func toggleShuffle() async {
        playbackState.isShuffled.toggle()
        sendCommand("toggleShuffle")
    }

    func toggleRepeat() async {
        sendCommand("toggleRepeat")
    }

    func setTransitionMode(_ mode: String) async {
        playbackState.transitionMode = mode
        sendCommand("setTransitionMode", extra: ["mode": mode])
    }

    func cycleTransitionMode() async {
        sendCommand("cycleTransitionMode")
    }

    func isActive() -> Bool {
        return !NSRunningApplication.runningApplications(withBundleIdentifier: "com.jinkun1998.anothermusic").isEmpty
    }

    func updatePlaybackInfo() async {
        sendCommand("requestState")
    }
}
