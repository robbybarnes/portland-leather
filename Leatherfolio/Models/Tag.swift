import SwiftData
import Foundation

@Model
final class Tag {
    var name: String = ""
    var items: [Item]? = []
    init(name: String = "") { self.name = name }
}
