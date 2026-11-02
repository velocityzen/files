import Foundation
import ProgramStatus
import Testing

@testable import files

@Suite("Program status reports")
struct StatusReportTests {
    @Test("Sync reports the route, each file it works on, and how it ended")
    func sync() throws {
        let directory = try TestHelpers.createTestDirectory(files: [
            "src/a.txt": "a", "src/sub/b.txt": "b", "dst/.keep": "",
        ])
        defer { try? FileManager.default.removeItem(at: directory) }

        let dryRun = try TestHelpers.runFiles(["sync", "src", "dst", "--dry-run"], in: directory)
        #expect(
            dryRun.reports == [
                SentStatus("working", "Syncing src → dst"),
                SentStatus("done", "Dry run: 2 operations to sync src → dst"),
            ])

        let sync = try TestHelpers.runFiles(["sync", "src", "dst"], in: directory)
        #expect(sync.status == 0)
        #expect(sync.reports.first == SentStatus("working", "Syncing src → dst"))
        #expect(
            Set(sync.reports.dropFirst().dropLast().compactMap(\.message)) == [
                "Copying a.txt", "Copying sub/b.txt",
            ])
        #expect(sync.reports.last == SentStatus("done", "Synced src → dst: 2 operations"))

        let again = try TestHelpers.runFiles(["sync", "src", "dst"], in: directory)
        #expect(again.reports.last == SentStatus("done", "Nothing to sync: src → dst"))
    }

    @Test("A copy that can't start reports why")
    func copyFailure() throws {
        let directory = try TestHelpers.createTestDirectory(files: ["src/a.txt": "a"])
        defer { try? FileManager.default.removeItem(at: directory) }

        let copy = try TestHelpers.runFiles(["cp", "missing", "src"], in: directory)
        #expect(copy.status == 1)
        #expect(copy.reports.first == SentStatus("working", "Copying missing → src"))
        #expect(copy.reports.last?.state == "error")
        #expect(copy.reports.last?.message?.hasPrefix("Invalid directory: ") == true)
    }

    @Test("Compare reports how many entries differ, or why it failed")
    func compare() throws {
        let directory = try TestHelpers.createTestDirectory(files: [
            "left/same.txt": "same", "left/changed.txt": "old", "left/gone.txt": "gone",
            "right/same.txt": "same", "right/changed.txt": "new and longer",
        ])
        defer { try? FileManager.default.removeItem(at: directory) }

        let compare = try TestHelpers.runFiles(["compare", "left", "right"], in: directory)
        #expect(compare.status == 1)
        #expect(
            compare.reports == [
                SentStatus("working", "Comparing left and right"),
                SentStatus("done", "Compared left and right: 2 differences"),
            ])

        let same = try TestHelpers.runFiles(["compare", "left", "left"], in: directory)
        #expect(same.reports.last == SentStatus("done", "Compared left and left: no differences"))

        let missing = try TestHelpers.runFiles(["compare", "left", "nowhere"], in: directory)
        #expect(missing.status == 2)
        #expect(missing.reports.last?.state == "error")
        #expect(missing.reports.last?.message?.hasPrefix("Invalid directory: ") == true)
    }

    @Test("FILES_STATUS=off sends nothing; unset or empty reports to the terminal")
    func setting() throws {
        let directory = try TestHelpers.createTestDirectory(files: ["a/x.txt": "x"])
        defer { try? FileManager.default.removeItem(at: directory) }

        let off = try TestHelpers.runFiles(
            ["compare", "a", "a"], in: directory, environment: ["FILES_STATUS": "off"])
        #expect(off.status == 0)
        #expect(off.reports.isEmpty)

        #expect(Status.makeReporter("off") == nil)
        for setting in [nil, ""] {
            let reporter = try #require(Status.makeReporter(setting))
            #expect(reporter.app == "files")
            guard case .terminal = reporter.destination else {
                Issue.record(
                    "Expected reports to go to the terminal for \(String(describing: setting))")
                continue
            }
        }
    }
}
