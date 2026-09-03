import SwiftUI

struct NotchMotionPolicy {
    let reducesMotion: Bool

    init(reduceMotion: Bool) {
        reducesMotion = reduceMotion
    }

    var openResponse: TimeInterval {
        reducesMotion ? 0.18 : 0.42
    }

    var openDampingFraction: CGFloat {
        reducesMotion ? 1 : 0.80
    }

    var closeDuration: TimeInterval {
        reducesMotion ? 0.18 : 0.30
    }

    var expandedContentRevealDelay: TimeInterval {
        reducesMotion ? 0 : 0.08
    }

    var expandedContentRevealDuration: TimeInterval {
        reducesMotion ? 0.14 : 0.22
    }

    var expandedContentHideDuration: TimeInterval {
        reducesMotion ? 0.10 : 0.12
    }

    var openShellAnimation: Animation {
        reducesMotion
            ? .easeOut(duration: openResponse)
            : .spring(response: openResponse, dampingFraction: openDampingFraction)
    }

    var closeShellAnimation: Animation {
        reducesMotion
            ? .easeOut(duration: closeDuration)
            : .smooth(duration: closeDuration)
    }

    var expandedContentRevealAnimation: Animation {
        .easeOut(duration: expandedContentRevealDuration)
    }

    var expandedContentHideAnimation: Animation {
        .easeOut(duration: expandedContentHideDuration)
    }

    var hudAnimation: Animation {
        .easeOut(duration: reducesMotion ? 0.12 : 0.18)
    }

    var hudTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: reducesMotion ? 0.98 : 0.96))
    }
}
