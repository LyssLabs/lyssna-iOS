enum LyssnaPropertyModification {
    case remove
    case setBool(Bool)
    case setEnum(String)
    // Flip if present, append if missing (needs name + scope).
    case forceBool(Bool)
}

struct LyssnaPropertyReplacement {
    let scope: String?
    let name: String?
    let modification: LyssnaPropertyModification
    
    init(name: String? = nil, scope: String? = nil, modification: LyssnaPropertyModification) {
        self.name = name
        self.scope = scope
        self.modification = modification
    }
}
