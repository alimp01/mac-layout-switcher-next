#if os(macOS)
import AppKit
import CoreGraphics

/// Authority for a bounded, freshly observed keyboard stream. This is NOT an
/// AX target or a claim that the editor accepted our events. Main-thread input
/// invalidates its permit; posting/replay state is confined to Typist's queue.
final class TrackedInputBatch {
    let permit: InputFocusGuard.Permit
    let replacementPermit = InputFocusGuard.Permit()
    private let applicationPID: pid_t
    private(set) var uncertain = false

    init(permit: InputFocusGuard.Permit, applicationPID: pid_t) {
        self.permit = permit
        self.applicationPID = applicationPID
    }

    var canReplay: Bool {
        permit.isAllowed && !uncertain && !SecureInput.isActive
            && NSWorkspace.shared.frontmostApplication?.processIdentifier == applicationPID
    }
    var canReplace: Bool { replacementPermit.isAllowed && canReplay }
    static var modifiersReleased: Bool {
        CGEventSource.flagsState(.combinedSessionState)
            .intersection([.maskShift, .maskAlternate, .maskCommand, .maskControl]).isEmpty
    }
    func reject(interrupted: Bool) {
        replacementPermit.cancel()
        uncertain = uncertain || interrupted
    }
}
#endif
