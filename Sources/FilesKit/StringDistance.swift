import Foundation

/// Calculates the Levenshtein distance between two strings
/// - Parameters:
///   - s1: First string
///   - s2: Second string
/// - Returns: The minimum number of single-character edits needed to transform s1 into s2
func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
    let s1Array = Array(s1)
    let s2Array = Array(s2)
    let m = s1Array.count
    let n = s2Array.count

    // Early returns for edge cases
    if m == 0 { return n }
    if n == 0 { return m }

    // Create distance matrix
    var matrix = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

    // Initialize first column and row
    for i in 0...m {
        matrix[i][0] = i
    }
    for j in 0...n {
        matrix[0][j] = j
    }

    // Calculate distances
    for i in 1...m {
        for j in 1...n {
            let cost = s1Array[i - 1] == s2Array[j - 1] ? 0 : 1
            matrix[i][j] = min(
                matrix[i - 1][j] + 1,  // deletion
                matrix[i][j - 1] + 1,  // insertion
                matrix[i - 1][j - 1] + cost  // substitution
            )
        }
    }

    return matrix[m][n]
}

/// Calculates similarity between two strings as a value between 0 and 1
/// - Parameters:
///   - s1: First string
///   - s2: Second string
/// - Returns: Similarity score where 1.0 means identical and 0.0 means completely different
func stringSimilarity(_ s1: String, _ s2: String) -> Double {
    let distance = levenshteinDistance(s1, s2)
    let maxLength = max(s1.count, s2.count)

    if maxLength == 0 {
        return 1.0
    }

    return 1.0 - (Double(distance) / Double(maxLength))
}
