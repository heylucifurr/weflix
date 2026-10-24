import SwiftUI

/// Settings → **Licences**: where this app comes from, and the licence it stays under (2026-10-25).
///
/// WeFlix for Apple is a modified version of **Strimr** by wunax. The GPL-3.0 requires that a modified version
/// says so and carries the notice, and until now the only place it did was `README.md` — which is fine for
/// somebody reading the repository and useless for somebody holding the app. This screen is that sentence in the
/// app itself, word for word the same one the README carries.
///
/// It is deliberately plain text and deliberately not a link farm: the two URLs are shown as text a person can
/// read and copy, and the notice is complete rather than summarised.
struct LicencesView: View {
    /// The attribution line, kept identical to `README.md`'s so the two cannot drift apart in meaning.
    static let attribution = """
        WeFlix for Apple is a modified version of Strimr by wunax (https://github.com/wunax/strimr), \
        licensed GPL-3.0. Modified by Luther, 2026.
        """

    var body: some View {
        List {
            Section("Strimr") {
                Text(Self.attribution)
                    .font(.subheadline)
            }

            Section("GPL-3.0") {
                Text(
                    """
                    This app is free software: you can redistribute it and/or modify it under the terms of the \
                    GNU General Public License as published by the Free Software Foundation, either version 3 of \
                    the License, or (at your option) any later version.

                    This app is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without \
                    even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU \
                    General Public License for more details.

                    The full licence text ships with the source at https://github.com/heylucifurr/weflix \
                    (LICENSE), and the original project's notice is kept there unchanged.
                    """,
                )
                .font(.subheadline)
            }
        }
        // `insetListStyle()` is the app's own modifier (`Shared/Views/InsetListStyle.swift`), which tvOS does not
        // compile: its settings are a sidebar and a focus engine, and this screen is reached from one.
        #if !os(tvOS)
            .insetListStyle()
        #endif
            .navigationTitle("Licences")
    }
}
