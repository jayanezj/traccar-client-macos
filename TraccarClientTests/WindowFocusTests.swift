import Testing

@MainActor
struct WindowFocusTests {
    @Test func restoresInitiatingWindowAfterActivationCompletes() async {
        let activation = ActivationGate()
        let window = FocusWindow()
        let otherWindow = FocusWindow()
        let focus = WindowFocusController { await activation.request() }
        focus.window = window
        var actionFinished = false
        let task = focus.perform { actionFinished = true }
        await activation.waitForRequest()
        #expect(actionFinished && window.restorations == 0)
        focus.window = otherWindow
        activation.complete(success: true)
        await task?.value
        #expect(window.restorations == 1 && otherWindow.restorations == 0)
    }

    @Test(arguments: [false, true])
    func closingOrMinimizingDuringActivationDoesNotRecoverWindow(minimized: Bool) async {
        let activation = ActivationGate()
        let window = FocusWindow()
        let focus = WindowFocusController { await activation.request() }
        focus.window = window
        let task = focus.perform {}
        await activation.waitForRequest()
        if minimized { window.isMiniaturized = true } else { window.isVisible = false }
        activation.complete(success: true)
        await task?.value
        #expect(window.restorations == 0)
    }

    @Test func missingOrClosedWindowDoesNotRequestActivation() async {
        var requests = 0
        let focus = WindowFocusController { requests += 1; return true }
        #expect(focus.perform {} == nil)
        let window = FocusWindow()
        window.isVisible = false
        focus.window = window
        #expect(focus.perform {} == nil)
        #expect(requests == 0)
    }

    @Test func activationFailureDoesNotOrderWindowForward() async {
        let window = FocusWindow()
        let focus = WindowFocusController { false }
        focus.window = window
        await focus.perform {}?.value
        #expect(window.restorations == 0)
    }

    @Test func newerActionCancelsEarlierRestoration() async {
        let activation = ActivationGate()
        let window = FocusWindow()
        var requests = 0
        let focus = WindowFocusController {
            requests += 1
            if requests == 1 { return await activation.request() }
            return true
        }
        focus.window = window
        let first = focus.perform {}
        await activation.waitForRequest()
        await focus.perform {}?.value
        #expect(window.restorations == 1)
        activation.complete(success: true)
        await first?.value
        #expect(window.restorations == 1)
    }
}

@MainActor
private final class FocusWindow: FocusRestorationWindow {
    var isVisible = true
    var isMiniaturized = false
    var restorations = 0
    func restoreKeyWindow() { restorations += 1 }
}

@MainActor
private final class ActivationGate {
    private var completion: CheckedContinuation<Bool, Never>?
    private var entered: CheckedContinuation<Void, Never>?

    func request() async -> Bool {
        await withCheckedContinuation { continuation in
            completion = continuation
            entered?.resume()
            entered = nil
        }
    }

    func waitForRequest() async {
        if completion != nil { return }
        await withCheckedContinuation { entered = $0 }
    }

    func complete(success: Bool) {
        completion?.resume(returning: success)
        completion = nil
    }
}
