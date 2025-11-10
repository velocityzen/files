import Foundation

/// Manages file ignore patterns similar to .gitignore
public struct Ignore: Sendable {
    private let patterns: [Pattern]

    private struct Pattern: Sendable {
        let original: String
        let isNegation: Bool
        let isDirectoryOnly: Bool
        let regex: NSRegularExpression

        init?(line: String) {
            var trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and comments
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
                return nil
            }

            // Check for negation
            let isNegation = trimmed.hasPrefix("!")
            if isNegation {
                trimmed = String(trimmed.dropFirst())
            }

            // Check if pattern is directory-only
            let isDirectoryOnly = trimmed.hasSuffix("/")
            if isDirectoryOnly {
                trimmed = String(trimmed.dropLast())
            }

            self.original = line
            self.isNegation = isNegation
            self.isDirectoryOnly = isDirectoryOnly

            // Convert glob pattern to regex
            let regexPattern = Self.globToRegex(trimmed)
            guard let regex = try? NSRegularExpression(pattern: regexPattern, options: []) else {
                return nil
            }

            self.regex = regex
        }

        /// Converts a glob pattern to a regular expression pattern
        private static func globToRegex(_ glob: String) -> String {
            var pattern = ""
            var i = glob.startIndex

            // If pattern starts with /, it's relative to root
            let isRooted = glob.hasPrefix("/")
            if isRooted {
                i = glob.index(after: i)
                pattern = "^"
            }

            while i < glob.endIndex {
                let char = glob[i]

                switch char {
                    case "*":
                        // Check for ** (matches any number of directories)
                        let nextIndex = glob.index(after: i)
                        if nextIndex < glob.endIndex && glob[nextIndex] == "*" {
                            // ** followed by / or at the end
                            let afterNext = glob.index(after: nextIndex)
                            if afterNext < glob.endIndex && glob[afterNext] == "/" {
                                // **/ matches zero or more directories
                                pattern += "(.*/|)"
                                i = afterNext
                            } else if afterNext >= glob.endIndex {
                                // ** at the end matches everything
                                pattern += ".*"
                                i = nextIndex
                            } else {
                                // ** not followed by /, treat as *
                                pattern += "[^/]*"
                            }
                        } else {
                            // Single * matches anything except /
                            pattern += "[^/]*"
                        }

                    case "?":
                        pattern += "[^/]"

                    case ".":
                        pattern += "\\."

                    case "\\":
                        // Escape character
                        i = glob.index(after: i)
                        if i < glob.endIndex {
                            pattern += NSRegularExpression.escapedPattern(for: String(glob[i]))
                        }

                    default:
                        if char.isLetter || char.isNumber || char == "/" || char == "-"
                            || char == "_"
                        {
                            pattern.append(char)
                        } else {
                            pattern += NSRegularExpression.escapedPattern(for: String(char))
                        }
                }

                i = glob.index(after: i)
            }

            // If pattern doesn't start with ^, it can match anywhere in the path
            if !isRooted {
                pattern = "(^|/)" + pattern
            }

            // Pattern can match at the end or before a /
            pattern += "($|/)"

            return pattern
        }

        func matches(_ path: String, isDirectory: Bool) -> Bool {
            // If pattern is directory-only and path is not a directory, skip
            if isDirectoryOnly && !isDirectory {
                return false
            }

            let range = NSRange(location: 0, length: path.utf16.count)
            return regex.firstMatch(in: path, options: [], range: range) != nil
        }
    }

    /// Creates an empty Ignore instance
    public init() {
        self.patterns = []
    }

    /// Creates an Ignore instance from an array of pattern strings
    public init(patterns: [String]) {
        // Always include default patterns to ignore .filesignore files
        let defaultPatterns = [".filesignore"]
        let allPatterns = defaultPatterns + patterns
        self.patterns = allPatterns.compactMap { Pattern(line: $0) }
    }

    /// Loads ignore patterns from .filesignore files from home directory and left and right directories
    public static func load(leftPath: String, rightPath: String) async -> Ignore {
        var filePaths: [String] = []

        if let homeDir = FileManager.default.homeDirectoryForCurrentUser.path(
            percentEncoded: false) as String?
        {
            let homePath = URL(fileURLWithPath: homeDir)
                .appendingPathComponent(".filesignore")
                .path(percentEncoded: false)
            filePaths.append(homePath)
        }

        filePaths.append(
            URL(fileURLWithPath: leftPath)
                .appendingPathComponent(".filesignore")
                .path(percentEncoded: false)
        )

        filePaths.append(
            URL(fileURLWithPath: rightPath)
                .appendingPathComponent(".filesignore")
                .path(percentEncoded: false)
        )

        // Load all files in parallel
        let allPatternArrays = await withTaskGroup(of: (Int, [String]).self) { group in
            for (index, path) in filePaths.enumerated() {
                group.addTask {
                    let patterns = await loadPatternsFromFile(path) ?? []
                    return (index, patterns)
                }
            }

            var results: [(Int, [String])] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        let sortedResults = allPatternArrays.sorted { $0.0 < $1.0 }
        let allPatterns = sortedResults.flatMap { $0.1 }

        return Ignore(patterns: allPatterns)
    }

    /// Loads patterns from a .filesignore file asynchronously
    @concurrent
    private static func loadPatternsFromFile(_ path: String) async -> [String]? {
        await Task.detached {
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
                return nil
            }
            return content.components(separatedBy: .newlines)
        }.value
    }

    /// Checks if a file should be ignored
    public func shouldIgnore(_ relativePath: String, isDirectory: Bool = false) -> Bool {
        var ignored = false

        for pattern in patterns {
            if pattern.matches(relativePath, isDirectory: isDirectory) {
                ignored = !pattern.isNegation
            }
        }

        return ignored
    }
}
