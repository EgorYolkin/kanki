import Foundation

struct StudyStatistics: Decodable {
    struct Day: Decodable {
        let date: String
        let visits: Int
        let reviews: Int
    }

    struct Topic: Decodable {
        let name: String
        let count: Int
    }

    let totalReviews: Int
    let streakDays: Int
    let days: [Day]
    let ratings: [Int]
    let topics: [Topic]
}
