import Foundation

/// Calculates the Levenshtein distance between two strings
/// - Parameters:
///   - s1: First string
///   - s2: Second string
/// - Returns: The minimum number of single-character edits needed to transform s1 into s2
func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
    levenshteinDistance(Array(s1), Array(s2))
}

/// The Levenshtein distance between two strings' characters. Fuzzy matching compares every
/// unmatched name with every other, so it splits each name into characters once, and only
/// one row of the distance matrix is kept.
func levenshteinDistance(_ s1: [Character], _ s2: [Character]) -> Int {
    // Early returns for edge cases
    if s1.isEmpty { return s2.count }
    if s2.isEmpty { return s1.count }

    // row[j] is the distance between the first i characters of s1 and the first j of s2
    var row = Array(0...s2.count)
    for i in 1...s1.count {
        // The distance between the first i - 1 and j - 1 characters
        var diagonal = row[0]
        row[0] = i
        for j in 1...s2.count {
            let cost = s1[i - 1] == s2[j - 1] ? 0 : 1
            let substitution = diagonal + cost
            diagonal = row[j]
            row[j] = min(
                row[j] + 1,  // deletion
                row[j - 1] + 1,  // insertion
                substitution
            )
        }
    }

    return row[s2.count]
}

/// Calculates similarity between two strings as a value between 0 and 1
/// - Parameters:
///   - s1: First string
///   - s2: Second string
/// - Returns: Similarity score where 1.0 means identical and 0.0 means completely different
func stringSimilarity(_ s1: String, _ s2: String) -> Double {
    stringSimilarity(Array(s1), Array(s2))
}

/// Similarity between two strings' characters, see `stringSimilarity(_:_:)`
func stringSimilarity(_ s1: [Character], _ s2: [Character]) -> Double {
    let maxLength = max(s1.count, s2.count)

    if maxLength == 0 {
        return 1.0
    }

    return 1.0 - (Double(levenshteinDistance(s1, s2)) / Double(maxLength))
}

/// The most two strings of these lengths can be alike: their distance is at least the
/// difference in length, so a pair below the threshold here can skip computing it
func maximumSimilarity(_ length1: Int, _ length2: Int) -> Double {
    let maxLength = max(length1, length2)
    return maxLength == 0 ? 1.0 : 1.0 - Double(abs(length1 - length2)) / Double(maxLength)
}
