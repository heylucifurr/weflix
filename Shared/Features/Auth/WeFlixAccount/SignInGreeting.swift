import SwiftUI

/// The one line under **Sign in** on the WeFlix sign-in screen.
///
/// It is a pool rather than one fixed sentence so the screen is not word-for-word the same every time it is
/// reached. The same person sees it whenever their token is refused or they sign out, and a line that never
/// changes stops being read.
///
/// **The lines are English literals used as their own localisation keys**, exactly as the rest of the screen is
/// (`WeFlixSignInView`), so Xcode extracts them into `Localizable.xcstrings` and `fr`/`zh-Hans` translate them
/// in place — there is no second place to keep a key and its wording in step.
///
/// 2026-10-26, requested by Luther: *"can we change this dynamically? like not static? like it change
/// everytime?"* — with the three lines below as the ones he wanted on it.
@MainActor
enum SignInGreeting {
    /// The rotation, in the order it tends to be seen. **This array is the whole feature**: add a line here and it
    /// joins immediately, on all three platforms, with nothing else to edit. `SignInGreetingTests` reads it, so a
    /// line added here is covered by the tests that already exist rather than needing new ones.
    static let all: [LocalizedStringKey] = [
        "Welcome back. Your shows are waiting.",
        "Pull up a seat. Movie night starts here.",
        "Good to see you again.",
    ]

    /// Where the rotation currently stands — **deliberately outside the view.**
    ///
    /// `WeFlixAppGate` builds `WeFlixSignInView` fresh every time it returns to `.signedOut`, so a cursor kept in
    /// the view would be reset to the same starting line on every visit and the screen would look static — the
    /// exact thing this replaced. Held here, each visit is guaranteed a line the person did not just read; a plain
    /// `randomElement()` repeats the line just read one time in three.
    ///
    /// Safe as shared mutable state because the enum is `@MainActor` and nothing but the sign-in view touches it.
    private static var cursor = Int.random(in: all.indices)

    /// The line to show. **Reading it never moves anything** — see `advance()` for why that separation is load
    /// bearing rather than tidiness.
    static var current: LocalizedStringKey { all[cursor] }

    /// Steps the rotation on, so the **next** visit shows a different line. Never the same one: the step is a
    /// random `1 ..< count` and `% count` wraps it, so it can neither stand still nor follow a visible order. With
    /// a one-line pool there is nothing to rotate to and this does nothing.
    ///
    /// **Called once per appearance from the view's `onAppear`, and never from a property initialiser.** The first
    /// version of this advanced from `@State private var greeting = SignInGreeting.next()`, and that was wrong:
    /// SwiftUI re-creates a view *struct* on every parent re-render, so the initialiser runs on every keystroke in
    /// the form. The cursor raced far ahead of the line on screen and "never the one just shown" quietly stopped
    /// being true. Splitting read from advance is what makes the guarantee hold.
    ///
    /// 2026-10-26 — caught by looking at three consecutive launches rather than by a test, which is why
    /// `SignInGreetingTests` now pins *both* halves: that reading is idempotent, and that advancing always differs.
    static func advance() {
        guard all.count > 1 else { return }

        cursor = (cursor + Int.random(in: 1 ..< all.count)) % all.count
    }
}
