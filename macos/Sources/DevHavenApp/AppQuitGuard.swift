import AppKit
import Foundation
import SwiftUI

struct AppQuitGuardCopy: Equatable {
    let message: String

    static let `default` = Self(
        message: "再按一次 ⌘Q 退出 DevHaven"
    )
}

struct AppQuitGuardState: Equatable {
    var pendingConfirmationDeadline: Date?
    var toastMessage: String?
}

enum AppQuitGuardDecision: Equatable {
    case showToast(String)
    case terminate
}

struct AppQuitGuardStateMachine {
    let confirmationInterval: TimeInterval
    let copy: AppQuitGuardCopy

    init(
        confirmationInterval: TimeInterval = 1.5,
        copy: AppQuitGuardCopy = .default
    ) {
        self.confirmationInterval = confirmationInterval
        self.copy = copy
    }

    func handleQuitRequest(
        state: inout AppQuitGuardState,
        now: Date,
        hasVisibleWindow: Bool
    ) -> AppQuitGuardDecision {
        expireIfNeeded(state: &state, now: now)

        guard hasVisibleWindow else {
            state = AppQuitGuardState()
            return .terminate
        }

        if let deadline = state.pendingConfirmationDeadline,
           now <= deadline {
            state = AppQuitGuardState()
            return .terminate
        }

        let deadline = now.addingTimeInterval(confirmationInterval)
        state.pendingConfirmationDeadline = deadline
        state.toastMessage = copy.message
        return .showToast(copy.message)
    }

    func expireIfNeeded(state: inout AppQuitGuardState, now: Date) {
        guard let deadline = state.pendingConfirmationDeadline,
              now >= deadline
        else {
            return
        }
        state = AppQuitGuardState()
    }
}

@MainActor
final class AppQuitGuard: ObservableObject {
    @Published private(set) var toastMessage: String?

    private let stateMachine: AppQuitGuardStateMachine
    private let nowProvider: () -> Date
    private let visibleWindowProvider: () -> Bool
    private let terminateAction: () -> Void

    private var state = AppQuitGuardState()
    private var expireTask: Task<Void, Never>?

    init(
        stateMachine: AppQuitGuardStateMachine = AppQuitGuardStateMachine(),
        nowProvider: @escaping () -> Date = Date.init,
        visibleWindowProvider: @escaping () -> Bool = {
            NSApp.windows.contains(where: \.isVisible)
        },
        terminateAction: @escaping () -> Void = {
            NSApp.terminate(nil)
        }
    ) {
        self.stateMachine = stateMachine
        self.nowProvider = nowProvider
        self.visibleWindowProvider = visibleWindowProvider
        self.terminateAction = terminateAction
        self.toastMessage = nil
    }

    func requestQuit() {
        var nextState = state
        let decision = stateMachine.handleQuitRequest(
            state: &nextState,
            now: nowProvider(),
            hasVisibleWindow: visibleWindowProvider()
        )
        apply(nextState)

        switch decision {
        case .showToast:
            scheduleExpiryIfNeeded()
        case .terminate:
            expireTask?.cancel()
            expireTask = nil
            terminateAction()
        }
    }

    func expireIfNeeded() {
        var nextState = state
        stateMachine.expireIfNeeded(state: &nextState, now: nowProvider())
        apply(nextState)
    }

    private func apply(_ nextState: AppQuitGuardState) {
        state = nextState
        toastMessage = nextState.toastMessage
    }

    private func scheduleExpiryIfNeeded() {
        expireTask?.cancel()
        guard let deadline = state.pendingConfirmationDeadline else {
            return
        }
        let delay = max(0, deadline.timeIntervalSince(nowProvider()))
        expireTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await MainActor.run {
                guard let self else {
                    return
                }
                self.expireTask = nil
                self.expireIfNeeded()
            }
        }
    }

    deinit {
        expireTask?.cancel()
    }
}

struct AppQuitToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NativeTheme.warning)
            Text(message)
                .font(.callout.weight(.medium))
                .foregroundStyle(NativeTheme.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(NativeTheme.panel)
        .overlay(
            Capsule()
                .stroke(NativeTheme.border, lineWidth: 1)
        )
        .clipShape(.capsule)
        .shadow(color: .black.opacity(0.24), radius: 16, y: 10)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}
