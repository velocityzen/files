import ArgumentParser

enum OutputFormat: String, ExpressibleByArgument {
    case text
    case json
    case summary
}
