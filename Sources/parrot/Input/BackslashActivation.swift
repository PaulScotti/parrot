import Foundation

/// Interprets physical Backslash edges as either push-to-talk or a latched
/// hands-free recording. Time is passed in so every ambiguous edge can be
/// tested without sleeping or synthesizing system keyboard events.
struct BackslashActivation {
    enum State: Equatable {
        case idle
        case firstPress
        case waitingForSecondTap
        case secondPress
        case handsFree
        case handsFreeStopPress
    }

    enum Action: Equatable {
        case startRecording
        case stopRecording
        case handsFreeStarted
    }

    private(set) var state = State.idle
    private var pressStartedAt: TimeInterval = 0
    private var firstTapReleasedAt: TimeInterval = 0
    private let maximumTapDuration: TimeInterval
    private let doubleTapWindow: TimeInterval

    init(
        maximumTapDuration: TimeInterval = 0.25,
        doubleTapWindow: TimeInterval = 0.40
    ) {
        self.maximumTapDuration = maximumTapDuration
        self.doubleTapWindow = doubleTapWindow
    }

    mutating func handle(pressed: Bool, at time: TimeInterval) -> Action? {
        switch state {
        case .idle:
            guard pressed else { return nil }
            pressStartedAt = time
            state = .firstPress
            return .startRecording

        case .firstPress:
            guard !pressed else { return nil }
            if isQuickTap(at: time) {
                firstTapReleasedAt = time
                state = .waitingForSecondTap
                return nil
            }
            state = .idle
            return .stopRecording

        case .waitingForSecondTap:
            guard pressed else { return nil }
            guard time - firstTapReleasedAt <= doubleTapWindow else {
                state = .idle
                return .stopRecording
            }
            pressStartedAt = time
            state = .secondPress
            return nil

        case .secondPress:
            guard !pressed else { return nil }
            if isQuickTap(at: time) {
                state = .handsFree
                return .handsFreeStarted
            }
            state = .idle
            return .stopRecording

        case .handsFree:
            guard pressed else { return nil }
            state = .handsFreeStopPress
            return .stopRecording

        case .handsFreeStopPress:
            guard !pressed else { return nil }
            state = .idle
            return nil
        }
    }

    mutating func singleTapTimedOut() -> Action? {
        guard state == .waitingForSecondTap else { return nil }
        state = .idle
        return .stopRecording
    }

    mutating func reset() {
        state = .idle
        pressStartedAt = 0
        firstTapReleasedAt = 0
    }

    private func isQuickTap(at time: TimeInterval) -> Bool {
        time - pressStartedAt <= maximumTapDuration
    }
}
