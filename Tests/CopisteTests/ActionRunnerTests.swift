import AppKit
import Testing
@testable import Copiste

@MainActor
private final class SpyPaster: Pasting {
    private(set) var pasteCount = 0
    func paste() {
        self.pasteCount += 1
    }
}

@MainActor
private struct StubAccessibility: AccessibilityGate {
    var isTrusted: Bool
    let requested = Requested()
    func requestPermission() {
        self.requested.value = true
    }

    final class Requested { var value = false }
}

@MainActor
private func makePasteboard(withImage data: Data) -> NSPasteboard {
    let board = NSPasteboard(name: .init("com.bixentemal.copiste.tests-\(UUID().uuidString)"))
    board.clearContents()
    board.setData(data, forType: .png)
    return board
}

private let imageBytes = Data([0x89, 0x50, 0x4E, 0x47])

@Suite("Action delivery")
@MainActor
struct ActionRunnerTests {
    @Test("Copy leaves the text on the clipboard and restores nothing")
    func copyKeepsText() async {
        let board = makePasteboard(withImage: imageBytes)
        let paster = SpyPaster()
        let runner = ActionRunner(
            pasteboard: board,
            paster: paster,
            accessibility: StubAccessibility(isTrusted: true)) { _ in "hello\nworld" }

        await runner.run(.copy)

        #expect(board.string(forType: .string) == "hello\nworld")
        #expect(board.data(forType: .png) == nil, "the image must not come back in copy mode")
        #expect(paster.pasteCount == 0)
        #expect(runner.status == .recognized(lines: 2))
    }

    @Test("Paste types the text once and puts the image back")
    func pasteRestoresImage() async {
        let board = makePasteboard(withImage: imageBytes)
        let paster = SpyPaster()
        let runner = ActionRunner(
            pasteboard: board,
            paster: paster,
            accessibility: StubAccessibility(isTrusted: true)) { _ in "recognized" }

        await runner.run(.paste)

        #expect(paster.pasteCount == 1)
        #expect(board.data(forType: .png) == imageBytes, "the user's copy must survive the paste")
        #expect(board.string(forType: .string) == nil)
        #expect(runner.status == .recognized(lines: 1))
    }

    @Test("An empty recognition leaves the clipboard untouched")
    func emptyRecognition() async {
        let board = makePasteboard(withImage: imageBytes)
        let runner = ActionRunner(
            pasteboard: board,
            paster: SpyPaster(),
            accessibility: StubAccessibility(isTrusted: true)) { _ in "" }

        await runner.run(.copy)

        #expect(runner.status == .noText)
        #expect(board.data(forType: .png) == imageBytes)
        #expect(board.string(forType: .string) == nil)
    }

    @Test("A recognition failure leaves the clipboard untouched")
    func recognitionFailure() async {
        struct Failure: Error {}
        let board = makePasteboard(withImage: imageBytes)
        let runner = ActionRunner(
            pasteboard: board,
            paster: SpyPaster(),
            accessibility: StubAccessibility(isTrusted: true)) { _ in throw Failure() }

        await runner.run(.copy)

        #expect(runner.status == .unreadableImage)
        #expect(board.data(forType: .png) == imageBytes)
    }

    @Test("With no image, nothing runs")
    func noImage() async {
        let board = NSPasteboard(name: .init("com.bixentemal.copiste.tests-\(UUID().uuidString)"))
        board.clearContents()
        board.setString("text only", forType: .string)
        let runner = ActionRunner(
            pasteboard: board,
            paster: SpyPaster(),
            accessibility: StubAccessibility(isTrusted: true)) { _ in "unreachable" }

        await runner.run(.copy)

        #expect(runner.status == .noImage)
        #expect(board.string(forType: .string) == "text only")
    }

    @Test("Paste without Accessibility permission asks for it and does nothing else")
    func pasteWithoutPermission() async {
        let board = makePasteboard(withImage: imageBytes)
        let paster = SpyPaster()
        let gate = StubAccessibility(isTrusted: false)
        let runner = ActionRunner(pasteboard: board, paster: paster, accessibility: gate) { _ in "unreachable" }

        await runner.run(.paste)

        #expect(runner.status == .needsAccessibility)
        #expect(gate.requested.value)
        #expect(paster.pasteCount == 0)
        #expect(board.data(forType: .png) == imageBytes)
    }

    @Test("Copy works without Accessibility permission")
    func copyWithoutPermission() async {
        let board = makePasteboard(withImage: imageBytes)
        let runner = ActionRunner(
            pasteboard: board,
            paster: SpyPaster(),
            accessibility: StubAccessibility(isTrusted: false)) { _ in "no permission needed" }

        await runner.run(.copy)

        #expect(runner.status == .recognized(lines: 1))
        #expect(board.string(forType: .string) == "no permission needed")
    }

    @Test("A permission complaint clears once the permission is granted")
    func staleComplaintClears() async {
        let board = makePasteboard(withImage: imageBytes)
        let gate = StubAccessibility(isTrusted: false)
        let runner = ActionRunner(pasteboard: board, paster: SpyPaster(), accessibility: gate) { _ in "text" }

        await runner.run(.paste)
        #expect(runner.displayStatus == .needsAccessibility)

        // The user grants the permission in System Settings; no further action has run.
        let granted = ActionRunner(
            pasteboard: board,
            paster: SpyPaster(),
            accessibility: StubAccessibility(isTrusted: true)) { _ in "text" }
        await granted.run(.paste)
        #expect(granted.displayStatus == .recognized(lines: 1))
    }

    @Test("A second invocation while one is in flight is dropped")
    func dropsReentrantInvocation() async {
        let board = makePasteboard(withImage: imageBytes)
        let counter = CallCounter()
        let runner = ActionRunner(
            pasteboard: board,
            paster: SpyPaster(),
            accessibility: StubAccessibility(isTrusted: true))
        { _ in
            await counter.record()
            try? await Task.sleep(for: .milliseconds(80))
            return "slow"
        }

        async let first: Void = runner.run(.copy)
        try? await Task.sleep(for: .milliseconds(20))
        await runner.run(.copy)
        await first

        #expect(await counter.count == 1, "the second invocation would race the clipboard restore")
    }
}

private actor CallCounter {
    private(set) var count = 0
    func record() {
        self.count += 1
    }
}
