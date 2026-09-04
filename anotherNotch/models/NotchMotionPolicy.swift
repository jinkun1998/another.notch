import Defaults
import SwiftUI

enum NotchMotionStyle: String, CaseIterable, Codable, Defaults.Serializable {
    case polished = "Polished"
    case spring = "Spring"
    case minimal = "Minimal"
}

enum NotchShellAnimation: Equatable {
    case easeOut(duration: TimeInterval)
    case smooth(duration: TimeInterval)
    case spring(response: TimeInterval, dampingFraction: CGFloat)

    var duration: TimeInterval {
        switch self {
        case let .easeOut(duration), let .smooth(duration): duration
        case let .spring(response, _): response
        }
    }

    var dampingFraction: CGFloat {
        switch self {
        case let .spring(_, dampingFraction): dampingFraction
        case .easeOut, .smooth: 1
        }
    }

    var animation: Animation {
        switch self {
        case let .easeOut(duration): .easeOut(duration: duration)
        case let .smooth(duration): .smooth(duration: duration)
        case let .spring(response, dampingFraction):
            .spring(response: response, dampingFraction: dampingFraction)
        }
    }
}

enum ContinuousAnimationPolicy {
    static func updateInterval(
        isActive: Bool,
        reducesMotion: Bool,
        activeInterval: TimeInterval
    ) -> TimeInterval? {
        isActive && !reducesMotion ? activeInterval : nil
    }
}

struct NotchMotionPolicy {
    let reducesMotion: Bool
    let style: NotchMotionStyle

    init(reduceMotion: Bool, style: NotchMotionStyle = .polished) {
        reducesMotion = reduceMotion
        self.style = style
    }

    var openResponse: TimeInterval {
        openShell.duration
    }

    var openDampingFraction: CGFloat {
        openShell.dampingFraction
    }

    var closeDuration: TimeInterval {
        closeShell.duration
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
        openShell.animation
    }

    var closeShellAnimation: Animation {
        closeShell.animation
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

    var openShell: NotchShellAnimation {
        if reducesMotion || style == .minimal {
            return .easeOut(duration: 0.18)
        }

        return .spring(
            response: 0.42,
            dampingFraction: style == .spring ? 1 : 0.80
        )
    }

    var closeShell: NotchShellAnimation {
        if reducesMotion || style == .minimal {
            return .easeOut(duration: 0.18)
        }

        return style == .spring
            ? .spring(response: 0.45, dampingFraction: 1)
            : .smooth(duration: 0.30)
    }
}
