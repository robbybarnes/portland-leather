enum ItemCategory: String, Codable, CaseIterable, Identifiable {
    case tote = "Tote"
    case crossbodyTote = "Crossbody Tote"
    case crossbody = "Crossbody"
    case beltBag = "Belt Bag"
    case backpack = "Backpack"
    case wallet = "Wallet"
    case cardholder = "Cardholder"
    case belt = "Belt"
    case accessory = "Accessory"
    case other = "Other"
    var id: String { rawValue }
}

enum LeatherType: String, Codable, CaseIterable, Identifiable {
    case smooth = "Smooth"
    case pebbled = "Pebbled"
    case suede = "Suede"
    case metallic = "Metallic"
    case other = "Other"
    var id: String { rawValue }
}

enum ItemCondition: String, Codable, CaseIterable, Identifiable {
    case new = "New"
    case excellent = "Excellent"
    case good = "Good"
    case worn = "Worn"
    var id: String { rawValue }
}
