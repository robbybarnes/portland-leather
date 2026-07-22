import Foundation

enum StatsFormatting {
    static func averageRating(
        _ average: Double,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let style = FloatingPointFormatStyle<Double>(locale: locale)
            .precision(.fractionLength(1))
        return "\(average.formatted(style)) of 5"
    }
}
