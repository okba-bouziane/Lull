import XCTest
@testable import LullCore

final class GroupingTests: XCTestCase {
    func testOutermostBundle() {
        XCTAssertEqual(Grouper.outermostBundle("/Applications/Google Chrome.app/Contents/Frameworks/X.framework/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper"),
                       "/Applications/Google Chrome.app")
        XCTAssertEqual(Grouper.outermostBundle("/Applications/Spotify.app"), "/Applications/Spotify.app")
        XCTAssertNil(Grouper.outermostBundle("/opt/homebrew/bin/mongod"))
        XCTAssertEqual(Grouper.outermostBundle("/Users/x/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS/steam_osx"),
                       "/Users/x/Library/Application Support/Steam/Steam.AppBundle/Steam")
    }

    func testSystemPaths() {
        XCTAssertTrue(Grouper.isSystemPath("/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder"))
        XCTAssertTrue(Grouper.isSystemPath("/usr/libexec/trustd"))
        XCTAssertFalse(Grouper.isSystemPath("/Applications/Discord.app/Contents/MacOS/Discord"))
        XCTAssertFalse(Grouper.isSystemPath("/opt/homebrew/bin/mongod"))
    }

    func testHelpersJoinTheirApp() {
        let chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
        let stats = [
            ProcessStat(pid: 10, name: "Google Chrome", path: chrome, responsiblePID: 10, cpu: 5, memory: 100),
            ProcessStat(pid: 11, name: "Renderer", path: "/Applications/Google Chrome.app/Contents/Frameworks/R.app/Contents/MacOS/R", responsiblePID: 10, cpu: 30, memory: 400),
            // An Apple XPC service working for Chrome counts toward Chrome, like Activity Monitor.
            ProcessStat(pid: 12, name: "VTDecoderXPCService", path: "/System/Library/Frameworks/VT.framework/XPCServices/VT.xpc/Contents/MacOS/VT", responsiblePID: 10, cpu: 2, memory: 10),
            ProcessStat(pid: 20, name: "mongod", path: "/opt/homebrew/bin/mongod", responsiblePID: 20, cpu: 1, memory: 50),
        ]
        let groups = Dictionary(uniqueKeysWithValues: Grouper.group(stats).map { ($0.id, $0) })
        XCTAssertEqual(groups.count, 2)
        let g = groups["/Applications/Google Chrome.app"]!
        XCTAssertEqual(g.pids, [10, 11, 12])
        XCTAssertEqual(g.cpu, 37)
        XCTAssertEqual(g.memory, 510)
        XCTAssertEqual(g.leaderPID, 10)
        XCTAssertEqual(g.fallbackName, "Google Chrome")
        XCTAssertEqual(groups["/opt/homebrew/bin/mongod"]?.fallbackName, "mongod")
    }

    func testUnreadableResponsibleFallsBackToOwnPath() {
        let stats = [ProcessStat(pid: 5, name: "Helper", path: "/Applications/Foo.app/Contents/MacOS/Helper", responsiblePID: 1, cpu: 0, memory: 1)]
        XCTAssertEqual(Grouper.group(stats).first?.id, "/Applications/Foo.app")
    }
}

final class LeaderAndLaunchdTests: XCTestCase {
    func testLeaderIsTheProcessHelpersBelongTo() {
        // Steam: ipcserver (own process, seen first) + steam_osx + two helpers owned by steam_osx.
        let b = "/Users/x/Steam.AppBundle/Steam/Contents"
        let stats = [
            ProcessStat(pid: 100, name: "ipcserver", path: b + "/MacOS/ipcserver", responsiblePID: 100, cpu: 0, memory: 1),
            ProcessStat(pid: 200, name: "steam_osx", path: b + "/MacOS/steam_osx", responsiblePID: 200, cpu: 0, memory: 1),
            ProcessStat(pid: 300, name: "Steam Helper", path: b + "/Frameworks/Steam Helper.app/Contents/MacOS/Steam Helper", responsiblePID: 200, cpu: 0, memory: 1),
            ProcessStat(pid: 301, name: "Steam Helper", path: b + "/Frameworks/Steam Helper.app/Contents/MacOS/Steam Helper", responsiblePID: 200, cpu: 0, memory: 1),
        ]
        let groups = Grouper.group(stats)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].leaderPID, 200)
        XCTAssertEqual(groups[0].fallbackName, "Steam")
    }

    func testParsesLaunchdServices() {
        let text = """
        gui/501 = {
        \tservices = {
        \t\t    2147      - \tsh.brew.mailpit
        \t\t   14787      - \tapplication.com.valvesoftware.steam.1.2
        \t\t   30901    -15 \tjp.co.canon.CUPSCAPT2.BackGrounder
        \t\t     631      - \tcom.apple.MenuBarAgent
        \t\t       0      0 \tcom.valvesoftware.steamclean
        \t}
        \tdisabled services = {
        \t\t"com.docker.helper" => enabled
        \t}
        }
        """
        let jobs = Launchd.parseServices(text)
        XCTAssertEqual(jobs, [2147: "sh.brew.mailpit", 30901: "jp.co.canon.CUPSCAPT2.BackGrounder"])
    }

    /// Real launchd round trip with a throwaway KeepAlive job: killing it brings it back, stopping it does not.
    /// Run with LULL_LAUNCHD_TEST=1.
    func testStoppingAKeepAliveJob() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LULL_LAUNCHD_TEST"] == "1")
        let label = "com.okba.lull.selftest"
        let plist = FileManager.default.temporaryDirectory.appendingPathComponent("\(label).plist")
        let dict: [String: Any] = ["Label": label, "ProgramArguments": ["/bin/sleep", "1000"], "KeepAlive": true, "RunAtLoad": true, "ThrottleInterval": 1]
        try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0).write(to: plist)
        Launchd.stop(label)
        XCTAssertNotNil(Launchd.run(["bootstrap", "gui/\(getuid())", plist.path]))
        defer { Launchd.stop(label); try? FileManager.default.removeItem(at: plist) }

        func pid() -> pid_t? { Launchd.userJobs().first { $0.value == label }?.key }
        func waitFor(_ ok: () -> Bool) -> Bool { for _ in 0..<150 { if ok() { return true }; usleep(100_000) }; return false }

        XCTAssertTrue(waitFor { pid() != nil })
        guard let first = pid() else { return XCTFail("job not running") }
        kill(first, SIGTERM)
        XCTAssertTrue(waitFor { (pid() ?? first) != first }, "launchd should restart a killed KeepAlive job")
        guard let second = pid() else { return XCTFail("job not running") }
        XCTAssertTrue(Launchd.stop(label))
        XCTAssertTrue(waitFor { kill(second, 0) != 0 })
        usleep(1_500_000)
        XCTAssertNil(pid(), "a stopped job must stay stopped")
        XCTAssertFalse(Launchd.isRunning(label))
    }
}

final class HogTrackerTests: XCTestCase {
    func testTracksContinuousHeat() {
        let t = HogTracker()
        let start = Date(timeIntervalSince1970: 1000)
        t.update([("a", 90), ("b", 10)], threshold: 80, now: start)
        t.update([("a", 95), ("b", 10)], threshold: 80, now: start.addingTimeInterval(120))
        XCTAssertEqual(t.hotDuration("a", now: start.addingTimeInterval(180)), 180)
        XCTAssertNil(t.hotDuration("b"))
        // Dropping below the threshold once resets the clock.
        t.update([("a", 20)], threshold: 80, now: start.addingTimeInterval(200))
        XCTAssertNil(t.hotDuration("a"))
    }
}

final class SamplerTests: XCTestCase {
    func testSamplerSeesThisProcess() {
        let s = ProcessSampler()
        _ = s.sample()
        var x = 0.0
        for i in 0..<3_000_000 { x += sin(Double(i)) } // burn a little CPU
        let stats = s.sample()
        let me = stats.first { $0.pid == getpid() }
        XCTAssertNotNil(me)
        XCTAssertGreaterThan(me!.memory, 1_000_000)
        XCTAssertGreaterThan(me!.cpu, 0, "\(x)")
    }

    func testSystemSnapshotIsSane() {
        let s = SystemSampler()
        _ = s.sample()
        let snap = s.sample()
        XCTAssertGreaterThan(snap.memoryTotal, 0)
        XCTAssertGreaterThan(snap.memoryUsed, 0)
        XCTAssertLessThanOrEqual(snap.memoryUsed, snap.memoryTotal)
        XCTAssertGreaterThanOrEqual(snap.cpu, 0)
    }

    func testFormat() {
        XCTAssertEqual(Format.bytes(512 * 1_048_576), "512 MB")
        XCTAssertEqual(Format.bytes(3 * 1_073_741_824 / 2), "1.5 GB")
        XCTAssertEqual(Format.cpu(151.7), "152%")
        XCTAssertEqual(Format.cpu(3.21), "3.2%")
    }
}
