#if os(macOS)
import ApplicationServices
import AppKit
import Foundation
import SwitcherCore

/// AX work is restricted to the sampling queue and Typist, never EventTap.
/// The cache only licenses a target identity: deletion still requires a fresh
/// empty selection and an exact source-text match at execution time.
final class InputFocusGuard {
    final class Permit {
        private let lock = NSLock()
        private var allowed = true
        func cancel() { lock.lock(); allowed = false; lock.unlock() }
        var isAllowed: Bool { lock.lock(); defer { lock.unlock() }; return allowed }
    }

    enum ReplacementResult: Equatable {
        case confirmed, untouched, uncertain, unconfirmedSelection
        var isUncertain: Bool { self == .uncertain || self == .unconfirmedSelection }
    }

    enum CaptureFailure {
        case accessibilityDenied, protectedField, secureInput, unavailableField, unavailableSelection
        case unavailableText, unreadableSelection, selectionTooLarge, changed, unavailableApplication
        case systemFocus(DictationFocusFailure)
        case preparingAccessibility(DictationFocusFailure?)
        var message: String {
            switch self {
            case .accessibilityDenied:
                return "У Mac Layout Switcher нет разрешения «Универсальный доступ». Проверьте его в настройках macOS; после обновления может потребоваться повторное включение."
            case .protectedField, .secureInput: return "Включён защищённый ввод или выбрано защищённое поле."
            case .unavailableField: return "Редактор не предоставил доступное поле ввода."
            case .unavailableApplication: return "macOS не сообщила активное приложение. Выберите нужное поле и повторите действие."
            case .systemFocus(let failure): return failure.message
            case .preparingAccessibility(let focus):
                return "Редактор подготавливает доступ к полю. Повторите действие через несколько секунд."
                    + (focus.map { " Диагностика: \($0.metadata)." } ?? "")
            case .unavailableSelection: return "Редактор не сообщил положение курсора или выделение."
            case .unavailableText: return "Редактор не предоставил текст для проверки замены."
            case .unreadableSelection: return "Редактор не предоставил текст выделения для проверки замены."
            case .selectionTooLarge: return "Выделение слишком большое. Выберите меньший фрагмент текста."
            case .changed: return "Во время захвата изменилось поле, текст или положение курсора. Повторите Option в нужном поле."
            }
        }
    }

    struct Target {
        let element: AXUIElement
        let pid: pid_t
        var accessibility: any DictationAccessibility = SystemDictationAccessibility()
        var processStart: SpotlightProcessStart? = nil

        /// Runs on a worker. Reuse the speech adapter's bounded AX bootstrap and
        /// process routing; querying the current element itself never bootstraps.
        static func capture(expectedPID: pid_t? = NSWorkspace.shared.frontmostApplication?.processIdentifier,
                            accessibility: any DictationAccessibility = SystemDictationAccessibility(),
                            allowed: () -> Bool = { true },
                            preparingOnly: Bool = false,
                            failure: (CaptureFailure) -> Void = { _ in }) -> Target? {
            func failed(_ reason: CaptureFailure) -> Target? { failure(reason); return nil }
            guard accessibility.isTrusted else { return failed(.accessibilityDenied) }
            guard !accessibility.isSecure else { return failed(.secureInput) }
            guard let pid = expectedPID else { return failed(.unavailableApplication) }
            guard allowed() else { return failed(.changed) }
            var bootstrap: DictationAXBootstrap?
            var firstElement: AXUIElement?
            var reason = CaptureFailure.unavailableField
            for attempt in 0..<3 {
                if attempt > 0 {
                    if attempt == 1 {
                        bootstrap = accessibility.prepareAccessibility(pid: pid, allowed: allowed)
                        if bootstrap?.rejectsCapture == true { return failed(.changed) }
                        if bootstrap?.requiresFreshFocus == true && firstElement == nil && !preparingOnly {
                            guard allowed() else { return failed(.changed) }
                            if case .systemFocus(let focus) = reason { return failed(.preparingAccessibility(focus.including(bootstrap))) }
                            return failed(.preparingAccessibility(nil))
                        }
                    }
                    guard bootstrap?.wait(before: attempt, allowed: allowed) != false else { return failed(.changed) }
                }
                guard allowed() else { return failed(.changed) }
                guard accessibility.isTrusted else { return failed(.accessibilityDenied) }
                guard !accessibility.isSecure else { return failed(.secureInput) }
                var stop = false
                let reportFailure: (DictationFocusFailure) -> Void = {
                    reason = .systemFocus($0.including(bootstrap)); stop = $0.preventsBootstrap
                }
                let focus = attempt == 0
                    ? accessibility.captureFocus(pid: pid, failure: reportFailure)
                    : accessibility.focusedElement(pid: pid, failure: reportFailure).map { DictationFocus(element: $0, pid: pid) }
                guard let focus else { if stop { return failed(reason) }; continue }
                let element = focus.element
                guard accessibility.attribute(kAXSubroleAttribute, of: element) as? String != kAXSecureTextFieldSubrole
                    else { return failed(.protectedField) }
                if let firstElement, !CFEqual(firstElement, element) { return failed(.changed) }
                // AX bootstrap can replace a non-editable wrapper with its
                // real text field. Once a text field was observed, keep its
                // identity even when its range is temporarily unavailable.
                let role = accessibility.attribute(kAXRoleAttribute, of: element) as? String
                if role == kAXTextFieldRole || role == kAXTextAreaRole { firstElement = element }
                let target = Target(element: element, pid: focus.pid, accessibility: accessibility, processStart: focus.processStart)
                if target.selection() != nil { return allowed() && (focus.processStart == nil || target.isCurrent()) ? target : failed(.changed) }
                if focus.processStart != nil { return failed(.unavailableSelection) }
                reason = .unavailableSelection
            }
            return failed(reason)
        }

        func matches(_ other: Target) -> Bool { pid == other.pid && processStart == other.processStart && CFEqual(element, other.element) }
        func isCurrent() -> Bool {
            guard !accessibility.isSecure, let current = accessibility.focusedElement(pid: pid, processStart: processStart) else { return false }
            return CFEqual(element, current)
                && accessibility.attribute(kAXSubroleAttribute, of: element) as? String != kAXSecureTextFieldSubrole
        }
        func selection() -> CFRange? {
            guard let value = accessibility.attribute(kAXSelectedTextRangeAttribute, of: element),
                  CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
            var range = CFRange()
            guard AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cfRange, &range),
                  range.location >= 0, range.length >= 0 else { return nil }
            return range
        }
        func value() -> String? { accessibility.attribute(kAXValueAttribute, of: element) as? String }
        func text(in range: CFRange) -> String? {
            guard range.location >= 0, range.length >= 0, let text = value(),
                  range.location <= text.utf16.count, range.length <= text.utf16.count - range.location else { return nil }
            return (text as NSString).substring(with: NSRange(location: range.location, length: range.length))
        }
        func sourceRange(_ expected: String) -> CFRange? {
            let source = ReplacementSource(expected: expected)
            guard isCurrent(), let selection = selection(),
                  let range = source.rangeBeforeCaret(location: selection.location, selectionLength: selection.length) else { return nil }
            let atStart = range.lowerBound == 0
            let validationStart = atStart ? 0 : range.lowerBound - 1
            guard source.matches(text(in: CFRange(location: validationStart,
                                                  length: range.upperBound - validationStart)),
                                 atDocumentStart: atStart) else { return nil }
            return CFRange(location: range.lowerBound, length: range.count)
        }

        /// Explicit Option can recover a word which predates event-tap binding.
        /// Capture this on the selection worker, never by reading AX in the tap.
        func wordBeforeCaret(_ caret: CFRange, in snapshot: String? = nil) -> (range: CFRange, text: String)? {
            guard caret.length == 0, isCurrent(), let original = snapshot ?? value(), caret.location <= original.utf16.count,
                  selection().map({ $0.location == caret.location && $0.length == 0 }) == true else { return nil }
            let prefix = (original as NSString).substring(to: caret.location)
            var tail = ""
            var foundWord = false
            for character in prefix.reversed() {
                if !foundWord, character == " " {
                    tail.insert(character, at: tail.startIndex)
                    if tail.utf16.count > 4096 { return nil }
                    continue
                }
                if character.isWhitespace { break }
                foundWord = true
                tail.insert(character, at: tail.startIndex)
                if tail.utf16.count > 4096 { return nil }
            }
            guard foundWord else { return nil }
            return (CFRange(location: caret.location - tail.utf16.count, length: tail.utf16.count), tail)
        }

        /// An attempted text write is never retried, even if AX reports failure.
        /// Only exact readback plus a collapsed caret can confirm it. Select the
        /// Unicode route BEFORE mutation for bridges with missing/no-op setters.
        func replace(range: CFRange, expected: String, with replacement: String,
                     originalSelection: CFRange, requiresWordBoundary: Bool = false, capturedValue: String? = nil, allowed: () -> Bool) -> ReplacementResult {
            func selected(_ expected: CFRange) -> Bool {
                selection().map { $0.location == expected.location && $0.length == expected.length } == true
            }
            guard allowed(), isCurrent(), selected(originalSelection), let original = value(),
                  capturedValue.map({ $0 == original }) != false,
                  range.location >= 0, range.length >= 0, range.location <= original.utf16.count,
                  range.length <= original.utf16.count - range.location,
                  (original as NSString).substring(with: NSRange(location: range.location, length: range.length)) == expected else { return .untouched }
            if requiresWordBoundary {
                let start = max(0, range.location - 1)
                let validation = (original as NSString).substring(with: NSRange(location: start, length: range.location + range.length - start))
                guard ReplacementSource(expected: expected).matches(validation, atDocumentStart: range.location == 0) else { return .untouched }
            }
            let direct = accessibility.selectedTextIsSettable(element) && !accessibility.prefersUnicodeInsertion(pid: pid)
            guard direct || accessibility.supportsUnicodeInsertion(element) else { return .untouched }
            guard allowed(), isCurrent(), selected(originalSelection), value() == original else { return .untouched }
            var attempted = false
            var selectionRequested = false
            var selectionConfirmed = false
            func confirmSelection(_ expected: CFRange, requireAllowed: Bool = true) -> Bool {
                for attempt in 0..<6 {
                    if attempt > 0 { Thread.sleep(forTimeInterval: 0.025) }
                    guard (!requireAllowed || allowed()), isCurrent(), value() == original else { return false }
                    if selected(expected) { return true }
                }
                return false
            }
            func finish(_ result: ReplacementResult) -> ReplacementResult {
                // A selection RPC can apply and still report failure. Restore
                // only our exact selection over unchanged content, and READ BACK
                // restoration before permitting a physical separator to replay.
                if isCurrent(), selected(range), value() == original {
                    if range.location != originalSelection.location || range.length != originalSelection.length {
                        _ = accessibility.setSelection(originalSelection, in: element)
                        if !confirmSelection(originalSelection, requireAllowed: false) { return .unconfirmedSelection }
                    }
                    selectionConfirmed = true
                } else if result == .untouched, !selected(originalSelection) {
                    return .unconfirmedSelection
                }
                // An acknowledged AX action may still be in the editor's queue.
                // Seeing the old caret cannot prove that no selection will apply.
                if selectionRequested && !selectionConfirmed { return .unconfirmedSelection }
                return result
            }
            // Explicit conversion already owns this verified selection. Sending
            // it again could reselect old offsets after text/caret changed.
            if range.location != originalSelection.location || range.length != originalSelection.length {
                selectionRequested = true
                _ = accessibility.setSelection(range, in: element)
            }
            selectionConfirmed = confirmSelection(range)
            guard selectionConfirmed, allowed(), isCurrent(), value() == original, allowed() else { return finish(.untouched) }
            func replacing(_ value: String, _ selected: CFRange, _ text: String) -> String {
                (value as NSString).replacingCharacters(in: NSRange(location: selected.location, length: selected.length), with: text)
            }
            func confirm(_ expected: String, caret: Int) -> Bool {
                for attempt in 0..<6 {
                    if attempt > 0 { Thread.sleep(forTimeInterval: 0.025) }
                    guard allowed(), isCurrent() else { return false }
                    if value() == expected, selected(CFRange(location: caret, length: 0)) { return true }
                }
                return false
            }
            if direct {
                attempted = true
                _ = accessibility.setSelectedText(replacement, in: element)
                let expectedValue = replacing(original, range, replacement)
                let end = range.location + replacement.utf16.count
                // Native setters can retain selection. Collapse only our own
                // exact replacement after verifying the full resulting value.
                if allowed(), isCurrent(), value() == expectedValue,
                   selected(CFRange(location: range.location, length: replacement.utf16.count)) {
                    _ = accessibility.setSelection(CFRange(location: end, length: 0), in: element)
                }
                return finish(confirm(expectedValue, caret: end) ? .confirmed : .uncertain)
            }
            var currentValue = original
            var currentRange = range
            for chunk in DictationTarget.unicodeChunks(replacement) {
                guard allowed(), isCurrent(), value() == currentValue, selected(currentRange), allowed() else {
                    return finish(attempted ? .uncertain : .untouched)
                }
                let expectedValue = replacing(currentValue, currentRange, chunk)
                attempted = true
                guard accessibility.postUnicode(chunk, pid: pid) else { return finish(.uncertain) }
                let end = currentRange.location + chunk.utf16.count
                guard confirm(expectedValue, caret: end) else { return finish(.uncertain) }
                currentValue = expectedValue
                currentRange = CFRange(location: end, length: 0)
            }
            return finish(attempted ? .confirmed : .untouched)
        }
    }

    /// Accessed exclusively on Typist's serial queue. A delivered physical Tab
    /// or Enter may intentionally move focus; subsequent physical replays follow
    /// native event order until idle, unless unrelated navigation cancels them.
    final class ReplayRoute {
        private let target: Target
        private var policy = InputReplayPolicy()
        private var uncertain = false
        private var holdingAllInput = false
        init(target: Target) { self.target = target }
        func didNavigate() { policy.didDeliverNavigation() }
        func didBecomeUncertain(holdingAllInput: Bool = false) {
            uncertain = true
            self.holdingAllInput = self.holdingAllInput || holdingAllInput
        }
        var requiresRecovery: Bool { uncertain }
        func canReplay(permit: Permit, navigates: Bool = false) -> Bool {
            if holdingAllInput { return false }
            if uncertain && (navigates || target.selection()?.length != 0) { return false }
            let current = policy.followsNavigation || target.isCurrent()
            return policy.allowsReplay(cancelled: !permit.isAllowed,
                                       secure: target.accessibility.isSecure, originalTargetCurrent: current)
        }
    }

    /// Read-only evidence captured for a fresh Option stream. It can veto the
    /// buffered route without requiring an AX setter or claiming readback.
    struct BufferedSource {
        let target: Target
        let selection: CFRange
        let value: String
        let permit: Permit

        var isAllowed: Bool { permit.isAllowed && target.isCurrent() && permit.isAllowed }

        func matches(_ expected: String) -> Bool {
            guard isAllowed, selection.length == 0,
                  target.selection().map({ $0.location == selection.location && $0.length == 0 }) == true,
                  let range = target.sourceRange(expected), range.location + range.length == selection.location,
                  target.value() == value else { return false }
            return isAllowed
        }
    }

    struct Ticket {
        let target: Target
        let permit: Permit
        let replacementPermit: Permit
        let replayRoute: ReplayRoute
        var allowsReplacement: Bool { replacementPermit.isAllowed && isCurrent }
        var isCurrent: Bool { permit.isAllowed && target.isCurrent() && permit.isAllowed }
    }

    private let queue = DispatchQueue(label: "MacLayoutSwitcher.InputFocus")
    private var timer: DispatchSourceTimer?
    private var permit = Permit()
    private var replacementPermit = Permit()
    private var target: Target?
    private var replayRoute: ReplayRoute?
    private var sampling = false
    private(set) var isProtectedField = false
    private var protectedFieldPID: pid_t?
    var onChange: (() -> Void)?
    var shouldSample: (() -> Bool)?
    var ticket: Ticket? {
        guard let target, let replayRoute else { return nil }
        return Ticket(target: target, permit: permit, replacementPermit: replacementPermit, replayRoute: replayRoute)
    }

    func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.refresh() }
        self.timer = timer
        timer.resume()
    }

    func stop() { timer?.cancel(); timer = nil; invalidate() }

    /// Main-thread, constant-time cancellation, suitable for the event callback.
    func invalidate() {
        permit.cancel()
        replacementPermit.cancel()
        permit = Permit()
        replacementPermit = Permit()
        target = nil
        replayRoute = nil
        onChange?()
        // The click itself must first reach the application. Start an off-tap
        // refresh on the next main-loop turn rather than waiting for the timer.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.timer != nil else { return }
            self.refresh()
        }
    }

    /// A correction failure invalidates dependent corrections, not physical keys.
    /// Return false for a completion from an older field or already reset batch.
    func reject(_ ticket: Ticket) -> Bool {
        guard permit === ticket.permit, replacementPermit === ticket.replacementPermit else { return false }
        replacementPermit.cancel()
        replacementPermit = Permit()
        return true
    }

    /// Main-thread handoff from an explicit off-tap capture. A cancelled focus
    /// generation is never revived by a late result.
    var generation: Permit { permit }
    func bind(_ captured: Target, generation: Permit, replacingCachedTarget: Bool = false) -> Ticket? {
        guard permit === generation, generation.isAllowed else { return nil }
        if let target, !target.matches(captured) {
            guard replacingCachedTarget else { invalidate(); return nil }
            // Explicit capture owns a fresh target. Retire cached work without
            // cancelling the separate conversion request that captured it.
            permit.cancel()
            replacementPermit.cancel()
            permit = Permit()
            replacementPermit = Permit()
            replayRoute = nil
        }
        target = captured
        if replayRoute == nil { replayRoute = ReplayRoute(target: captured) }
        return ticket
    }

    /// Called on main only after Typist is idle. Uncertainty belongs to one
    /// queued batch, not every future Enter in this editor.
    func finishBatch() {
        if replayRoute?.requiresRecovery == true { invalidate() }
    }

    private func refresh() {
        guard !sampling, shouldSample?() != false else { return }
        sampling = true
        let requestedPermit = permit
        let expectedPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        queue.async { [weak self] in
            // Unknown AX cannot downgrade a previously known secure field.
            // Global SecureInput is independently sampled by Engine/Typist.
            var protectedField: Bool?
            let captured = Target.capture(expectedPID: expectedPID, allowed: { requestedPermit.isAllowed },
                preparingOnly: true, failure: { failure in
                    if case .protectedField = failure { protectedField = true }
                })
            if captured != nil { protectedField = false }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.sampling = false
                guard self.timer != nil, self.permit === requestedPermit, self.shouldSample?() != false else { return }
                let changedProtectedApplication = self.isProtectedField
                    && expectedPID != nil && expectedPID != self.protectedFieldPID
                if let protection = protectedField ?? (changedProtectedApplication ? false : nil) {
                    self.protectedFieldPID = protection ? expectedPID : nil
                    if self.isProtectedField != protection {
                        self.isProtectedField = protection
                        self.invalidate()
                        return
                    }
                }
                let unchanged = self.target.flatMap { old in captured.map { old.matches($0) } } ?? (captured == nil && self.target == nil)
                if self.target == nil, let captured {
                    _ = self.bind(captured, generation: requestedPermit)
                } else if !unchanged {
                    self.invalidate()
                    self.target = captured
                    self.replayRoute = captured.map(ReplayRoute.init)
                }
            }
        }
    }
}
#endif
