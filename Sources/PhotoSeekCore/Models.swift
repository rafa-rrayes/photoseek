import Foundation

public struct SearchResult: Identifiable, Sendable {
    public let rank: Int
    public let score: Double
    public let uuid: String
    public let filename: String
    public let date: String
    public let path: String
    public let derivative: String
    public let title: String
    public let albums: [String]
    public let persons: [String]

    public var id: String { uuid }

    public init(rank: Int, score: Double, uuid: String, filename: String, date: String,
                path: String, derivative: String, title: String, albums: [String], persons: [String]) {
        self.rank = rank
        self.score = score
        self.uuid = uuid
        self.filename = filename
        self.date = date
        self.path = path
        self.derivative = derivative
        self.title = title
        self.albums = albums
        self.persons = persons
    }
}
