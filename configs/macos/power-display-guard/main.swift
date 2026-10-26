import Foundation
import IOKit.ps
import IOKit.pwr_mgt
import Darwin

// PowerDisplayGuard — the single owner of this Mac's keep-awake policy.
//
// On AC, and for 60 seconds after switching to battery, it holds display and
// idle-system sleep assertions and keeps SleepDisabled = 1 (lid-closed sleep
// off). After 60 s on battery everything is released. A keep-awake override
// (override.json, written by BarShelf) extends the hold for up to 12 hours.
// Amphetamine and BarShelf never touch SleepDisabled; only this process does.
//
// Files (mode 0600) in ~/Library/Application Support/PowerDisplayGuard/:
//   status.json    written here on change and at least every 5 s
//   override.json  written by BarShelf (tmp + rename), deleted to cancel

let guardVersion = "2"
let graceSeconds: TimeInterval = 60
let overrideCap: TimeInterval = 12 * 3600
let lidClosedMinBattery = 20

// MARK: - Policy (pure, covered by --self-test)

struct GracePolicy {
    var wasOnAC = false
    var batterySince: TimeInterval?
    mutating func keepAwake(onAC: Bool, now: TimeInterval) -> Bool {
        if onAC {
            wasOnAC = true
            batterySince = nil
            return true
        }
        guard wasOnAC else { return false }
        if batterySince == nil { batterySince = now }
        return now - batterySince! < graceSeconds
    }
    func graceRemaining(now: TimeInterval) -> Int? {
        guard let since = batterySince, now - since < graceSeconds else { return nil }
        return Int((graceSeconds - (now - since)).rounded(.up))
    }
}

struct Override: Codable, Equatable {
    var id: String?
    var createdAt: String?
    var until: String
    var lidClosed: Bool?
    var source: String?
}

struct OverrideState: Equatable {
    var active: Bool
    var effectiveUntil: Date
    var capped: Bool
    var lidClosedEffective: Bool
    var note: String?
}

let iso: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

func parseDate(_ s: String?) -> Date? {
    guard let s else { return nil }
    if let d = iso.date(from: s) { return d }
    let frac = ISO8601DateFormatter()
    frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return frac.date(from: s)
}

/// The cap counts from when the override was made (createdAt, never later
/// than the file's mtime or now), so re-reading the file does not extend it.
func evaluate(_ o: Override, written: Date, now: Date, onAC: Bool, battery: Int?) -> OverrideState? {
    guard let requested = parseDate(o.until) else { return nil }
    let created = min(parseDate(o.createdAt) ?? written, written, now)
    let cap = created.addingTimeInterval(overrideCap)
    let until = min(requested, cap)
    let capped = requested > cap
    var notes: [String] = []
    if capped { notes.append("capped at 12 h") }
    var lid = o.lidClosed ?? false
    if lid, !onAC, let battery, battery <= lidClosedMinBattery {
        lid = false
        notes.append("battery ≤ \(lidClosedMinBattery) %: lid-closed ignored")
    }
    return OverrideState(active: now < until, effectiveUntil: until, capped: capped,
                         lidClosedEffective: lid, note: notes.isEmpty ? nil : notes.joined(separator: "; "))
}

// MARK: - Status file

struct Blocker: Codable, Equatable {
    var pid: Int
    var process: String
    var type: String
    var assertionName: String?
}

struct StatusOverride: Codable, Equatable {
    var id: String?
    var createdAt: String?
    var until: String
    var requestedUntil: String?
    var lidClosed: Bool
    var lidClosedEffective: Bool
    var note: String?
    var source: String?
}

struct Status: Codable, Equatable {
    var version = 1
    var updatedAt = ""
    var guardPid: Int
    var guardVersion: String
    var onAC: Bool
    var phase: String          // ac | grace | battery | override
    var graceRemaining: Int?
    var holding: Bool
    var sleepDisabled: Bool
    var batteryPercent: Int?
    var override: StatusOverride?
    var blockers: [Blocker]
}

func phase(onAC: Bool, powerHold: Bool, overrideActive: Bool) -> String {
    if overrideActive { return "override" }
    if onAC { return "ac" }
    return powerHold ? "grace" : "battery"
}

func encode(_ status: Status) -> Data {
    let e = JSONEncoder()
    e.outputFormatting = [.prettyPrinted, .sortedKeys]
    return (try? e.encode(status)) ?? Data()
}

// MARK: - Self-test and samples

func selfTest() {
    var p = GracePolicy()
    precondition(!p.keepAwake(onAC: false, now: 0))
    precondition(p.keepAwake(onAC: true, now: 1))
    precondition(p.keepAwake(onAC: false, now: 2))
    precondition(p.keepAwake(onAC: true, now: 3))
    precondition(p.keepAwake(onAC: false, now: 10))
    precondition(p.graceRemaining(now: 10) == 60)
    precondition(p.keepAwake(onAC: false, now: 69.9))
    precondition(!p.keepAwake(onAC: false, now: 70))
    precondition(p.graceRemaining(now: 70) == nil)
    precondition(!p.keepAwake(onAC: false, now: 100))
    precondition(p.keepAwake(onAC: true, now: 101))

    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let o2h = Override(id: "a", createdAt: iso.string(from: t0), until: iso.string(from: t0 + 7200), lidClosed: true, source: "barshelf")
    let s = evaluate(o2h, written: t0, now: t0 + 60, onAC: true, battery: 80)!
    precondition(s.active && !s.capped && s.lidClosedEffective && s.note == nil)
    precondition(!evaluate(o2h, written: t0, now: t0 + 7200, onAC: true, battery: 80)!.active)
    let low = evaluate(o2h, written: t0, now: t0 + 60, onAC: false, battery: 20)!
    precondition(low.active && !low.lidClosedEffective && low.note!.contains("lid-closed ignored"))
    precondition(evaluate(o2h, written: t0, now: t0 + 60, onAC: true, battery: 5)!.lidClosedEffective)
    let o20h = Override(id: "b", createdAt: iso.string(from: t0), until: iso.string(from: t0 + 72000), lidClosed: false, source: nil)
    let c = evaluate(o20h, written: t0, now: t0 + 60, onAC: true, battery: 80)!
    precondition(c.capped && c.effectiveUntil == t0 + overrideCap && c.note == "capped at 12 h")
    // A createdAt in the future cannot push the cap out.
    let future = Override(id: "c", createdAt: iso.string(from: t0 + 86400), until: iso.string(from: t0 + 90000), lidClosed: nil, source: nil)
    precondition(evaluate(future, written: t0, now: t0, onAC: true, battery: 80)!.effectiveUntil == t0 + overrideCap)
    precondition(evaluate(Override(id: nil, createdAt: nil, until: "garbage", lidClosed: nil, source: nil), written: t0, now: t0, onAC: true, battery: nil) == nil)

    precondition(phase(onAC: true, powerHold: true, overrideActive: false) == "ac")
    precondition(phase(onAC: false, powerHold: true, overrideActive: false) == "grace")
    precondition(phase(onAC: false, powerHold: false, overrideActive: false) == "battery")
    precondition(phase(onAC: false, powerHold: false, overrideActive: true) == "override")
    print("PASS: grace policy, override evaluation (expiry, 12 h cap, future createdAt, low-battery lid), phases")
}

func writeSamples(to dir: String) {
    let t0 = iso.date(from: "2026-10-26T03:00:00Z")!
    let caffeinate = Blocker(pid: 75068, process: "caffeinate", type: "PreventUserIdleSystemSleep", assertionName: "caffeinate command-line tool")
    func status(_ phase: String, onAC: Bool, grace: Int?, holding: Bool, sd: Bool, battery: Int?, override: StatusOverride?) -> Status {
        Status(updatedAt: iso.string(from: t0), guardPid: 91566, guardVersion: guardVersion, onAC: onAC, phase: phase,
               graceRemaining: grace, holding: holding, sleepDisabled: sd, batteryPercent: battery, override: override, blockers: [caffeinate])
    }
    let ov = StatusOverride(id: "6F1C2A7E-0B7D-4E7A-9C1B-2F7C5E1D9A10", createdAt: iso.string(from: t0), until: iso.string(from: t0 + 7200),
                            requestedUntil: nil, lidClosed: true, lidClosedEffective: true, note: nil, source: "barshelf")
    var capped = ov; capped.until = iso.string(from: t0 + overrideCap); capped.requestedUntil = iso.string(from: t0 + 20 * 3600)
    capped.lidClosed = false; capped.lidClosedEffective = false; capped.note = "capped at 12 h"
    var lowLid = ov; lowLid.lidClosedEffective = false; lowLid.note = "battery ≤ 20 %: lid-closed ignored"
    let samples: [(String, Status)] = [
        ("ac", status("ac", onAC: true, grace: nil, holding: true, sd: true, battery: 100, override: nil)),
        ("grace", status("grace", onAC: false, grace: 42, holding: true, sd: true, battery: 97, override: nil)),
        ("battery", status("battery", onAC: false, grace: nil, holding: false, sd: false, battery: 96, override: nil)),
        ("override", status("override", onAC: false, grace: nil, holding: true, sd: true, battery: 88, override: ov)),
        ("override-capped", status("override", onAC: true, grace: nil, holding: true, sd: true, battery: 100, override: capped)),
        ("override-lid-ignored", status("override", onAC: false, grace: nil, holding: true, sd: false, battery: 18, override: lowLid)),
    ]
    for (name, s) in samples { try! encode(s).write(to: URL(fileURLWithPath: "\(dir)/status-\(name).json")) }
    print("wrote \(samples.count) samples to \(dir)")
}

if CommandLine.arguments.contains("--self-test") { selfTest(); exit(0) }
if let i = CommandLine.arguments.firstIndex(of: "--write-samples"), i + 1 < CommandLine.arguments.count {
    writeSamples(to: CommandLine.arguments[i + 1]); exit(0)
}

// MARK: - System access

let dir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/PowerDisplayGuard")
let statusURL = dir.appendingPathComponent("status.json")
let overrideURL = dir.appendingPathComponent("override.json")
umask(0o077) // status.json and its temp file are created 0600

func report(_ message: String) {
    print("\(iso.string(from: Date())) \(message)")
    fflush(stdout)
}

func onACPower() -> Bool {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else {
        return false
    }
    return source as String == kIOPSACPowerValue
}

func batteryPercent() -> Int? {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
    for ps in list {
        guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
              let cur = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
        return cur * 100 / max
    }
    return nil
}

// proc_name fails for root-owned processes such as powerd; the kernel's
// p_comm via sysctl does not need privileges.
func processName(_ pid: pid_t) -> String {
    var name = [CChar](repeating: 0, count: 256)
    if proc_name(pid, &name, UInt32(name.count)) > 0 { return String(cString: name) }
    var info = kinfo_proc(), size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return "" }
    return withUnsafeBytes(of: info.kp_proc.p_comm) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
}

// Other processes' sleep-preventing assertions; read through IOKit, no pmset spawn.
func blockers() -> [Blocker] {
    var raw: Unmanaged<CFDictionary>?
    guard IOPMCopyAssertionsByProcess(&raw) == kIOReturnSuccess,
          let byPid = raw?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return [] }
    let me = Int(getpid())
    var out: [Blocker] = []
    for (pidNumber, list) in byPid where pidNumber.intValue != me {
        let process = processName(pidNumber.int32Value)
        for a in list {
            guard let type = a["AssertType"] as? String,
                  type.contains("Prevent") || type.hasPrefix("NoIdle") || type.hasPrefix("NoDisplay") else { continue }
            out.append(Blocker(pid: pidNumber.intValue, process: process.isEmpty ? "pid \(pidNumber)" : process,
                               type: type, assertionName: a["AssertName"] as? String))
        }
    }
    return out.sorted { ($0.process, $0.pid, $0.type) < ($1.process, $1.pid, $1.type) }
}

// Runs only the two commands sudoers allows without a password:
// /usr/bin/pmset -a disablesleep 1 and /usr/bin/pmset -a disablesleep 0.
func setSleepDisabled(_ on: Bool) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
    task.arguments = ["-n", "/usr/bin/pmset", "-a", "disablesleep", on ? "1" : "0"]
    do { try task.run(); task.waitUntilExit() } catch { report("disablesleep \(on ? 1 : 0) failed to start: \(error)"); return }
    if task.terminationStatus != 0 { report("disablesleep \(on ? 1 : 0) failed (status \(task.terminationStatus))") }
}

func sleepDisabled() -> Bool? {
    let task = Process(), pipe = Pipe()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    task.arguments = ["-g"]
    task.standardOutput = pipe
    do { try task.run() } catch { return nil }
    let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    task.waitUntilExit()
    guard let line = out.split(separator: "\n").first(where: { $0.contains("SleepDisabled") }) else { return nil }
    return line.split(whereSeparator: { $0 == " " || $0 == "\t" }).last == "1"
}

func readOverride() -> (Override, Date)? {
    guard let data = try? Data(contentsOf: overrideURL),
          let mtime = (try? FileManager.default.attributesOfItem(atPath: overrideURL.path))?[.modificationDate] as? Date,
          let o = try? JSONDecoder().decode(Override.self, from: data) else { return nil }
    return (o, mtime)
}

// MARK: - Loop

var policy = GracePolicy()
var assertions: [IOPMAssertionID] = []
var previousAC: Bool?
var lastSleepCheck: TimeInterval = -.infinity
var lastPowerChange: TimeInterval = 0
var knownSleepDisabled: Bool?
var lastStatus: Status?
var lastStatusWrite: TimeInterval = -.infinity
var lastOverrideID: String?

// Re-checked on every change of the wanted value; every 2 s for 90 s after a
// power change (Amphetamine resets SleepDisabled when it starts), otherwise
// every 30 s, so pmset is not spawned every second.
func enforceSleepDisabled(_ want: Bool, now: TimeInterval, force: Bool) {
    let interval: TimeInterval = now - lastPowerChange < 90 ? 2 : 30
    guard force || now - lastSleepCheck >= interval else { return }
    lastSleepCheck = now
    guard let current = sleepDisabled() else { return }
    knownSleepDisabled = current
    guard current != want else { return }
    setSleepDisabled(want)
    knownSleepDisabled = want
    report("SleepDisabled \(want ? 1 : 0)")
}

func setHolding(_ hold: Bool) {
    if hold && assertions.isEmpty {
        for type in [kIOPMAssertionTypePreventUserIdleDisplaySleep, kIOPMAssertionTypePreventUserIdleSystemSleep] {
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                     "PowerDisplayGuard" as CFString, &id)
            if result == kIOReturnSuccess { assertions.append(id) } else { report("Assertion creation failed: \(result)") }
        }
        report("Keep-awake held (\(assertions.count) assertions)")
    } else if !hold && !assertions.isEmpty {
        for id in assertions { IOPMAssertionRelease(id) }
        assertions.removeAll()
        report("Keep-awake released; normal sleep settings apply")
    }
}

var lastWantSleepDisabled: Bool?

func update() {
    let uptime = ProcessInfo.processInfo.systemUptime
    let now = Date()
    let ac = onACPower()
    if previousAC != ac {
        report(ac ? "AC connected" : "Battery power (60-second grace if previously on AC)")
        previousAC = ac
        lastPowerChange = uptime
    }
    let powerHold = policy.keepAwake(onAC: ac, now: uptime)
    let battery = batteryPercent()

    var ovState: OverrideState?
    var ov: Override?
    if let (o, mtime) = readOverride() {
        ov = o
        ovState = evaluate(o, written: mtime, now: now, onAC: ac, battery: battery)
        if let s = ovState, !s.active, let (again, mtime2) = readOverride(), mtime2 == mtime,
           let s2 = evaluate(again, written: mtime2, now: now, onAC: ac, battery: battery), !s2.active {
            try? FileManager.default.removeItem(at: overrideURL)
            report("Override \(o.id ?? "-") expired; removed")
            ov = nil; ovState = nil; lastOverrideID = nil
        }
    }
    if ov?.id != lastOverrideID {
        if let o = ov, let s = ovState { report("Override \(o.id ?? "-") until \(iso.string(from: s.effectiveUntil)) lidClosed=\(s.lidClosedEffective)\(s.note.map { " (\($0))" } ?? "")") }
        else if lastOverrideID != nil { report("Override cancelled") }
        lastOverrideID = ov?.id
    }
    let overrideActive = ovState?.active ?? false
    let holding = powerHold || overrideActive
    let wantSD = powerHold || (overrideActive && ovState!.lidClosedEffective)

    setHolding(holding)
    enforceSleepDisabled(wantSD, now: uptime, force: wantSD != lastWantSleepDisabled)
    lastWantSleepDisabled = wantSD

    var statusOverride: StatusOverride?
    if let o = ov, let s = ovState, s.active {
        statusOverride = StatusOverride(id: o.id, createdAt: o.createdAt, until: iso.string(from: s.effectiveUntil),
                                        requestedUntil: s.capped ? o.until : nil, lidClosed: o.lidClosed ?? false,
                                        lidClosedEffective: s.lidClosedEffective, note: s.note, source: o.source)
    }
    var status = Status(guardPid: Int(getpid()), guardVersion: guardVersion, onAC: ac,
                        phase: phase(onAC: ac, powerHold: powerHold, overrideActive: overrideActive),
                        graceRemaining: ac ? nil : policy.graceRemaining(now: uptime), holding: holding,
                        sleepDisabled: knownSleepDisabled ?? wantSD, batteryPercent: battery,
                        override: statusOverride, blockers: blockers())
    if status != lastStatus || uptime - lastStatusWrite >= 5 {
        lastStatus = status
        status.updatedAt = iso.string(from: now)
        do {
            try encode(status).write(to: statusURL, options: .atomic)
            lastStatusWrite = uptime
        } catch { report("status.json write failed: \(error)") }
    }
}

// On SIGTERM/SIGINT (launchctl bootout, logout, shutdown) leave lid-closed
// sleep allowed: SleepDisabled is a persistent system setting and must not
// stay on without this process enforcing the policy. Assertions are released
// by macOS when the process exits.
func installSignalHandlers() -> [DispatchSourceSignal] {
    [SIGTERM, SIGINT].map { sig in
        signal(sig, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        src.setEventHandler {
            setHolding(false)
            setSleepDisabled(false)
            report("Signal \(sig): released keep-awake, SleepDisabled 0, exiting")
            exit(0)
        }
        src.resume()
        return src
    }
}

try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
let signalSources = installSignalHandlers()
report("PowerDisplayGuard \(guardVersion) started (pid \(getpid()))")
update()
let timer = Timer(timeInterval: 1, repeats: true) { _ in update() }
RunLoop.main.add(timer, forMode: .common)
RunLoop.main.run()
