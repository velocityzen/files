import Foundation

/// Represents the differences between two directories
public struct DirectoryDifference: Sendable, Codable {
    public let onlyInLeft: Set<String>
    public let onlyInRight: Set<String>
    public let common: Set<String>

    /// Files that exist in both but have different content
    public let modified: Set<String>

    /// Returns true if there are any differences between the directories
    public var hasDifferences: Bool {
        !onlyInLeft.isEmpty || !onlyInRight.isEmpty || !modified.isEmpty
    }

    // Custom coding keys to maintain JSON compatibility
    private enum CodingKeys: String, CodingKey {
        case onlyInLeft, onlyInRight, common, modified, summary
    }

    // Helper struct for JSON encoding/decoding summary
    private struct Summary: Codable {
        let onlyInLeftCount: Int
        let onlyInRightCount: Int
        let modifiedCount: Int
        let commonCount: Int
        let identical: Bool
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Decode arrays and convert to sets
        let leftArray = try container.decode([String].self, forKey: .onlyInLeft)
        let rightArray = try container.decode([String].self, forKey: .onlyInRight)
        let commonArray = try container.decode([String].self, forKey: .common)
        let modifiedArray = try container.decode([String].self, forKey: .modified)

        self.onlyInLeft = Set(leftArray)
        self.onlyInRight = Set(rightArray)
        self.common = Set(commonArray)
        self.modified = Set(modifiedArray)

        // Summary is optional and we don't need to store it
        _ = try? container.decodeIfPresent(Summary.self, forKey: .summary)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        // Encode sets as sorted arrays
        try container.encode(Array(onlyInLeft).sorted(), forKey: .onlyInLeft)
        try container.encode(Array(onlyInRight).sorted(), forKey: .onlyInRight)
        try container.encode(Array(common).sorted(), forKey: .common)
        try container.encode(Array(modified).sorted(), forKey: .modified)

        // Add summary for better readability
        let summary = Summary(
            onlyInLeftCount: onlyInLeft.count,
            onlyInRightCount: onlyInRight.count,
            modifiedCount: modified.count,
            commonCount: common.count,
            identical: !hasDifferences
        )
        try container.encode(summary, forKey: .summary)
    }

    public init(
        onlyInLeft: Set<String>, onlyInRight: Set<String>, common: Set<String>,
        modified: Set<String>
    ) {
        self.onlyInLeft = onlyInLeft
        self.onlyInRight = onlyInRight
        self.common = common
        self.modified = modified
    }
}

public enum DirectoryDifferenceError: Error, Sendable {
    case invalidDirectory(String)
    case accessDenied(String)
}

/// Specifies what files from the right directory to include in the comparison result
public enum IncludeOnlyInRight: Sendable {
    /// Include all files from the right directory (full comparison)
    case all
    /// Don't include any files only in right (most optimized)
    case none
    /// Include only files in right's leaf directories that match left's leaf directories
    case leafFoldersOnly
}

/// Compares two directories and returns their differences
/// - Parameters:
///   - leftPath: Path to the left directory
///   - rightPath: Path to the right directory
///   - recursive: Whether to compare subdirectories recursively (default: true)
///   - includeOnlyInRight: Specifies what files from the right directory to include (default: .all)
///   - ignore: Optional ignore patterns to skip certain files (default: nil, will auto-load from .filesignore files)
///   - matchPrecision: Similarity threshold for fuzzy file matching (0.0 to 1.0, default: 1.0).
///                     1.0 means exact matches only. Lower values enable fuzzy matching based on Levenshtein distance.
///   - sizeTolerance: Maximum allowed file size difference ratio for fuzzy-matched files (0.0 to 1.0, default: 0.0).
///                    Only applies to fuzzy-matched pairs. 0.0 means exact content comparison.
///                    Higher values allow more size difference (e.g., 0.2 allows 20% size difference).
/// - Returns: A `Result` containing either the `DirectoryDifference` or a `DirectoryDifferenceError`
public func directoryDifference(
    left leftPath: String,
    right rightPath: String,
    recursive: Bool = true,
    includeOnlyInRight: IncludeOnlyInRight = .all,
    ignore: Ignore? = nil,
    matchPrecision: Double = 1.0,
    sizeTolerance: Double = 0.0
) async -> Result<DirectoryDifference, DirectoryDifferenceError> {
    do {
        try validateDirectories(leftPath: leftPath, rightPath: rightPath)
    } catch let error as DirectoryDifferenceError {
        return .failure(error)
    } catch {
        return .failure(.accessDenied("\(error)"))
    }

    // Load ignore patterns
    let patterns =
        if let ignore { ignore } else {
            await Ignore.load(leftPath: leftPath, rightPath: rightPath)
        }

    // Scan left directory and choose comparison strategy
    do {
        let filesLeft = try await scanDirectory(
            at: leftPath,
            recursive: recursive,
            ignore: patterns
        )

        // Choose the appropriate comparison strategy based on includeOnlyInRight mode
        let diff =
            switch includeOnlyInRight {
                case .all:
                    try await fullComparison(
                        leftPath: leftPath,
                        rightPath: rightPath,
                        filesLeft: filesLeft,
                        recursive: recursive,
                        ignore: patterns,
                        matchPrecision: matchPrecision,
                        sizeTolerance: sizeTolerance
                    )
                case .none:
                    try await optimizedComparison(
                        leftPath: leftPath,
                        rightPath: rightPath,
                        filesLeft: filesLeft,
                        matchPrecision: matchPrecision,
                        sizeTolerance: sizeTolerance
                    )
                case .leafFoldersOnly:
                    try await leafFoldersComparison(
                        leftPath: leftPath,
                        rightPath: rightPath,
                        filesLeft: filesLeft,
                        ignore: patterns,
                        matchPrecision: matchPrecision,
                        sizeTolerance: sizeTolerance
                    )
            }
        return .success(diff)
    } catch let error as DirectoryDifferenceError {
        return .failure(error)
    } catch {
        return .failure(.accessDenied("\(error)"))
    }
}

/// Validates that both paths are valid directories
private func validateDirectories(leftPath: String, rightPath: String) throws {
    let fileManager = FileManager.default

    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: leftPath, isDirectory: &isDirectory),
        isDirectory.boolValue
    else {
        throw DirectoryDifferenceError.invalidDirectory(leftPath)
    }

    guard fileManager.fileExists(atPath: rightPath, isDirectory: &isDirectory),
        isDirectory.boolValue
    else {
        throw DirectoryDifferenceError.invalidDirectory(rightPath)
    }
}

/// Full comparison mode: scans both directories completely
@concurrent
private func fullComparison(
    leftPath: String,
    rightPath: String,
    filesLeft: Set<String>,
    recursive: Bool,
    ignore: Ignore,
    matchPrecision: Double,
    sizeTolerance: Double
) async throws -> DirectoryDifference {
    let filesRight = try await scanDirectory(
        at: rightPath, recursive: recursive, ignore: ignore)

    if matchPrecision >= 1.0 {
        return try await exactComparison(
            leftPath: leftPath,
            rightPath: rightPath,
            filesLeft: filesLeft,
            filesRight: filesRight
        )
    }

    return try await fuzzyComparison(
        leftPath: leftPath,
        rightPath: rightPath,
        filesLeft: filesLeft,
        filesRight: filesRight,
        matchPrecision: matchPrecision,
        sizeTolerance: sizeTolerance
    )
}

/// Compares directories using exact filename matching
@concurrent
private func exactComparison(
    leftPath: String,
    rightPath: String,
    filesLeft: Set<String>,
    filesRight: Set<String>
) async throws -> DirectoryDifference {
    let onlyInLeft = filesLeft.subtracting(filesRight)
    let onlyInRight = filesRight.subtracting(filesLeft)
    let common = filesLeft.intersection(filesRight)

    let modified = try await findModifiedFiles(
        common: common,
        leftPath: leftPath,
        rightPath: rightPath
    )

    return DirectoryDifference(
        onlyInLeft: onlyInLeft,
        onlyInRight: onlyInRight,
        common: common.subtracting(modified),
        modified: modified
    )
}

/// Compares directories using fuzzy filename matching for unmatched files
@concurrent
private func fuzzyComparison(
    leftPath: String,
    rightPath: String,
    filesLeft: Set<String>,
    filesRight: Set<String>,
    matchPrecision: Double,
    sizeTolerance: Double
) async throws -> DirectoryDifference {
    let exactCommon = filesLeft.intersection(filesRight)
    let unmatchedLeft = filesLeft.subtracting(filesRight)
    let unmatchedRight = filesRight.subtracting(filesLeft)

    let fuzzyMatches = findFuzzyMatches(
        leftFiles: unmatchedLeft,
        rightFiles: unmatchedRight,
        threshold: matchPrecision
    )

    var common = exactCommon
    var modified = Set<String>()
    var onlyInLeft = unmatchedLeft
    var onlyInRight = unmatchedRight

    let exactModified = try await findModifiedFiles(
        common: exactCommon,
        leftPath: leftPath,
        rightPath: rightPath
    )
    modified.formUnion(exactModified)
    common.subtract(exactModified)

    for (leftFile, rightFile) in fuzzyMatches {
        let leftFullPath = URL(fileURLWithPath: leftPath)
            .appendingPathComponent(leftFile)
            .path(percentEncoded: false)
        let rightFullPath = URL(fileURLWithPath: rightPath)
            .appendingPathComponent(rightFile)
            .path(percentEncoded: false)

        let isDifferent =
            if sizeTolerance > 0 {
                try await !filesAreSimilarSize(
                    leftFullPath, rightFullPath, tolerance: sizeTolerance)
            } else {
                try await filesAreDifferent(leftFullPath, rightFullPath)
            }

        if isDifferent {
            modified.insert(leftFile)
        } else {
            common.insert(leftFile)
        }

        onlyInLeft.remove(leftFile)
        onlyInRight.remove(rightFile)
    }

    return DirectoryDifference(
        onlyInLeft: onlyInLeft,
        onlyInRight: onlyInRight,
        common: common,
        modified: modified
    )
}

/// Optimized comparison mode: only checks if left files exist in right
@concurrent
private func optimizedComparison(
    leftPath: String,
    rightPath: String,
    filesLeft: Set<String>,
    matchPrecision: Double,
    sizeTolerance: Double
) async throws -> DirectoryDifference {
    // If matchPrecision is 1.0, use exact matching
    if matchPrecision >= 1.0 {
        let (common, modified) = try await checkLeftFilesInRight(
            leftFiles: filesLeft,
            leftPath: leftPath,
            rightPath: rightPath
        )

        return DirectoryDifference(
            onlyInLeft: filesLeft.subtracting(common).subtracting(modified),
            onlyInRight: [],
            common: common,
            modified: modified
        )
    }

    // For fuzzy matching in optimized mode, we need to scan the right directory
    // because we don't know which files might be similar
    let ignore = Ignore()
    let filesRight = try await scanDirectory(at: rightPath, recursive: true, ignore: ignore)

    let exactCommon = filesLeft.intersection(filesRight)
    let unmatchedLeft = filesLeft.subtracting(filesRight)
    let unmatchedRight = filesRight.subtracting(filesLeft)

    // Find fuzzy matches
    let fuzzyMatches = findFuzzyMatches(
        leftFiles: unmatchedLeft,
        rightFiles: unmatchedRight,
        threshold: matchPrecision
    )

    // Build sets for the result
    var common = Set<String>()
    var modified = Set<String>()
    var onlyInLeft = unmatchedLeft

    // Check exact matches
    let exactModified = try await findModifiedFiles(
        common: exactCommon,
        leftPath: leftPath,
        rightPath: rightPath
    )
    common.formUnion(exactCommon.subtracting(exactModified))
    modified.formUnion(exactModified)

    // Process fuzzy matches
    for (leftFile, rightFile) in fuzzyMatches {
        let leftFullPath = URL(fileURLWithPath: leftPath)
            .appendingPathComponent(leftFile)
            .path(percentEncoded: false)
        let rightFullPath = URL(fileURLWithPath: rightPath)
            .appendingPathComponent(rightFile)
            .path(percentEncoded: false)

        let isDifferent =
            if sizeTolerance > 0 {
                try await !filesAreSimilarSize(
                    leftFullPath, rightFullPath, tolerance: sizeTolerance)
            } else {
                try await filesAreDifferent(leftFullPath, rightFullPath)
            }

        if isDifferent {
            modified.insert(leftFile)
        } else {
            common.insert(leftFile)
        }

        onlyInLeft.remove(leftFile)
    }

    return DirectoryDifference(
        onlyInLeft: onlyInLeft,
        onlyInRight: [],
        common: common,
        modified: modified
    )
}

/// Leaf folders comparison mode: scans left's leaf directories on the right side
@concurrent
private func leafFoldersComparison(
    leftPath: String,
    rightPath: String,
    filesLeft: Set<String>,
    ignore: Ignore,
    matchPrecision: Double,
    sizeTolerance: Double
) async throws -> DirectoryDifference {
    // Derive leaf directories from the files we already scanned
    let leftLeafDirs = findLeafDirectoriesFromFiles(filesLeft)
    let filesInRightLeaves = try await scanLeafDirectories(
        at: rightPath,
        leafDirs: leftLeafDirs,
        ignore: ignore
    )

    // If matchPrecision is 1.0, use exact matching
    if matchPrecision >= 1.0 {
        // First, do the optimized check for all left files
        let (common, modified) = try await checkLeftFilesInRight(
            leftFiles: filesLeft,
            leftPath: leftPath,
            rightPath: rightPath
        )

        // Calculate what's only in right (within left's leaf directories)
        let onlyInRightLeaves = filesInRightLeaves.subtracting(filesLeft)

        // For files in both, check if they're modified (but only within left's leaf dirs)
        let commonInLeaves = filesInRightLeaves.intersection(filesLeft)
        let modifiedInLeaves = try await findModifiedFiles(
            common: commonInLeaves,
            leftPath: leftPath,
            rightPath: rightPath
        )

        return DirectoryDifference(
            onlyInLeft: filesLeft.subtracting(common).subtracting(modified),
            onlyInRight: onlyInRightLeaves,
            common: common.union(commonInLeaves.subtracting(modifiedInLeaves)),
            modified: modified.union(modifiedInLeaves)
        )
    }

    // Use fuzzy matching
    let exactCommon = filesLeft.intersection(filesInRightLeaves)
    let unmatchedLeft = filesLeft.subtracting(filesInRightLeaves)
    let unmatchedRight = filesInRightLeaves.subtracting(filesLeft)

    // Find fuzzy matches
    let fuzzyMatches = findFuzzyMatches(
        leftFiles: unmatchedLeft,
        rightFiles: unmatchedRight,
        threshold: matchPrecision
    )

    // Build sets for the result
    var common = Set<String>()
    var modified = Set<String>()
    var onlyInLeft = unmatchedLeft
    var onlyInRight = unmatchedRight

    // Check exact matches
    let exactModified = try await findModifiedFiles(
        common: exactCommon,
        leftPath: leftPath,
        rightPath: rightPath
    )
    common.formUnion(exactCommon.subtracting(exactModified))
    modified.formUnion(exactModified)

    // Process fuzzy matches
    for (leftFile, rightFile) in fuzzyMatches {
        let leftFullPath = URL(fileURLWithPath: leftPath)
            .appendingPathComponent(leftFile)
            .path(percentEncoded: false)
        let rightFullPath = URL(fileURLWithPath: rightPath)
            .appendingPathComponent(rightFile)
            .path(percentEncoded: false)

        let isDifferent =
            if sizeTolerance > 0 {
                try await !filesAreSimilarSize(
                    leftFullPath, rightFullPath, tolerance: sizeTolerance)
            } else {
                try await filesAreDifferent(leftFullPath, rightFullPath)
            }

        if isDifferent {
            modified.insert(leftFile)
        } else {
            common.insert(leftFile)
        }

        onlyInLeft.remove(leftFile)
        onlyInRight.remove(rightFile)
    }

    return DirectoryDifference(
        onlyInLeft: onlyInLeft,
        onlyInRight: onlyInRight,
        common: common,
        modified: modified
    )
}

/// Checks which files from left exist in right and which are modified
/// This is an optimization that avoids scanning the entire right directory
@concurrent
private func checkLeftFilesInRight(
    leftFiles: Set<String>,
    leftPath: String,
    rightPath: String
) async throws -> (common: Set<String>, modified: Set<String>) {
    try await withThrowingTaskGroup(of: (String, FileStatus).self) { group in
        for relativePath in leftFiles {
            group.addTask {
                let fileLeft = URL(fileURLWithPath: leftPath)
                    .appendingPathComponent(relativePath)
                    .path(percentEncoded: false)
                let fileRight = URL(fileURLWithPath: rightPath)
                    .appendingPathComponent(relativePath)
                    .path(percentEncoded: false)

                let fileManager = FileManager.default
                guard fileManager.fileExists(atPath: fileRight) else {
                    return (relativePath, .onlyInLeft)
                }

                let isDifferent = try await filesAreDifferent(fileLeft, fileRight)
                return (relativePath, isDifferent ? .modified : .same)
            }
        }

        var common = Set<String>()
        var modified = Set<String>()

        for try await (file, status) in group {
            switch status {
                case .same:
                    common.insert(file)
                case .modified:
                    modified.insert(file)
                case .onlyInLeft:
                    break  // Will be in onlyInLeft by subtraction
            }
        }

        return (common, modified)
    }
}

private enum FileStatus {
    case same
    case modified
    case onlyInLeft
}

/// Derives leaf directories from a set of file paths
/// A leaf directory is one that contains files but has no subdirectories
private func findLeafDirectoriesFromFiles(_ files: Set<String>) -> Set<String> {
    var allDirectories = Set<String>()
    var directoriesWithSubdirs = Set<String>()

    // Extract all directories from file paths
    for filePath in files {
        let components = (filePath as NSString).pathComponents

        // Build directory path incrementally
        for i in 0..<(components.count - 1) {  // Exclude the file name
            let dirPath = components[0...i].joined(separator: "/")
            if !dirPath.isEmpty && dirPath != "." {
                allDirectories.insert(dirPath)

                // Mark parent directories as having subdirectories
                if i > 0 {
                    let parentPath = components[0..<i].joined(separator: "/")
                    if !parentPath.isEmpty && parentPath != "." {
                        directoriesWithSubdirs.insert(parentPath)
                    }
                }
            }
        }
    }

    // Leaf directories are those without subdirectories
    return allDirectories.subtracting(directoriesWithSubdirs)
}

/// Scans only files within specified leaf directories
@concurrent
private func scanLeafDirectories(
    at path: String,
    leafDirs: Set<String>,
    ignore: Ignore
) async throws -> Set<String> {
    try await Task.detached {
        let fileManager = FileManager.default
        let baseURL = URL(fileURLWithPath: path)

        var files = Set<String>()

        // Standardize base path
        let standardizedBase = baseURL.standardizedFileURL
        var standardizedBasePath = standardizedBase.path(percentEncoded: false)
        if standardizedBasePath.hasSuffix("/") {
            standardizedBasePath = String(standardizedBasePath.dropLast())
        }

        // Scan each leaf directory
        for leafDir in leafDirs {
            let leafURL = baseURL.appendingPathComponent(leafDir)

            guard
                let enumerator = fileManager.enumerator(
                    at: leafURL,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsSubdirectoryDescendants]
                )
            else {
                continue
            }

            for case let fileURL as URL in enumerator.allObjects {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
                let isDirectory = resourceValues.isDirectory == true

                if !isDirectory {
                    let standardizedFile = fileURL.standardizedFileURL
                    var filePath = standardizedFile.path(percentEncoded: false)

                    if filePath.hasSuffix("/") {
                        filePath = String(filePath.dropLast())
                    }

                    // Get relative path from base
                    let relativePath: String
                    if filePath.hasPrefix(standardizedBasePath + "/") {
                        relativePath = String(filePath.dropFirst(standardizedBasePath.count + 1))
                    } else {
                        relativePath = fileURL.lastPathComponent
                    }

                    if !ignore.shouldIgnore(relativePath, isDirectory: false) {
                        files.insert(relativePath)
                    }
                }
            }
        }

        return files
    }.value
}

/// Scans a directory and returns relative paths of all files
@concurrent
private func scanDirectory(at path: String, recursive: Bool, ignore: Ignore)
    async throws -> Set<String>
{
    let baseURL = URL(fileURLWithPath: path)

    return try await Task.detached {
        let fileManager = FileManager.default

        guard
            let enumerator = fileManager.enumerator(
                at: baseURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: recursive ? [] : [.skipsSubdirectoryDescendants]
            )
        else {
            throw DirectoryDifferenceError.accessDenied(path)
        }

        var files = Set<String>()
        let allObjects = enumerator.allObjects

        // Standardize URLs to resolve symlinks and remove trailing slash
        let standardizedBase = baseURL.standardizedFileURL
        var standardizedBasePath = standardizedBase.path(percentEncoded: false)
        if standardizedBasePath.hasSuffix("/") {
            standardizedBasePath = String(standardizedBasePath.dropLast())
        }

        for case let fileURL as URL in allObjects {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
            let isDirectory = resourceValues.isDirectory == true

            if !isDirectory {
                let standardizedFile = fileURL.standardizedFileURL
                var filePath = standardizedFile.path(percentEncoded: false)

                // Remove trailing slash if present
                if filePath.hasSuffix("/") {
                    filePath = String(filePath.dropLast())
                }

                // Remove base path to get relative path
                let relativePath: String
                if filePath.hasPrefix(standardizedBasePath + "/") {
                    relativePath = String(filePath.dropFirst(standardizedBasePath.count + 1))
                } else {
                    relativePath = fileURL.lastPathComponent
                }

                // Check if file should be ignored
                if !ignore.shouldIgnore(relativePath, isDirectory: false) {
                    files.insert(relativePath)
                }
            }
        }

        return files
    }.value
}

/// Finds files that exist in both directories but have different content
@concurrent
private func findModifiedFiles(
    common: Set<String>,
    leftPath: String,
    rightPath: String
) async throws -> Set<String> {
    try await withThrowingTaskGroup(of: String?.self) { group in
        for relativePath in common {
            group.addTask {
                let fileLeft = URL(fileURLWithPath: leftPath)
                    .appendingPathComponent(relativePath)
                    .path(percentEncoded: false)
                let fileRight = URL(fileURLWithPath: rightPath)
                    .appendingPathComponent(relativePath)
                    .path(percentEncoded: false)

                return try await filesAreDifferent(fileLeft, fileRight) ? relativePath : nil
            }
        }

        var modified = Set<String>()
        for try await modifiedFile in group {
            if let file = modifiedFile {
                modified.insert(file)
            }
        }
        return modified
    }
}

/// Compares two files to determine if they have different content
@concurrent
private func filesAreDifferent(_ path1: String, _ path2: String) async throws -> Bool {
    try await Task.detached {
        let fileManager = FileManager.default

        // First compare file sizes for quick check
        let attrs1 = try fileManager.attributesOfItem(atPath: path1)
        let attrs2 = try fileManager.attributesOfItem(atPath: path2)

        if let size1 = attrs1[.size] as? Int64, let size2 = attrs2[.size] as? Int64 {
            if size1 != size2 {
                return true
            }
        }

        // If sizes match, compare content
        guard let data1 = fileManager.contents(atPath: path1),
            let data2 = fileManager.contents(atPath: path2)
        else {
            throw DirectoryDifferenceError.accessDenied("Could not read file contents")
        }

        return data1 != data2
    }.value
}

/// Compares two files to determine if they have similar sizes within a tolerance
@concurrent
private func filesAreSimilarSize(
    _ left: String,
    _ right: String,
    tolerance: Double
) async throws -> Bool {
    try await Task.detached {
        let fileManager = FileManager.default

        let leftAttrs = try fileManager.attributesOfItem(atPath: left)
        let rightAttrs = try fileManager.attributesOfItem(atPath: right)

        guard let leftSize = leftAttrs[.size] as? Int64,
            let rightSize = rightAttrs[.size] as? Int64
        else {
            return false
        }

        if leftSize == 0 && rightSize == 0 {
            return true
        }

        let minSize = min(leftSize, rightSize)
        let allowedDifference = Double(minSize) * tolerance
        let actualDifference = abs(Double(leftSize) - Double(rightSize))

        return actualDifference <= allowedDifference
    }.value
}

// MARK: - JSON Comparison

/// Compares two JSON comparison result files and returns their differences
/// - Parameters:
///   - leftPath: Path to the left JSON file
///   - rightPath: Path to the right JSON file
/// - Returns: A `DirectoryDifference` representing the differences between the two comparison results
/// - Throws: `DirectoryDifferenceError` if files are invalid or inaccessible
public func compareSnapshots(
    left leftPath: String,
    right rightPath: String
) async throws -> DirectoryDifference {
    // Load both JSON files concurrently
    async let leftDiff = try loadJSONFile(at: leftPath)
    async let rightDiff = try loadJSONFile(at: rightPath)

    // Wait for both to complete and compare
    return try await compareDirectoryDifferences(left: leftDiff, right: rightDiff)
}

/// Loads and decodes a JSON file into a DirectoryDifference
/// - Parameter path: Path to the JSON file
/// - Returns: A decoded `DirectoryDifference`
/// - Throws: `DirectoryDifferenceError` if file is invalid or inaccessible
@concurrent
private func loadJSONFile(at path: String) async throws -> DirectoryDifference {
    try await Task.detached {
        let fileManager = FileManager.default

        // Validate that file exists
        guard fileManager.fileExists(atPath: path) else {
            throw DirectoryDifferenceError.invalidDirectory(path)
        }

        // Read file
        guard let data = fileManager.contents(atPath: path) else {
            throw DirectoryDifferenceError.accessDenied("Could not read \(path)")
        }

        // Decode JSON
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(DirectoryDifference.self, from: data)
        } catch {
            throw DirectoryDifferenceError.accessDenied(
                "Could not decode JSON from \(path): \(error)")
        }
    }.value
}

/// Compares two DirectoryDifference structures to find meta-differences
/// This shows what files changed status between two comparison snapshots
private func compareDirectoryDifferences(
    left: DirectoryDifference,
    right: DirectoryDifference
) -> DirectoryDifference {
    // Collect all files from both comparisons
    let leftAllFiles = left.onlyInLeft
        .union(left.onlyInRight)
        .union(left.common)
        .union(left.modified)

    let rightAllFiles = right.onlyInLeft
        .union(right.onlyInRight)
        .union(right.common)
        .union(right.modified)

    // Files that exist in left comparison but not in right
    let onlyInLeft = leftAllFiles.subtracting(rightAllFiles)

    // Files that exist in right comparison but not in left
    let onlyInRight = rightAllFiles.subtracting(leftAllFiles)

    // Files in both comparisons
    let commonFiles = leftAllFiles.intersection(rightAllFiles)

    // Find files that changed status between comparisons
    var modified = Set<String>()
    var unchanged = Set<String>()

    for file in commonFiles {
        let leftStatus = getFileStatus(in: left, file: file)
        let rightStatus = getFileStatus(in: right, file: file)

        if leftStatus != rightStatus {
            modified.insert(file)
        } else {
            unchanged.insert(file)
        }
    }

    return DirectoryDifference(
        onlyInLeft: onlyInLeft,
        onlyInRight: onlyInRight,
        common: unchanged,
        modified: modified
    )
}

/// Helper to determine the status of a file in a DirectoryDifference
private func getFileStatus(in diff: DirectoryDifference, file: String) -> String {
    if diff.onlyInLeft.contains(file) {
        return "onlyInLeft"
    } else if diff.onlyInRight.contains(file) {
        return "onlyInRight"
    } else if diff.modified.contains(file) {
        return "modified"
    } else if diff.common.contains(file) {
        return "common"
    }
    return "unknown"
}

// MARK: - Fuzzy Matching

/// Finds fuzzy matches between two sets of files based on name similarity
/// - Parameters:
///   - leftFiles: Files from the left directory
///   - rightFiles: Files from the right directory
///   - threshold: Minimum similarity threshold (0.0 to 1.0)
/// - Returns: A dictionary mapping left files to their best matching right files
internal func findFuzzyMatches(
    leftFiles: Set<String>,
    rightFiles: Set<String>,
    threshold: Double
) -> [String: String] {
    var matches: [String: String] = [:]
    var usedRightFiles = Set<String>()

    // For each left file, find the best matching right file
    for leftFile in leftFiles {
        let leftName = URL(fileURLWithPath: leftFile).lastPathComponent
        var bestMatch: (rightFile: String, similarity: Double)?

        for rightFile in rightFiles {
            // Skip already matched files
            if usedRightFiles.contains(rightFile) {
                continue
            }

            let rightName = URL(fileURLWithPath: rightFile).lastPathComponent
            let similarity = stringSimilarity(leftName, rightName)

            // Update best match if this is better and meets threshold
            if similarity >= threshold {
                if let current = bestMatch {
                    if similarity > current.similarity {
                        bestMatch = (rightFile, similarity)
                    }
                } else {
                    bestMatch = (rightFile, similarity)
                }
            }
        }

        // Record the match if found
        if let match = bestMatch {
            matches[leftFile] = match.rightFile
            usedRightFiles.insert(match.rightFile)
        }
    }

    return matches
}
