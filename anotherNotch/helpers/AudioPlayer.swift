//
//  AudioPlayer.swift
//  anotherNotch
//
//  Created by Harsh Vardhan  Goswami  on 09/08/24.
//

import AppKit
import Defaults
import Foundation

class AudioPlayer {
    func play(fileName: String, fileExtension: String) {
        NSSound(contentsOf:Bundle.main.url(forResource: fileName, withExtension: fileExtension)!, byReference: false)?.play()
    }
}

enum HapticFeedback {
    static func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern = .generic) {
        guard Defaults[.enableHaptics] else { return }
        perform(pattern: pattern, level: Defaults[.hapticFeedbackLevel])
    }

    static func perform(for level: HapticFeedbackLevel) {
        perform(pattern: .generic, level: level)
    }

    private static func perform(pattern: NSHapticFeedbackManager.FeedbackPattern, level: HapticFeedbackLevel) {
        let performer = NSHapticFeedbackManager.defaultPerformer
        switch level {
        case .light:
            performer.perform(.alignment, performanceTime: .default)
        case .medium:
            performer.perform(pattern, performanceTime: .default)
        case .strong:
            performer.perform(.levelChange, performanceTime: .default)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.045) {
                performer.perform(.levelChange, performanceTime: .default)
            }
        }
    }
}
