import Testing

@testable import weflix

/// The sign-in screen's greeting: the rules that must hold for "a different line every time" to be true, and not
/// merely likely.
///
/// No network, no view, no clock — `SignInGreeting` is a list and a cursor. Four things about it would each be
/// embarrassing to get wrong, and each has a test below: a pool too small to rotate, two lines that read the same,
/// **a read that moves the rotation** (the defect of 2026-10-26), and an `advance()` that does not actually leave
/// the line it was on.
@MainActor
struct SignInGreetingTests {
    @Test func `the rotation has more than one line to rotate through`() {
        #expect(
            SignInGreeting.all.count > 1,
            "with one line there is no rotation, and the screen is static again",
        )
    }

    @Test func `no two lines in the rotation say the same thing`() {
        // Two identical entries would be two positions the cursor treats as different while the screen shows no
        // change at all, which reads as the rotation being stuck. Pairwise rather than a `Set`: `LocalizedStringKey`
        // is `Equatable` but not `Hashable` (measured — `Set(SignInGreeting.all)` does not compile).
        for index in SignInGreeting.all.indices {
            for other in SignInGreeting.all.indices where other > index {
                #expect(
                    SignInGreeting.all[index] != SignInGreeting.all[other],
                    "lines \(index) and \(other) are the same line",
                )
            }
        }
    }

    @Test func `reading the line never moves the rotation`() {
        // The bug this pins (2026-10-26): the first version advanced the cursor from the view's `@State` property
        // initialiser. SwiftUI re-creates a view struct on every parent re-render — every keystroke in the form —
        // so the cursor ran far ahead of the line on screen and "never the one just shown" stopped being true.
        // Reading must be free of side effects; only `advance()` may step.
        let line = SignInGreeting.current

        for read in 1 ... 50 {
            #expect(SignInGreeting.current == line, "read \(read) moved the rotation")
        }
    }

    @Test func `advancing always leaves a different line`() {
        // Walk the rotation well past the number of lines: a random step that could be zero, or a rotation that is
        // not advanced at all, shows up here within one or two steps rather than after a release.
        var previous = SignInGreeting.current

        for step in 1 ... 30 {
            SignInGreeting.advance()

            let current = SignInGreeting.current
            #expect(current != previous, "step \(step) repeated the line before it")
            previous = current
        }
    }
}
