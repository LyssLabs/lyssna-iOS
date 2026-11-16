struct LyssnaContributorSection: Decodable, Equatable {
    var title: String
    var shuffled: Bool
    var contributors: [LyssnaContributor]
}
