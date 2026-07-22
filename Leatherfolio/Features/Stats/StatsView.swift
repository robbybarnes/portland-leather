import SwiftUI
import Charts

/// Renders CollectionStats (Phase 2 value type — all math lives there and is
/// unit-tested there). Tasteful per the spec: counts, money, one chart,
/// completeness. No streaks, no badges.
struct StatsView: View {
    let stats: CollectionStats

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
                Text(String(format: "%.1f of 5", average))
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
