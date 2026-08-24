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
        .favorite,
        .previous,
        .playPause,
        .next,
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

    static let customizableSlotIndexes = [0, 1, 3]

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

    static let customizableOptions = pickerOptions.filter {
        $0 != .playPause && $0 != .airPlay
    }

    static func normalizedLayout(_ layout: [MusicControlButton]) -> [MusicControlButton] {
        var normalized = defaultLayout
        var used: Set<MusicControlButton> = []
        var acceptedIndexes: Set<Int> = []

        for index in customizableSlotIndexes {
            guard layout.indices.contains(index) else { continue }
            let control = layout[index]
            guard customizableOptions.contains(control), used.insert(control).inserted else { continue }
            normalized[index] = control
            acceptedIndexes.insert(index)
        }

        for index in customizableSlotIndexes where !acceptedIndexes.contains(index) {
            let preferred = defaultLayout[index]
            let replacement = !used.contains(preferred) ? preferred : customizableOptions.first { !used.contains($0) }
            guard let replacement else { continue }
            normalized[index] = replacement
            used.insert(replacement)
        }

        return normalized
    }

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
            return "Audio Source"
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
