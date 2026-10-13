import XCTest
@testable import PSRCore

final class USRFileTests: XCTestCase {
    static let examples = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Examples")

    func exampleData(_ n: Int) throws -> Data {
        try Data(contentsOf: Self.examples.appendingPathComponent("USER00\(n).USR"))
    }

    func testRoundTripIsByteIdentical() throws {
        for n in 1...2 {
            let raw = try exampleData(n)
            let file = try USRFile(data: raw)
            XCTAssertTrue(file.checksumIsValid, "checksum of USER00\(n)")
            XCTAssertEqual(file.serialized(), raw, "USER00\(n) must re-serialize identically")
        }
    }

    func testChecksumTracksContent() throws {
        var file = try USRFile(data: exampleData(1))
        let before = file.computedChecksum
        file.patches[5][20] &+= 1
        XCTAssertEqual(file.computedChecksum, (before + 1) & 0xFF)
    }

    func testSlotLayoutMatchesKnownSlots() throws {
        // Confirmed against the keyboard: Bank 1/Mem 1 = 0, Bank 2/Mem 1 = 1, Bank 3/Mem 2 = 10.
        XCTAssertEqual(SlotLayout.position(bank: 1, memory: 1), 0)
        XCTAssertEqual(SlotLayout.position(bank: 2, memory: 1), 1)
        XCTAssertEqual(SlotLayout.position(bank: 3, memory: 2), 10)
        let file = try USRFile(data: exampleData(1))
        let b1m1 = PatchInfo(record: file.patches[0])
        XCTAssertEqual(b1m1.mainVoice, 102)
        XCTAssertFalse(b1m1.splitOn); XCTAssertFalse(b1m1.dualOn)
        XCTAssertEqual(b1m1.splitPoint, 54)
        let b2m1 = PatchInfo(record: file.patches[1])
        XCTAssertEqual(b2m1.mainVoice, 129)
        XCTAssertTrue(b2m1.splitOn); XCTAssertTrue(b2m1.dualOn)
        XCTAssertEqual(b2m1.dualVoice, 127)
        let b3m2 = PatchInfo(record: file.patches[10])
        XCTAssertEqual(b3m2.mainVoice, 1)
        XCTAssertEqual(b3m2.splitPoint, 62)
        XCTAssertTrue(b3m2.splitOn); XCTAssertFalse(b3m2.dualOn)
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try USRFile(data: Data(repeating: 0, count: 100)))
        XCTAssertThrowsError(try USRFile(data: Data(repeating: 0, count: USRFile.fileSize)))
    }

    func testVoiceNames() {
        XCTAssertEqual(VoiceCatalog.name(for: 102), "Overdriven Guitar")
        XCTAssertEqual(VoiceCatalog.name(for: 1), "Live! Concert Grand Piano")
    }

    @MainActor
    func testImportThenRebuildReproducesFile() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("psr-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = LibraryStore(root: tmp)
        let url = Self.examples.appendingPathComponent("USER002.USR")
        let plan = try store.makeImportPlan(from: url)
        XCTAssertEqual(plan.knownCount, 0)
        let names = Dictionary(uniqueKeysWithValues: plan.newSlots.map { ($0.position, $0.info.suggestedName) })
        let set = try XCTUnwrap(store.commit(plan, names: names, setlistName: "Test"))
        XCTAssertTrue(set.isComplete)
        let out = tmp.appendingPathComponent("out.USR")
        try store.export(setlistID: set.id, to: out)
        XCTAssertEqual(try Data(contentsOf: out), try Data(contentsOf: url))

        // Importing the same file again finds everything already in the library.
        let again = try store.makeImportPlan(from: url)
        XCTAssertEqual(again.newSlots.count, 0)
        XCTAssertEqual(again.knownCount, 32)

        // A reloaded library sees the same content.
        let reloaded = LibraryStore(root: tmp)
        XCTAssertEqual(reloaded.patches.count, store.patches.count)
        XCTAssertEqual(reloaded.setlists.first?.slots, set.slots)
    }
}

@MainActor
final class LibraryFeatureTests: XCTestCase {
    func makeStore() -> (LibraryStore, URL) {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("psr-test-\(UUID().uuidString)")
        return (LibraryStore(root: tmp), tmp)
    }
    func testBankLabelIsRestoredWhenSameBankIsImportedAgain() throws {
        let (store, tmp) = makeStore()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let plan = try store.makeImportPlan(from: usr2)
        let names = Dictionary(uniqueKeysWithValues: plan.newSlots.map { ($0.position, $0.info.suggestedName) })
        let first = try XCTUnwrap(store.commit(plan, names: names, setlistName: "First"))
        XCTAssertEqual(first.bankDescriptions, Array(repeating: "", count: 8))
        store.setBankDescription("Salsa", bank: 2, in: first.id)

        // Even after the labelled setlist is gone, importing the same bank brings the label back.
        store.deleteSetlist(first.id)
        let second = try XCTUnwrap(store.commit(try store.makeImportPlan(from: usr2), names: [:], setlistName: "Second"))
        XCTAssertEqual(second.bankDescriptions[1], "Salsa")
        XCTAssertEqual(second.bankDescriptions.filter { !$0.isEmpty }.count, 1)
        XCTAssertEqual(LibraryStore(root: tmp).setlist(second.id)?.bankDescriptions[1], "Salsa")

        // Clearing the label forgets it.
        store.setBankDescription("", bank: 2, in: second.id)
        let third = try XCTUnwrap(store.commit(try store.makeImportPlan(from: usr2), names: [:], setlistName: "Third"))
        XCTAssertEqual(third.bankDescriptions[1], "")
    }

    var usr2: URL { USRFileTests.examples.appendingPathComponent("USER002.USR") }

    func testRenameDoesNotAffectDuplicateDetection() throws {
        let (store, tmp) = makeStore(); defer { try? FileManager.default.removeItem(at: tmp) }
        let plan = try store.makeImportPlan(from: usr2)
        let names = Dictionary(uniqueKeysWithValues: plan.newSlots.map { ($0.position, "x\($0.position)") })
        store.commit(plan, names: names, setlistName: nil)
        let victim = try XCTUnwrap(store.patches.first)
        store.renamePatch(victim.id, to: "Totally different name")
        XCTAssertEqual(store.patch(victim.id)?.name, "Totally different name")
        XCTAssertEqual(store.patch(victim.id)?.meta.hash, victim.meta.hash)
        // Same bytes under a new name are still recognised and not added again.
        let again = try store.makeImportPlan(from: usr2)
        XCTAssertEqual(again.newSlots.count, 0)
        XCTAssertEqual(store.addPatch(record: victim.data, name: "Another name", source: nil).id, victim.id)
        // The rename is persisted and the setlist still points at the same patch.
        XCTAssertEqual(LibraryStore(root: tmp).patch(victim.id)?.name, "Totally different name")
    }

    func testTagsPersistFilterAndCount() throws {
        let (store, tmp) = makeStore(); defer { try? FileManager.default.removeItem(at: tmp) }
        let plan = try store.makeImportPlan(from: usr2)
        let set = try XCTUnwrap(store.commit(plan, names: Dictionary(uniqueKeysWithValues: plan.newSlots.map { ($0.position, $0.info.suggestedName) }), setlistName: "Gig"))
        let p = try XCTUnwrap(store.patches.first)
        store.setTags(["Rock", " #rock ", "slow ballad", ""], forPatch: p.id)
        store.setTags(["Rock", "Sunday"], forSetlist: set.id)
        XCTAssertEqual(store.patch(p.id)?.meta.tags, ["Rock", "slow ballad"])
        let counts = store.tagCounts
        XCTAssertEqual(counts.first { $0.id == "rock" }?.total, 2)
        XCTAssertTrue(try XCTUnwrap(store.patch(p.id)).matches(search: "", tags: ["ROCK"]))
        XCTAssertFalse(try XCTUnwrap(store.patch(p.id)).matches(search: "", tags: ["rock", "jazz"]))
        XCTAssertTrue(try XCTUnwrap(store.patch(p.id)).matches(search: "ballad", tags: []))   // tag text is searchable
        XCTAssertTrue(try XCTUnwrap(store.setlist(set.id)).matches(search: "sunday"))
        let again = LibraryStore(root: tmp)
        XCTAssertEqual(again.patch(p.id)?.meta.tags, ["Rock", "slow ballad"])
        XCTAssertEqual(again.setlist(set.id)?.tags, ["Rock", "Sunday"])
        XCTAssertEqual(Tags.parse("a, B ;#a\nc d"), ["a", "B", "c d"])
    }

    func testLibraryWithoutTagsStillLoads() throws {
        let (store, tmp) = makeStore(); defer { try? FileManager.default.removeItem(at: tmp) }
        let rec = try USRFile(data: Data(contentsOf: usr2)).patches[0]
        let p = store.addPatch(record: rec, name: "Old", source: nil)
        // Simulate a v1 meta.json: no "tags" key.
        let metaURL = tmp.appendingPathComponent("Patches/\(p.id.uuidString).patch/meta.json")
        var obj = try JSONSerialization.jsonObject(with: Data(contentsOf: metaURL)) as! [String: Any]
        obj.removeValue(forKey: "tags")
        try JSONSerialization.data(withJSONObject: obj).write(to: metaURL)
        XCTAssertEqual(LibraryStore(root: tmp).patch(p.id)?.meta.tags, [])
    }

    func testDragApply() throws {
        let (store, tmp) = makeStore(); defer { try? FileManager.default.removeItem(at: tmp) }
        let recs = try USRFile(data: Data(contentsOf: usr2)).patches
        let a = store.addPatch(record: recs[0], name: "A", source: nil), b = store.addPatch(record: recs[1], name: "B", source: nil)
        let s = store.createSetlist(name: "S")
        XCTAssertEqual(DragItem(payload: DragItem.patch(a.id).payload), .patch(a.id))
        XCTAssertEqual(DragItem(payload: DragItem.slot(7).payload), .slot(7))
        XCTAssertNil(DragItem(payload: "hello"))
        XCTAssertTrue(store.apply(.patch(a.id), to: 3, in: s.id))
        XCTAssertTrue(store.apply(.patch(b.id), to: 4, in: s.id))
        XCTAssertEqual(store.setlist(s.id)?.slots[3], a.id)
        XCTAssertTrue(store.apply(.slot(3), to: 4, in: s.id))   // swap
        XCTAssertEqual(store.setlist(s.id)?.slots[3], b.id)
        XCTAssertEqual(store.setlist(s.id)?.slots[4], a.id)
        XCTAssertFalse(store.apply(.patch(UUID()), to: 0, in: s.id))
    }
}

@MainActor
final class LibraryResilienceTests: XCTestCase {
    func testDamagedAndPartiallyDeletedLibraryStillLoads() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("psr-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = LibraryStore(root: tmp)
        let recs = try USRFile(data: Data(contentsOf: USRFileTests.examples.appendingPathComponent("USER002.USR"))).patches
        let a = store.addPatch(record: recs[0], name: "A", source: nil)
        let b = store.addPatch(record: recs[1], name: "B", source: nil)
        let s = store.createSetlist(name: "S", slots: [a.id, b.id] + Array(repeating: nil, count: 30))
        // user deletes one patch folder and half-breaks another, and a setlist file is garbage / short
        try FileManager.default.removeItem(at: tmp.appendingPathComponent("Patches/\(b.id.uuidString).patch"))
        let c = store.addPatch(record: recs[2], name: "C", source: nil)
        try FileManager.default.removeItem(at: tmp.appendingPathComponent("Patches/\(c.id.uuidString).patch/record.bin"))
        let badDir = tmp.appendingPathComponent("Setlists/\(UUID().uuidString).setlist"); try FileManager.default.createDirectory(at: badDir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: badDir.appendingPathComponent("setlist.json"))
        var short = try JSONSerialization.jsonObject(with: Data(contentsOf: tmp.appendingPathComponent("Setlists/\(s.id.uuidString).setlist/setlist.json"))) as! [String: Any]
        short["slots"] = [a.id.uuidString]; short["header"] = Data([1, 2, 3]).base64EncodedString()
        try JSONSerialization.data(withJSONObject: short).write(to: tmp.appendingPathComponent("Setlists/\(s.id.uuidString).setlist/setlist.json"))

        let reloaded = LibraryStore(root: tmp)
        XCTAssertEqual(reloaded.patches.map(\.name), ["A"])
        let set = try XCTUnwrap(reloaded.setlist(s.id))
        XCTAssertEqual(set.slots.count, 32)
        XCTAssertEqual(set.header.count, USRFile.headerSize)
        XCTAssertEqual(reloaded.filledCount(set), 1)
        XCTAssertNotNil(reloaded.loadWarning)
        XCTAssertThrowsError(try reloaded.buildFile(for: s.id))
    }

    func testBlankPatchAdoptionBuiltInAndResetBank() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("psr-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = LibraryStore(root: tmp)
        let file = try USRFile(data: Data(contentsOf: USRFileTests.examples.appendingPathComponent("USER001.USR")))
        let a = store.addPatch(record: file.patches[0], name: "A", source: nil)
        XCTAssertNil(store.blankPatchID)
        let blank = store.addPatch(record: file.patches[1], name: LibraryStore.blankPatchName, source: nil)
        XCTAssertEqual(store.blankPatchID, blank.id)
        XCTAssertEqual(LibraryStore(root: tmp).blankPatchID, blank.id)

        let s = store.createSetlist(name: "S", slots: Array(repeating: a.id, count: 32))
        XCTAssertTrue(store.resetBankToBlank(2, in: s.id))
        let after = try XCTUnwrap(store.setlist(s.id))
        XCTAssertEqual((1...4).map { after.slots[SlotLayout.position(bank: 2, memory: $0)] }, Array(repeating: blank.id, count: 4))
        XCTAssertEqual(after.slots.filter { $0 == blank.id }.count, 4)
        // With nothing marked, the copy shipped in the app is created and used.
        let fresh = LibraryStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("psr-test-\(UUID().uuidString)"), seedBlankPatch: true)
        defer { try? FileManager.default.removeItem(at: fresh.root) }
        let builtIn = try XCTUnwrap(fresh.blankPatch)
        XCTAssertEqual(builtIn.name, LibraryStore.blankPatchName); XCTAssertEqual(builtIn.meta.source, "Built-in")
        XCTAssertEqual(builtIn.data.count, USRFile.patchSize)
        XCTAssertTrue(store.patchFolderURL(a.id).path.hasSuffix("\(a.id.uuidString).patch"))
    }

    func testSetlistPointingAtDeletedPatchCountsAsEmpty() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("psr-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = LibraryStore(root: tmp)
        let s = store.createSetlist(name: "S", slots: Array(repeating: UUID(), count: 32))   // 32 refs, no such patches
        XCTAssertEqual(store.filledCount(s), 0)
        XCTAssertEqual(store.missingCount(s), 32)
        XCTAssertFalse(store.isComplete(s))
        XCTAssertThrowsError(try store.buildFile(for: s.id))
    }
}

final class PatchDetailsTests: XCTestCase {
    /// Values read from the keyboard for Bank 1 / Memory 1 (see the listing in the project notes).
    func testBank1Memory1MatchesKeyboardListing() throws {
        let file = try USRFile(data: Data(contentsOf: USRFileTests.examples.appendingPathComponent("USER001.USR")))
        let d = PatchDetails(record: file.patches[SlotLayout.position(bank: 1, memory: 1)])
        XCTAssertEqual(d.main.number, 102); XCTAssertEqual(d.main.name, "Overdriven Guitar")
        XCTAssertEqual([d.main.octave, d.main.volume, d.main.pan, d.main.reverb, d.main.chorus], [-1, 55, 64, 40, 60])
        XCTAssertEqual([d.main.attack, d.main.release, d.main.cutoff, d.main.resonance], [64, 64, 64, 64])
        XCTAssertEqual([d.split.volume, d.split.reverb, d.split.chorus, d.split.octave], [75, 8, 0, -1])
        XCTAssertEqual([d.dual.number, d.dual.volume, d.dual.reverb, d.dual.chorus], [272, 97, 43, 60])
        XCTAssertEqual(d.split.on, false); XCTAssertEqual(d.dual.on, false)
        XCTAssertEqual(d.harmonyName, "Octave"); XCTAssertEqual(d.harmonyVolume, 100)
        XCTAssertEqual(d.dsp1Type, 6); XCTAssertTrue(d.dsp1On); XCTAssertFalse(d.dsp2On)
        XCTAssertEqual(PatchDetails.noteName(d.splitPoint), "F#2")
        XCTAssertTrue(d.splitPointBytesAgree)
    }

    /// Bank 8 / Memory 1 with distinctive values set on the keyboard (transpose 1, style 003, echo harmony, ...).
    func testDistinctiveBankDecodes() {
        let hex = "0100020037370565000700000001016f411101414243447f006afe513d09027f0080ff2e3f5b024748494b030341027f1a500000000000000000270002000d007c00017f00004040404040404040404040400c0057044c027f011f003b00400000000064646464007f005b007f0040000074210000751b0000710100681730006800590068155a64646464646464646500"
        let rec = Data((0..<hex.count / 2).map { UInt8(hex[hex.index(hex.startIndex, offsetBy: $0 * 2)...].prefix(2), radix: 16)! })
        let d = PatchDetails(record: rec)
        XCTAssertEqual(d.styleNumber, 3); XCTAssertEqual(d.styleVolume, 101)
        XCTAssertEqual(d.transpose, 1); XCTAssertEqual(d.pitchBendRange, 3); XCTAssertEqual(d.touchResponse, 3)
        XCTAssertEqual(d.harmonyName, "Echo 1/32"); XCTAssertTrue(d.harmonyOn); XCTAssertEqual(d.harmonyVolume, 80)
        XCTAssertEqual(d.dsp1Type, 32); XCTAssertEqual(d.dsp2Part, 2); XCTAssertEqual(d.dsp1Part, 0)
    }

    func testNoteAndPanNames() {
        XCTAssertEqual(PatchDetails.noteName(60), "C3"); XCTAssertEqual(PatchDetails.noteName(62), "D3")
        XCTAssertEqual(PatchDetails.panName(64), "C"); XCTAssertEqual(PatchDetails.panName(60), "L4"); XCTAssertEqual(PatchDetails.panName(70), "R6")
    }
}

@MainActor
final class InstrumentIconTests: XCTestCase {
    func testInferenceForKnownVoices() {
        let expected: [(Int, InstrumentIcon)] = [
            (1, .piano), (102, .guitarLead), (89, .acousticGuitar), (91, .acousticGuitar), (93, .guitar), (107, .bass),
            (129, .strings), (272, .synthLead), (304, .synth), (208, .woodwind), (312, .mallets), (163, .brass), (156, .choir), (44, .organLead),
            (61, .organ), (341, .drums), (830, .sfx), (22, .electricPiano), (127, .strings), (6, .piano), (797, .mallets), (784, .acousticGuitar), (80, .accordion), (78, .harp), (806, .drums), (308, .synthPad),
        ]
        for (voice, icon) in expected {
            XCTAssertEqual(InstrumentIcon.infer(voice: voice), icon, "voice \(voice) \(VoiceCatalog.name(for: voice))")
        }
        XCTAssertEqual(InstrumentIcon.allCases.count, 23)
    }

    func testOverridePersistsAndResetsToAutomatic() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("psr-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = LibraryStore(root: tmp)
        let rec = try USRFile(data: Data(contentsOf: USRFileTests.examples.appendingPathComponent("USER001.USR"))).patches[0]
        let p = store.addPatch(record: rec, name: "X", source: nil)
        XCTAssertEqual(p.icon, .guitarLead)           // voice 102, inferred on import
        XCTAssertFalse(p.hasCustomIcon)
        store.setIcon(.ukulele, forPatch: p.id)
        XCTAssertEqual(LibraryStore(root: tmp).patch(p.id)?.icon, .ukulele)
        XCTAssertTrue(LibraryStore(root: tmp).patch(p.id)?.hasCustomIcon ?? false)
        XCTAssertTrue(try XCTUnwrap(store.patch(p.id)).matches(search: "ukulele"))
        store.setIcon(nil, forPatch: p.id)
        XCTAssertEqual(LibraryStore(root: tmp).patch(p.id)?.icon, .guitarLead)
        // an override chosen during import is stored
        let q = store.addPatch(record: try USRFile(data: Data(contentsOf: USRFileTests.examples.appendingPathComponent("USER002.USR"))).patches[5], name: "Y", source: nil, icon: .drums)
        XCTAssertEqual(q.icon, .drums)
    }
}

@MainActor
final class BlankPatchTests: XCTestCase {
    func testBlankPatchLifecycle() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("psr-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = LibraryStore(root: tmp)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("library.json").path))   // version stamp is written
        let recs = try USRFile(data: Data(contentsOf: USRFileTests.examples.appendingPathComponent("USER002.USR"))).patches
        let a = store.addPatch(record: recs[0], name: "A", source: nil), b = store.addPatch(record: recs[1], name: "B", source: nil)
        let s = store.createSetlist(name: "S", slots: [b.id] + Array(repeating: nil, count: 31))

        XCTAssertNil(store.blankPatch)
        XCTAssertTrue(store.useBlankPatch(in: s.id, at: 3))                      // nothing marked: the built-in blank is created
        let builtIn = try XCTUnwrap(store.blankPatch)
        XCTAssertEqual(store.setlist(s.id)?.slots[3], builtIn.id)
        store.setSlot(3, of: s.id, to: nil)

        store.setBlankPatch(a.id)
        XCTAssertEqual(LibraryStore(root: tmp).blankPatchID, a.id)             // persisted
        XCTAssertTrue(store.useBlankPatch(in: s.id, at: 3))
        XCTAssertEqual(store.setlist(s.id)?.slots[3], a.id)
        XCTAssertEqual(store.fillEmptySlots(of: s.id), 30)                       // 32 − slot 0 (B) − slot 3 (already A)
        XCTAssertEqual(store.setlist(s.id)?.slots[0], b.id)                      // existing patches are untouched
        XCTAssertTrue(store.isComplete(store.setlist(s.id)!))

        store.setBlankPatch(UUID())                                            // unknown id is ignored
        XCTAssertEqual(store.blankPatchID, a.id)
        store.setSlot(3, of: s.id, to: nil); store.setSlot(0, of: s.id, to: nil)
        store.deletePatch(a.id)                                                  // in use → refused
        XCTAssertNotNil(store.patch(a.id))
        for i in 0..<32 { store.setSlot(i, of: s.id, to: b.id) }
        store.deletePatch(a.id)
        XCTAssertNil(store.blankPatchID)                                         // deleting the blank patch clears it
    }

    func testVersionStringsAreNeverEmpty() {
        XCTAssertFalse(AppVersion.display.isEmpty)
        XCTAssertEqual(AppVersion.libraryFormat, 1)
    }
}
