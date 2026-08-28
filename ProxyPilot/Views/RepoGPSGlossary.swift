import SwiftUI

/// RepoGPS vocabulary, so the harness surfaces can use its terms without the reader
/// having to already know them.
///
/// Definitions are taken from RepoGPS's own bundled behavior pack
/// (`RepoGPSPayload/.../BehaviorPack/skills/*/SKILL.md`) rather than restated, so this
/// glossary cannot drift from what the harness actually does.
struct RepoGPSGlossaryTerm: Identifiable, Equatable {
    let term: String
    let short: String
    let full: String

    var id: String { term }
}

enum RepoGPSGlossary {
    static let terms: [RepoGPSGlossaryTerm] = [
        RepoGPSGlossaryTerm(
            term: "Basecamp",
            short: "A reversible governance foundation for a repository.",
            full: "Establishes and maintains a tiered, reversible governance foundation plus scoped session Waypoints. RepoGPS prefers a repository's existing governance: it previews every missing artifact, asks once before writing, creates only what is missing without clobbering existing work, and records a rollback receipt."
        ),
        RepoGPSGlossaryTerm(
            term: "Waypoint",
            short: "A session handoff record.",
            full: "Waypoints record entry state, intended scope, changed files, verification, blockers, and the next safe action. They do not replace repository instructions, development history, release procedures, or your authorization."
        ),
        RepoGPSGlossaryTerm(
            term: "Retrace",
            short: "Re-establish what is true right now, changing nothing.",
            full: "Reads the closest repository instructions, branch and worktree state, current plans, recent history, and the latest handoff, distinguishing selected, configured, stored, and live evidence. It returns a compact orientation card and never edits, tests, commits, pushes, deploys, or writes durable state."
        ),
        RepoGPSGlossaryTerm(
            term: "Resurface",
            short: "Re-enter a repository after it has gone quiet.",
            full: "Begins with Retrace, then compares the current silence against the repository's own cadence, re-reads durable invariants, inspects what changed since the last trustworthy handoff, and labels remembered assumptions as confirmed, superseded, or unresolved. It produces a Season Delta and a re-entry sequence, and does not implement repairs."
        ),
        RepoGPSGlossaryTerm(
            term: "Season Delta",
            short: "What changed while the repository slept.",
            full: "The output of Resurface: the list of everything that moved in the repository and its surroundings during the dormancy, so assumptions carried in from an earlier era can be quarantined instead of trusted."
        ),
        RepoGPSGlossaryTerm(
            term: "ALMANAC",
            short: "Generated repository history, derived from Git.",
            full: "A deterministic, generated page reporting genesis arithmetic, commit cadence, release-window eras, a fix-commit breakage proxy, and file churn — every line derived from Git history rather than written by an agent. Deep Expedition mode installs the machinery that keeps it current."
        ),
        RepoGPSGlossaryTerm(
            term: "Quick Look",
            short: "Read-only orientation.",
            full: "Reports repository and Git state without creating any Basecamp files. The safe way to look around an unfamiliar repository first."
        ),
        RepoGPSGlossaryTerm(
            term: "Deep Expedition",
            short: "The most thorough orientation mode.",
            full: "Adds the Standard foundation plus deterministic ALMANAC and Waypoint machinery, so history and handoffs stay generated rather than hand-maintained."
        )
    ]
}

/// A term rendered as a small pill. Hovering shows the one-line meaning as a tooltip;
/// clicking opens the full definition in a popover.
struct GlossaryTermChip: View {
    let entry: RepoGPSGlossaryTerm

    @State private var isShowingDefinition = false

    var body: some View {
        Button {
            isShowingDefinition.toggle()
        } label: {
            Text(entry.term)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(.tertiary, lineWidth: 0.5)
                }
        }
        .buttonStyle(.plain)
        .help(entry.short)
        .accessibilityLabel("\(entry.term). \(entry.short)")
        .accessibilityHint("Shows the full definition")
        .popover(isPresented: $isShowingDefinition, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text(entry.term)
                    .font(.headline)

                Text(entry.full)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(width: 320)
        }
    }
}

/// A wrapping row of glossary chips. Used wherever RepoGPS vocabulary first appears.
struct GlossaryTermRow: View {
    var terms: [RepoGPSGlossaryTerm] = RepoGPSGlossary.terms
    var caption: String? = "Hover for a one-line meaning, click for the full definition."

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 6) {
                ForEach(terms) { entry in
                    GlossaryTermChip(entry: entry)
                }
            }

            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// Minimal wrapping layout. The chips must reflow at narrow widths, and an `HStack`
/// would clip them instead.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0 && rowWidth + spacing + size.width > maxWidth {
                totalWidth = max(totalWidth, rowWidth)
                totalHeight += rowHeight + spacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }

        totalWidth = max(totalWidth, rowWidth)
        totalHeight += rowHeight
        return CGSize(width: min(totalWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
