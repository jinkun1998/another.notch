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
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .default)
    }
}
