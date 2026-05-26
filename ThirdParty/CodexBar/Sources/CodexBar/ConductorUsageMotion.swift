import SwiftUI

enum ConductorUsageMotion {
    enum Timing {
        static let tap: Double = 0.08
        static let hover: Double = 0.11
        static let feedback: Double = 0.09
        static let selection: Double = 0.17
        static let contentSwap: Double = 0.18
        static let panel: Double = 0.21
    }

    static var press: Animation {
        .easeOut(duration: Timing.tap)
    }

    static var hover: Animation {
        .easeOut(duration: Timing.hover)
    }

    static var feedback: Animation {
        .easeOut(duration: Timing.feedback)
    }

    static var selection: Animation {
        .smooth(duration: Timing.selection, extraBounce: 0.004)
    }

    static var contentSwap: Animation {
        .timingCurve(0.22, 1.0, 0.36, 1.0, duration: Timing.contentSwap)
    }

    static var panel: Animation {
        .timingCurve(0.16, 1.0, 0.30, 1.0, duration: Timing.panel)
    }

    static func perform(
        _ animation: Animation = selection,
        reduceMotion: Bool = false,
        _ action: () -> Void)
    {
        if reduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction, action)
        } else {
            withAnimation(animation, action)
        }
    }
}
