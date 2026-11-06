#if os(macOS)
import ApplicationServices
import Foundation
import SwitcherCore

/// Explicit conversions only. AX reads run off EventTap; any later physical
/// input cancels the request before a selected-text write can be committed.
final class SelectionConverter {
    struct Selection {
        let target: InputFocusGuard.Target
        let range: CFRange
        let text: String
        let originalSelection: CFRange
        var isWord = false
        var sourceValue: String? = nil
    }
    enum Capture {
        case empty(InputFocusGuard.Target, CFRange, Selection?, String)
        case selected(Selection)
        case unavailable(InputFocusGuard.CaptureFailure)
    }
    private let queue = DispatchQueue(label: "MacLayoutSwitcher.SelectionCapture")
    private var permit: InputFocusGuard.Permit?

    var isPending: Bool { permit != nil }

    @discardableResult
    func cancel() -> Bool {
        let wasPending = permit != nil
        permit?.cancel()
        permit = nil
        return wasPending
    }
    func finish(_ request: InputFocusGuard.Permit) {
        if permit === request { permit = nil }
    }

    func capture(expectedPID: pid_t?, completion: @escaping (Capture, InputFocusGuard.Permit) -> Void) {
        cancel()
        let request = InputFocusGuard.Permit()
        permit = request
        queue.async {
            let result: Capture
            var failure = InputFocusGuard.CaptureFailure.unavailableField
            if request.isAllowed, let target = InputFocusGuard.Target.capture(expectedPID: expectedPID, allowed: { request.isAllowed }, failure: { failure = $0 }) {
                if let range = target.selection() {
                    if !target.isCurrent() {
                        result = .unavailable(.changed)
                    } else if range.length > 65_536 {
                        result = .unavailable(.selectionTooLarge)
                    } else if let value = target.value(), range.location <= value.utf16.count,
                              range.length <= value.utf16.count - range.location {
                        let text = (value as NSString).substring(with: NSRange(location: range.location, length: range.length))
                        let word = range.length == 0 ? target.wordBeforeCaret(range, in: value).map {
                            Selection(target: target, range: $0.range, text: $0.text, originalSelection: range,
                                      isWord: true, sourceValue: value)
                        } : nil
                        if target.isCurrent(),
                           target.selection().map({ $0.location == range.location && $0.length == range.length }) == true,
                           target.value() == value {
                            if range.length == 0 { result = .empty(target, range, word, value) }
                            else { result = .selected(Selection(target: target, range: range, text: text,
                                                               originalSelection: range, sourceValue: value)) }
                        } else { result = .unavailable(.changed) }
                    } else { result = .unavailable(range.length > 0 ? .unreadableSelection : .unavailableText) }
                } else { result = .unavailable(.unavailableSelection) }
            } else { result = .unavailable(failure) }
            DispatchQueue.main.async {
                guard request.isAllowed else { return }
                completion(result, request)
            }
        }
    }

    func replace(_ selection: Selection, permit: InputFocusGuard.Permit,
                 typist: Typist, replayRoute: InputFocusGuard.ReplayRoute, completion: @escaping (InputFocusGuard.ReplacementResult, Lang) -> Void) {
        let converted = KeyMap.selectionConversion(selection.text)
        typist.enqueue {
            let completed = selection.target.replace(range: selection.range,
                expected: selection.text, with: converted.text, originalSelection: selection.originalSelection, requiresWordBoundary: selection.isWord,
                capturedValue: selection.sourceValue, allowed: { permit.isAllowed })
            if completed.isUncertain { replayRoute.didBecomeUncertain(holdingAllInput: completed == .unconfirmedSelection) }
            DispatchQueue.main.async {
                if completed.isUncertain { typist.onUnconfirmedReplacement?(selection.text, converted.text) }
                completion(completed, converted.language)
            }
        }
    }
}
#endif
