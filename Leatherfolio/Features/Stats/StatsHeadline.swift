import Foundation

/// Pure composition of the stats headline, e.g.
/// "12 items · 5 colors · 3 leather types · 2 unicorns".
enum StatsHeadline {
    static func text(itemCount: Int, colorCount: Int,
                     leatherTypeCount: Int, unicornCount: Int) -> String {
        var parts = [
            counted(itemCount, "item"),
            counted(colorCount, "color"),
            counted(leatherTypeCount, "leather type"),
        ]
        if unicornCount > 0 {
            parts.append(counted(unicornCount, "unicorn"))
        }
        return parts.joined(separator: " · ")
    }

    private static func counted(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }
}
