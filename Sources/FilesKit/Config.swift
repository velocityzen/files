import Foundation

/// Configuration loaded from .files configuration files
public struct Config: Sendable {
    public var matchPrecision: Double?
    public var sizeTolerance: Double?
    public var recursive: Bool?
    public var deletions: Bool?
    public var showMoreRight: Bool?
    public var dryRun: Bool?
    public var verbose: Bool?
    public var format: String?
    public var twoWay: Bool?
    public var conflictResolution: String?
    public var noIgnore: Bool?

    /// Creates an empty Config instance with no values set
    public init() {}

    /// Loads config from .files in both left and right directories
    /// Right directory values override left directory values
    public static func load(leftPath: String, rightPath: String) async -> Config {
        let filePaths = [
            URL(fileURLWithPath: leftPath)
                .appendingPathComponent(".files")
                .path(percentEncoded: false),
            URL(fileURLWithPath: rightPath)
                .appendingPathComponent(".files")
                .path(percentEncoded: false),
        ]

        let configs = await withTaskGroup(of: (Int, Config?).self) { group in
            for (index, path) in filePaths.enumerated() {
                group.addTask {
                    let config = await loadFromFile(path)
                    return (index, config)
                }
            }

            var results: [(Int, Config?)] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        let sortedConfigs = configs.sorted { $0.0 < $1.0 }
        var merged = Config()
        for (_, config) in sortedConfigs {
            if let config {
                merged = merged.merged(with: config)
            }
        }

        return merged
    }

    /// Merges this config with another, where the other's non-nil values take precedence
    public func merged(with other: Config) -> Config {
        var result = self
        if let v = other.matchPrecision { result.matchPrecision = v }
        if let v = other.sizeTolerance { result.sizeTolerance = v }
        if let v = other.recursive { result.recursive = v }
        if let v = other.deletions { result.deletions = v }
        if let v = other.showMoreRight { result.showMoreRight = v }
        if let v = other.dryRun { result.dryRun = v }
        if let v = other.verbose { result.verbose = v }
        if let v = other.format { result.format = v }
        if let v = other.twoWay { result.twoWay = v }
        if let v = other.conflictResolution { result.conflictResolution = v }
        if let v = other.noIgnore { result.noIgnore = v }
        return result
    }

    /// Parses a .files configuration file
    @concurrent
    private static func loadFromFile(_ path: String) async -> Config? {
        await Task.detached {
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
                return nil
            }

            var config = Config()

            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
                    continue
                }

                let parts = trimmed.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else {
                    continue
                }

                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts[1].trimmingCharacters(in: .whitespaces)

                switch key {
                    case "matchPrecision":
                        config.matchPrecision = Double(value)
                    case "sizeTolerance":
                        config.sizeTolerance = Double(value)
                    case "recursive":
                        config.recursive = parseBool(value)
                    case "deletions":
                        config.deletions = parseBool(value)
                    case "showMoreRight":
                        config.showMoreRight = parseBool(value)
                    case "dryRun":
                        config.dryRun = parseBool(value)
                    case "verbose":
                        config.verbose = parseBool(value)
                    case "format":
                        config.format = value
                    case "twoWay":
                        config.twoWay = parseBool(value)
                    case "conflictResolution":
                        config.conflictResolution = value
                    case "noIgnore":
                        config.noIgnore = parseBool(value)
                    default:
                        break
                }
            }

            return config
        }.value
    }

    private static func parseBool(_ value: String) -> Bool? {
        switch value.lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return nil
        }
    }
}
