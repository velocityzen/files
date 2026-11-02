import Testing

@testable import FilesKit

@Suite("Track file names")
struct TrackFileNameTests {
    @Test("File names lose reserved characters, edge dots and excess length")
    func sanitizing() {
        #expect(TrackFileName.sanitized("a/b\\c:d*e?f\"g<h>i|j") == "a_b_c_d_e_f_g_h_i_j")
        #expect(TrackFileName.sanitized("tab\there") == "tab_here")
        #expect(TrackFileName.sanitized("  Ends with dots... ") == "Ends with dots")
        #expect(TrackFileName.sanitized("...") == "_")

        let long = TrackFileName.sanitized(String(repeating: "й", count: 200))
        #expect(long.utf8.count <= 240)
        #expect(long.allSatisfy { $0 == "й" })
    }

    @Test("Numbers are padded to two digits, or more for long sheets")
    func numbering() {
        #expect(TrackFileName.numberWidth([1, 9]) == 2)
        #expect(TrackFileName.numberWidth([1, 120]) == 3)
        #expect(TrackFileName.numberWidth([]) == 2)
        #expect(TrackFileName.stem(number: 7, width: 3, performer: nil, title: "T") == "007 - T")
        #expect(
            TrackFileName.make(
                number: 3, width: 2, performer: "A/B", title: nil, extension: "flac")
                == "03 - A_B - Track 03.flac")
    }

    @Test("Repeated names get a suffix, ignoring case, and never collide with a real name")
    func deduplicating() {
        #expect(
            TrackFileName.deduplicated(["a.wav", "A.wav", "a.wav", "b.wav"]) == [
                "a.wav", "A (2).wav", "a (3).wav", "b.wav",
            ])
        // A title that already reads "a (2)" pushes the duplicate on to "(3)"
        #expect(
            TrackFileName.deduplicated(["a (2).wav", "a.wav", "a.wav"]) == [
                "a (2).wav", "a.wav", "a (3).wav",
            ])
    }
}
