//
//  MusicControlButton.swift
//  anotherNotch
//
//  Created by Alexander on 2025-11-16.
//

import Defaults

enum MusicControlButton: String, CaseIterable, Identifiable, Codable, Defaults.Serializable {
    case shuffle
    case previous
    case playPause
    case next
    case repeatMode
    case volume
    case airPlay
    case favorite
    case goBackward
    case goForward
    case none

    var id: String { rawValue }

    static let legacyDefaultLayout: [MusicControlButton] = [
        .none,
        .previous,
        .playPause,
        .next,
        .none
    ]

    static let defaultLayout: [MusicControlButton] = [
        .none,
        .goBackward,
        .playPause,
        .goForward,
        .airPlay
    ]

    static let preAirPlayDefaultLayout: [MusicControlButton] = [
        .shuffle,
        .previous,
        .playPause,
        .next,
        .favorite
    ]

    static let minSlotCount: Int = 3
    static let maxSlotCount: Int = 5

    static let pickerOptions: [MusicControlButton] = [
        .shuffle,
        .previous,
        .playPause,
        .next,
        .repeatMode,
        .favorite,
        .volume,
        .airPlay,
        .goBackward,
        .goForward
    ]

    var label: String {
        switch self {
        case .shuffle:
            return "Shuffle"
        case .previous:
            return "Previous"
        case .playPause:
            return "Play/Pause"
        case .next:
            return "Next"
        case .repeatMode:
            return "Repeat"
        case .volume:
            return "Volume"
        case .airPlay:
            return "AirPlay"
        case .favorite:
            return "Favorite"
        case .goBackward:
            return "Backward 10s"
        case .goForward:
            return "Forward 10s"
        case .none:
            return "Empty slot"
        }
    }

    var iconName: String {
        switch self {
        case .shuffle:
            return "shuffle"
        case .previous:
            return "backward.fill"
        case .playPause:
            return "playpause"
        case .next:
            return "forward.fill"
        case .repeatMode:
            return "repeat"
        case .volume:
            return "speaker.wave.2.fill"
        case .airPlay:
            return "airplayaudio"
        case .favorite:
            return "heart"
        case .goBackward:
            return "gobackward.10"
        case .goForward:
            return "goforward.10"
        case .none:
            return ""
        }
    }

    var prefersLargeScale: Bool {
        self == .playPause
    }
}
