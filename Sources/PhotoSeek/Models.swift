import Foundation

struct SearchResult: Identifiable {
    let rank: Int
    let score: Double
    let uuid: String
    let filename: String
    let date: String
    let path: String
    let derivative: String
    let title: String
    let albums: [String]
    let persons: [String]

    var id: String { uuid }
}
