import SwiftUI
import Charts

/// Renders CollectionStats (Phase 2 value type — all math lives there and is
/// unit-tested there). Tasteful per the spec: counts, money, one chart,
/// completeness. No streaks, no badges.
struct StatsView: View {
    let stats: CollectionStats
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showDog = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headline
                moneyBlock
                ratingBlock
                categoryChart
                completenessBlock
            }
            .padding()
        }
        .navigationTitle("Stats")
        .background(Theme.background)
        .sensoryFeedback(trigger: showDog) { _, revealed in
            revealed ? .impact(flexibility: .soft) : nil
        }
        .overlay {
            if showDog {
                HouseDogReveal {
                    withAnimation(.easeOut(duration: 0.2)) { showDog = false }
                }
                .transition(reduceMotion
                            ? .opacity
                            : .scale(scale: 0.85).combined(with: .opacity))
            }
        }
    }

    /// Easter egg: the house dog, hidden behind a long-press on the headline.
    private func revealDog() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.62)) {
            showDog = true
        }
    }

    // MARK: - Blocks

    private var headline: some View {
        Text(StatsHeadline.text(
            itemCount: stats.itemCount,
            colorCount: stats.distinctColorCount,
            leatherTypeCount: stats.distinctLeatherTypeCount,
            unicornCount: stats.unicornCount
        ))
        .font(.display(.title3))
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.5) { revealDog() }
        .accessibilityAddTraits(.isHeader)
        .accessibilityAction(named: "Meet the house dog") { revealDog() }
    }

    private var moneyBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            LabeledContent("Total spent",
                           value: CurrencyFormat.string(from: stats.totalSpent))
            LabeledContent("Estimated value",
                           value: CurrencyFormat.string(from: stats.totalEstimatedValue))
            LabeledContent("Unrealized delta") {
                Text(CurrencyFormat.signedString(from: stats.unrealizedDelta))
                    .fontWeight(.semibold)
                    .foregroundStyle(stats.unrealizedDelta >= 0 ? Theme.gain : Theme.loss)
            }
        }
        .cardStyle()
    }

    private var ratingBlock: some View {
        LabeledContent("Average rating") {
            if let average = stats.averageRating {
                Text(StatsFormatting.averageRating(average))
            } else {
                Text("No ratings yet")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var categoryChart: some View {
        if !stats.itemsByCategory.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Items by category")
                    .font(.headline)
                Chart(stats.itemsByCategory, id: \.category) { entry in
                    BarMark(
                        x: .value("Items", entry.count),
                        y: .value("Category", entry.category.rawValue)
                    )
                }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                .frame(height: CGFloat(stats.itemsByCategory.count) * 36 + 24)
                .accessibilityLabel("Bar chart of items by category")
            }
        }
    }

    @ViewBuilder private var completenessBlock: some View {
        if !stats.lineCompleteness.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Line completeness")
                    .font(.headline)
                ForEach(stats.lineCompleteness) { line in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(line.ownedColors.count) of \(line.totalColors) \(line.lineName) colors")
                            .font(.subheadline)
                        ProgressView(
                            value: Double(line.ownedColors.count),
                            total: Double(max(line.totalColors, 1))
                        )
                        .accessibilityLabel("\(line.lineName): \(line.ownedColors.count) of \(line.totalColors) colors")
                    }
                }
            }
        }
    }
}

/// The house dog easter egg: a dimmed backdrop and a spring-in portrait of the
/// Chief Bag Inspector. Dismissed by tapping anywhere or the VoiceOver escape.
private struct HouseDogReveal: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: Theme.Spacing.m) {
                Image("HouseDog")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
                Text("Chief Bag Inspector")
                    .font(.display(.title3))
                    .foregroundStyle(.white)
                Text("Tap to dismiss")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(Theme.Spacing.xl)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel("The house dog, Chief Bag Inspector")
        .accessibilityHint("Tap to dismiss")
        .accessibilityAction(.escape, onDismiss)
    }
}
