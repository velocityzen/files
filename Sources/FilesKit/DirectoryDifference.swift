import Foundation

/// Represents the differences between two directories
public struct DirectoryDifference: Sendable {
    public let onlyInLeft: Set<String>
    public let onlyInRight: Set<String>
    public let common: Set<String>

    /// Files that exist in both but have different content
    public let modified: Set<String>

    /// Returns true if there are any differences between the directories
    public var hasDifferences: Bool {
        !onlyInLeft.isEmpty || !onlyInRight.isEmpty || !modified.isEmpty
    }
}

public enum DirectoryDifferenceError: Error, Sendable {
    case invalidDirectory(String)
    case accessDenied(String)
}

/// Compares two directories and returns their differences
/// - Parameters:
///   - leftPath: Path to the left directory
///   - rightPath: Path to the right directory
///   - recursive: Whether to compare subdirectories recursively (default: true)
///   - includeOnlyInRight: If true, includes files only in right directory in the result (default: true). Set to false for optimization when you don't need to know about right-only files.
/// - Returns: A `DirectoryDifference` containing the differences between the directories
/// - Throws: `DirectoryDifferenceError` if directories are invalid or inaccessible
public func directoryDifference(
    left leftPath: String,
    right rightPath: String,
    recursive: Bool = true,
    includeOnlyInRight: Bool = true
) async throws -> DirectoryDifference {
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

    let filesLeft = try await scanDirectory(at: leftPath, recursive: recursive)

    if !includeOnlyInRight {
        // Optimized path: only check if left files exist in right
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

    // Full scan: compare both directories
    let filesRight = try await scanDirectory(at: rightPath, recursive: recursive)

    let onlyInLeft = filesLeft.subtracting(filesRight)
    let onlyInRight = filesRight.subtracting(filesLeft)
    let common = filesLeft.intersection(filesRight)

    // Check for modified files in common set
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

/// Checks which files from left exist in right and which are modified
/// This is an optimization that avoids scanning the entire right directory
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

/// Scans a directory and returns relative paths of all files
private func scanDirectory(at path: String, recursive: Bool) async throws -> Set<String> {
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
            if resourceValues.isDirectory != true {
                let standardizedFile = fileURL.standardizedFileURL
                var filePath = standardizedFile.path(percentEncoded: false)

                // Remove trailing slash if present
                if filePath.hasSuffix("/") {
                    filePath = String(filePath.dropLast())
                }

                // Remove base path to get relative path
                if filePath.hasPrefix(standardizedBasePath + "/") {
                    let relativePath = String(filePath.dropFirst(standardizedBasePath.count + 1))
                    files.insert(relativePath)
                } else {
                    files.insert(fileURL.lastPathComponent)
                }
            }
        }

        return files
    }.value
}

/// Finds files that exist in both directories but have different content
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
