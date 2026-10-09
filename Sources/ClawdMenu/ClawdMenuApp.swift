import SwiftUI
import ServiceManagement
import UserNotifications

// MARK: - Model

struct Usage {
    var session = 0, sessionReset = 0   // % та хвилини до скидання (5h)
    var week = 0, weekReset = 0         // 7d
    var status = "unknown"
    var enterprise = false
}

@MainActor
final class Store: ObservableObject {
    @Published var usage: Usage?
    @Published var error: String?
    @AppStorage("interval") var interval = 60.0
    @AppStorage("notify") var notify = true
    private var notified = Set<Int>()   // пороги, про які вже сповіщали
    private var lastSession = 0
    private var timer: Timer?

    init() {
        restart()
    }

    func restart() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: max(30, interval), repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        Task { await refresh() }
    }

    var title: String {
        guard let u = usage else { return error == nil ? "…" : "!" }
        return "\(u.session)% · \(fmt(u.sessionReset))"
    }

    func refresh() async {
        do {
            let u = try await fetch()
            usage = u; error = nil
            if notify { check(u) }
            lastSession = u.session
        } catch { self.error = "\(error.localizedDescription)" }
    }

    private func check(_ u: Usage) {
        if u.session < lastSession - 20 {   // сесія скинулась
            notified.removeAll()
            push("Сесію скинуто", "Ліміт 5h знову вільний")
        }
        for t in [80, 95] where u.session >= t && !notified.contains(t) {
            notified.insert(t)
            push("Claude: сесія \(u.session)%", "Скидання через \(fmt(u.sessionReset))")
        }
    }

    private func push(_ title: String, _ body: String) {
        let n = UNUserNotificationCenter.current()
        n.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = .default
        n.add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
}

func fmt(_ m: Int) -> String {
    m >= 1440 ? "\(m / 1440)d\(m % 1440 / 60)h" : m >= 60 ? "\(m / 60)h\(m % 60)m" : "\(m)m"
}

// MARK: - API (порт з daemon/claude_usage_daemon.py)

struct AppError: LocalizedError { let errorDescription: String? }

func token() throws -> String {
    let p = Process(); let out = Pipe()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
    p.standardOutput = out; p.standardError = Pipe()
    try p.run(); p.waitUntilExit()
    let s = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    if let r = s.range(of: #""accessToken"\s*:\s*"([^"]+)""#, options: .regularExpression) {
        let m = String(s[r])
        return String(m.split(separator: "\"").last!)
    }
    throw AppError(errorDescription: "Токен не знайдено в Keychain — залогінься в Claude Code")
}

func fetch() async throws -> Usage {
    var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!, timeoutInterval: 20)
    req.httpMethod = "POST"
    for (k, v) in ["anthropic-version": "2023-06-01", "anthropic-beta": "oauth-2025-04-20",
                   "Content-Type": "application/json", "User-Agent": "claude-code/2.1.5",
                   "Authorization": "Bearer \(try token())"] { req.setValue(v, forHTTPHeaderField: k) }
    req.httpBody = try JSONSerialization.data(withJSONObject: [
        "model": "claude-haiku-4-5-20251001", "max_tokens": 1,
        "messages": [["role": "user", "content": "hi"]]])
    let (_, resp) = try await URLSession.shared.data(for: req)
    let h = resp as! HTTPURLResponse
    guard h.statusCode < 400 else { throw AppError(errorDescription: "API HTTP \(h.statusCode)") }

    func hdr(_ n: String) -> String? { h.value(forHTTPHeaderField: "anthropic-ratelimit-unified-" + n) }
    func pct(_ s: String?) -> Int { Int(((Double(s ?? "") ?? 0) * 100).rounded()) }
    func mins(_ s: String?) -> Int { max(0, Int(((Double(s ?? "") ?? 0) - Date().timeIntervalSince1970) / 60)) }

    if hdr("5h-utilization") != nil {
        return Usage(session: pct(hdr("5h-utilization")), sessionReset: mins(hdr("5h-reset")),
                     week: pct(hdr("7d-utilization")), weekReset: mins(hdr("7d-reset")),
                     status: hdr("5h-status") ?? "unknown")
    }
    // Enterprise: один spending-limit
    return Usage(session: pct(hdr("overage-utilization")), sessionReset: mins(hdr("overage-reset")),
                 status: hdr("status") ?? "unknown", enterprise: true)
}

// MARK: - UI

struct Row: View {
    let label: String, pct: Int, reset: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(label); Spacer(); Text("\(pct)%").monospacedDigit() }
            ProgressView(value: Double(min(pct, 100)), total: 100)
                .tint(pct >= 95 ? .red : pct >= 80 ? .orange : .accentColor)
            Text("скидання через \(fmt(reset))").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct Panel: View {
    @ObservedObject var s: Store
    @State private var login = SMAppService.mainApp.status == .enabled
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let u = s.usage {
                Row(label: u.enterprise ? "Витрати (overage)" : "Сесія (5h)", pct: u.session, reset: u.sessionReset)
                if !u.enterprise { Row(label: "Тиждень (7d)", pct: u.week, reset: u.weekReset) }
                Text("Статус: \(u.status)").font(.caption).foregroundStyle(.secondary)
            }
            if let e = s.error { Text(e).font(.caption).foregroundStyle(.red) }
            Divider()
            Picker("Оновлення", selection: Binding(get: { s.interval }, set: { s.interval = $0; s.restart() })) {
                ForEach([30.0, 60, 120, 300], id: \.self) { Text("\(Int($0)) с").tag($0) }
            }
            Toggle("Сповіщення (80/95% і скидання)", isOn: $s.notify)
            Toggle("Запуск при вході", isOn: Binding(get: { login }, set: { on in
                do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister(); login = on }
                catch { s.error = error.localizedDescription }
            }))
            HStack {
                Button("Оновити") { Task { await s.refresh() } }
                Spacer()
                Button("Вийти") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding().frame(width: 280)
    }
}

let menuIcon: NSImage = {
    let i = Bundle.main.image(forResource: "clawd") ?? NSImage(systemSymbolName: "gauge", accessibilityDescription: nil)!
    i.size = NSSize(width: 18, height: 18)
    return i
}()

@main
struct ClawdMenuApp: App {
    @StateObject private var store = Store()
    var body: some Scene {
        MenuBarExtra {
            Panel(s: store)
        } label: {
            Image(nsImage: menuIcon)
            Text(store.title)
        }
        .menuBarExtraStyle(.window)
    }
}
