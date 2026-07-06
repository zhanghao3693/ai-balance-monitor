import Cocoa
import Foundation

// MARK: - Platform
enum Platform: String, Codable, CaseIterable {
    case deepseek = "deepseek"
    case zhipu = "zhipu"
    case kimi = "kimi"
    case minimax = "minimax"
    case longcat = "longcat"

    var displayName: String {
        switch self {
        case .deepseek: return "DeepSeek"
        case .zhipu:   return "智谱 AI"
        case .kimi:    return "Kimi"
        case .minimax: return "MiniMax"
        case .longcat: return "LongCat"
        }
    }

    var balanceURL: String? {
        switch self {
        case .deepseek: return "https://api.deepseek.com/user/balance"
        case .kimi:    return "https://api.moonshot.cn/v1/users/me/balance"
        // Zhipu, MiniMax, LongCat do not expose public balance REST endpoints.
        case .zhipu, .minimax, .longcat: return nil
        }
    }

    var platformURL: String {
        switch self {
        case .deepseek: return "https://platform.deepseek.com/usage"
        case .zhipu:   return "https://open.bigmodel.cn/overview"
        case .kimi:    return "https://platform.moonshot.cn/console"
        case .minimax: return "https://platform.minimaxi.com/user-center/payment/balance"
        case .longcat: return "https://longcat.chat/platform/"
        }
    }

    /// Auth header value for this platform
    func authHeader(key: String) -> String {
        switch self {
        case .deepseek, .zhipu, .kimi, .minimax, .longcat: return "Bearer \(key)"
        }
    }

    var iconFileName: String {
        switch self {
        case .deepseek: return "deepseek_icon.png"
        case .zhipu:   return "zhipu_icon.png"
        case .kimi:    return "kimi_icon.png"
        case .minimax: return "minimax_icon.png"
        case .longcat: return "longcat_icon.png"
        }
    }

    /// Estimated cost per 1M tokens (CNY) for token estimation
    var costPerMillionTokens: Double {
        switch self {
        case .deepseek: return 5.0   // DeepSeek ~¥5/1M tokens (rough avg)
        case .zhipu:   return 2.0   // Zhipu GLM-Flash free / GLM-4 paid ~¥2-8 range
        case .kimi:    return 12.0  // Kimi ~¥12/1M tokens
        case .minimax: return 1.0   // MiniMax M2.5-Lightning free / M2.5 ~¥1/M
        case .longcat: return 0.0   // LongCat currently free beta
        }
    }
}

// MARK: - Data Models — DeepSeek

struct BalanceInfo: Codable {
    let currency: String
    let totalBalance: String
    let grantedBalance: String
    let toppedUpBalance: String

    enum CodingKeys: String, CodingKey {
        case currency
        case totalBalance = "total_balance"
        case grantedBalance = "granted_balance"
        case toppedUpBalance = "topped_up_balance"
    }
}

struct BalanceResponse: Codable {
    let isAvailable: Bool
    let balanceInfos: [BalanceInfo]

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }
}

// MARK: - Data Models — Zhipu

/// Zhipu balance response (v1 — matches known API shape).
/// The actual endpoint may return a DeepSeek-compatible envelope or a flat object;
/// we decode both gracefully.
struct ZhipuBalanceEnvelope: Codable {
    let code: Int?
    let success: Bool?
    let msg: String?

    // DeepSeek-style envelope (some versions mirror this)
    let isAvailable: Bool?
    let balanceInfos: [ZhipuBalanceInfo]?

    // Flat single-currency style
    let data: ZhipuBalanceData?
}

struct ZhipuBalanceInfo: Codable {
    let currency: String?
    let totalBalance: String?
    let grantedBalance: String?
    let toppedUpBalance: String?

    enum CodingKeys: String, CodingKey {
        case currency
        case totalBalance = "total_balance"
        case grantedBalance = "granted_balance"
        case toppedUpBalance = "topped_up_balance"
    }
}

struct ZhipuBalanceData: Codable {
    let balance: Double?
    let totalBalance: Double?
    let grantedBalance: Double?
    let toppedUpBalance: Double?
    let currency: String?

    enum CodingKeys: String, CodingKey {
        case balance
        case totalBalance = "total_balance"
        case grantedBalance = "granted_balance"
        case toppedUpBalance = "topped_up_balance"
        case currency
    }
}

// MARK: - Data Models — Kimi

struct KimiBalanceResponse: Codable {
    let code: Int
    let data: KimiBalanceData?
    let scode: String?
    let status: Bool?
}

struct KimiBalanceData: Codable {
    let availableBalance: Double?
    let voucherBalance: Double?
    let cashBalance: Double?

    enum CodingKeys: String, CodingKey {
        case availableBalance = "available_balance"
        case voucherBalance = "voucher_balance"
        case cashBalance = "cash_balance"
    }
}

// MARK: - Data Models — MiniMax

struct MiniMaxPlanResponse: Codable {
    let modelRemains: [MiniMaxModelRemain]?
    let baseResp: MiniMaxBaseResp?

    enum CodingKeys: String, CodingKey {
        case modelRemains = "model_remains"
        case baseResp = "base_resp"
    }
}

struct MiniMaxBaseResp: Codable {
    let statusCode: Int?
    let statusMsg: String?

    enum CodingKeys: String, CodingKey {
        case statusCode = "status_code"
        case statusMsg = "status_msg"
    }
}

struct MiniMaxModelRemain: Codable {
    let modelName: String?
    let remain: Int?

    enum CodingKeys: String, CodingKey {
        case modelName = "model_name"
        case remain
    }
}

// MARK: - Unified internal balance representation

struct UnifiedBalance {
    let isAvailable: Bool
    let cnyTotal: Double
    let cnyGranted: Double
    let cnyToppedUp: Double
    let usdTotal: Double
    let rawJson: String       // keep raw for debug
}

// MARK: - Config

struct ApiKey: Codable {
    var name: String
    var key: String
    var platform: String = "deepseek"   // default legacy value
}

struct Config: Codable {
    var keys: [ApiKey] = []
    var active: String = ""
}

// MARK: - History

struct DayRecord: Codable {
    let date: String
    let startBalance: Double
    var endBalance: Double
}

// MARK: - Monitor App

class DeepSeekMonitor: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var timer: Timer?
    private var config = Config()
    private var cachedBalance: UnifiedBalance?
    private var errorMsg: String?
    private var lastRefresh = "从未"
    private var platformUnsupported: Platform?

    // Current resolved platform (derived from active key)
    private var currentPlatform: Platform { resolvePlatform(for: config.active) }

    // Config paths
    private let configDir = NSHomeDirectory() + "/.deepseek_monitor"
    private var configFile: String { configDir + "/config.json" }
    private var historyFile: String { configDir + "/history.json" }

    // --- Icon caches ---

    private var deepseekIcon: NSImage?
    private var zhipuIcon: NSImage?
    private var zhipuFallbackIcon: NSImage?
    private var kimiIcon: NSImage?
    private var kimiFallbackIcon: NSImage?
    private var minimaxIcon: NSImage?
    private var minimaxFallbackIcon: NSImage?
    private var longcatIcon: NSImage?
    private var longcatFallbackIcon: NSImage?
    private var combinedIcon: NSImage?
    private var keyIcons: [String: NSImage] = [:]
    private var loadingIcon: NSImage?
    private var errorIcon: NSImage?
    private var keyIcon: NSImage?

    // SF Symbol mapping for keys without custom icons
    private let keySymbolMap: [String: String] = [
        "qclaw": "wrench.and.screwdriver.fill",
        "gui":   "rectangle.3.group.fill",
        "kimi":  "k.circle.fill",
        "minimax": "m.circle.fill",
    ]

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        migrateConfigIfNeeded()
        loadConfig()
        setupMenuBar()
        refreshData()
        startTimer()
    }

    // MARK: - Config Migration

    /// Legacy config had no `platform` field on keys; default to "deepseek".
    func migrateConfigIfNeeded() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configFile)),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        guard var keysArr = json["keys"] as? [[String: Any]] else { return }

        var migrated = false
        for i in keysArr.indices {
            if keysArr[i]["platform"] == nil {
                keysArr[i]["platform"] = "deepseek"
                migrated = true
            }
        }
        if !migrated { return }

        json["keys"] = keysArr
        if let newData = try? JSONSerialization.data(withJSONObject: json) {
            try? newData.write(to: URL(fileURLWithPath: configFile))
        }
    }

    // MARK: - Config Load / Save

    func loadConfig() {
        if let data = try? Data(contentsOf: URL(fileURLWithPath: configFile)) {
            if let c = try? JSONDecoder().decode(Config.self, from: data) {
                config = c
                return
            }
            // legacy: single key format
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let key = json["api_key"] as? String, !key.isEmpty {
                config.keys = [ApiKey(name: "default", key: key)]
                config.active = "default"
            }
        }
        saveConfig()
    }

    func saveConfig() {
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true, attributes: nil)
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: URL(fileURLWithPath: configFile))
        }
    }

    var activeKey: String {
        config.keys.first(where: { $0.name == config.active })?.key ?? config.keys.first?.key ?? ""
    }

    var activeKeyName: String { config.active }

    func resolvePlatform(for keyName: String) -> Platform {
        if let k = config.keys.first(where: { $0.name == keyName }),
           let p = Platform(rawValue: k.platform) {
            return p
        }
        return .deepseek
    }

    // MARK: - Menu Bar Setup

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        }
        menu = NSMenu()
        statusItem.menu = menu

        // Load icons for all platforms
        deepseekIcon = loadIcon(configDir + "/deepseek_icon.png", size: 14)
        zhipuIcon   = loadIcon(configDir + "/zhipu_icon.png", size: 14)
        kimiIcon    = loadIcon(configDir + "/kimi_icon.png", size: 14)
        minimaxIcon = loadIcon(configDir + "/minimax_icon.png", size: 14)
        longcatIcon = loadIcon(configDir + "/longcat_icon.png", size: 14)

        // SF Symbol fallback for Zhipu (purple "Z" via symbol)
        let zhipuCfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        zhipuFallbackIcon = NSImage(systemSymbolName: "z.circle.fill", accessibilityDescription: "Zhipu")?
            .withSymbolConfiguration(zhipuCfg)

        // SF Symbol fallback for Kimi (blue "K")
        let kimiCfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        kimiFallbackIcon = NSImage(systemSymbolName: "k.circle.fill", accessibilityDescription: "Kimi")?
            .withSymbolConfiguration(kimiCfg)

        // SF Symbol fallback for MiniMax (orange "M")
        let minimaxCfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        minimaxFallbackIcon = NSImage(systemSymbolName: "m.circle.fill", accessibilityDescription: "MiniMax")?
            .withSymbolConfiguration(minimaxCfg)

        // SF Symbol fallback for LongCat (teal "L")
        let longcatCfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        longcatFallbackIcon = NSImage(systemSymbolName: "l.circle.fill", accessibilityDescription: "LongCat")?
            .withSymbolConfiguration(longcatCfg)

        preloadKeyIcons()
        rebuildCombinedIcon()

        // Preload status icons
        let iconCfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        loadingIcon = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)?
            .withSymbolConfiguration(iconCfg)
        errorIcon = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(iconCfg)
        keyIcon = NSImage(systemSymbolName: "key.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(iconCfg)

        setIcon(.loading)
    }

    // MARK: - Icon Helpers

    func loadIcon(_ path: String, size: CGFloat) -> NSImage? {
        guard let raw = NSImage(contentsOfFile: path) else { return nil }
        let maxDim = max(raw.size.width, raw.size.height)
        let scale = size / maxDim
        let drawW = raw.size.width * scale
        let drawH = raw.size.height * scale
        let fullSize = NSSize(width: 16, height: 16)
        let drawX = (fullSize.width - drawW) / 2
        let drawY = (fullSize.height - drawH) / 2
        let resized = NSImage(size: fullSize)
        resized.lockFocus()
        raw.draw(in: NSRect(x: drawX, y: drawY, width: drawW, height: drawH),
                 from: .zero, operation: .copy, fraction: 1.0)
        resized.unlockFocus()
        return resized
    }

    func currentPlatformIcon() -> NSImage? {
        switch currentPlatform {
        case .deepseek: return deepseekIcon
        case .zhipu:   return zhipuIcon ?? zhipuFallbackIcon ?? deepseekIcon
        case .kimi:    return kimiIcon ?? kimiFallbackIcon ?? deepseekIcon
        case .minimax: return minimaxIcon ?? minimaxFallbackIcon ?? deepseekIcon
        case .longcat: return longcatIcon ?? longcatFallbackIcon ?? deepseekIcon
        }
    }

    func preloadKeyIcons() {
        keyIcons.removeAll()
        for k in config.keys {
            let pngPath = configDir + "/\(k.name)_icon.png"
            if let icon = loadIcon(pngPath, size: 12) {
                keyIcons[k.name] = icon
                continue
            }
            if let symbolName = keySymbolMap[k.name],
               let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
                let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
                keyIcons[k.name] = image.withSymbolConfiguration(cfg)
            }
        }
    }

    func rebuildCombinedIcon() {
        let iconW: CGFloat = 16
        let keyW: CGFloat = 14
        let spacing: CGFloat = 2

        let activeKeys = config.keys.filter { keyIcons[$0.name] != nil }
        let count = activeKeys.count
        // Use the active-key's platform as the primary icon
        let primaryIcon = currentPlatformIcon()
        let totalW = iconW + CGFloat(count) * keyW + CGFloat(count) * spacing
        guard totalW > 0 else { combinedIcon = nil; return }

        let combined = NSImage(size: NSSize(width: totalW, height: iconW))
        combined.lockFocus()
        var x: CGFloat = 0
        if let icon = primaryIcon {
            icon.draw(in: NSRect(x: x, y: 0, width: iconW, height: iconW))
            x += iconW + spacing
        }
        for k in activeKeys {
            if let img = keyIcons[k.name] {
                let alpha: CGFloat = (k.name == config.active) ? 1.0 : 0.45
                img.draw(in: NSRect(x: x, y: 1, width: keyW, height: keyW),
                         from: .zero, operation: .sourceOver, fraction: alpha)
                x += keyW + spacing
            }
        }
        combined.unlockFocus()
        combinedIcon = combined
    }

    func makeCombinedIcon(left: NSImage?, right: NSImage?) -> NSImage? {
        let iconW: CGFloat = 16, iconH: CGFloat = 16
        let spacing: CGFloat = 2
        let totalW = (left != nil ? iconW : 0) + (left != nil && right != nil ? spacing : 0) + (right != nil ? iconW : 0)
        guard totalW > 0 else { return nil }

        let combined = NSImage(size: NSSize(width: totalW, height: iconH))
        combined.lockFocus()
        var x: CGFloat = 0
        if let left = left {
            left.draw(in: NSRect(x: x, y: 0, width: iconW, height: iconH))
            x += iconW + spacing
        }
        if let right = right {
            right.draw(in: NSRect(x: x, y: 0, width: iconW, height: iconH))
        }
        combined.unlockFocus()
        return combined
    }

    // MARK: - Icon States

    enum StatusState {
        case loading, error, noKey, unsupported
        case normal(balance: String)
        case warning(balance: String)
    }

    func setIcon(_ state: StatusState, balance: String = "") {
        guard let button = statusItem.button else { return }
        button.layer?.removeAnimation(forKey: "spin")

        switch state {
        case .loading:
            button.image = loadingIcon
            button.title = ""
            animateLoadingIcon()
        case .error:
            button.image = errorIcon
            button.title = ""
        case .noKey:
            button.image = keyIcon
            button.title = ""
        case .unsupported:
            button.image = currentPlatformIcon() ?? keyIcon
            button.title = "?"
        case .normal(let balance), .warning(let balance):
            button.image = currentPlatformIcon() ?? loadingIcon
            button.title = balance
        }

        button.imagePosition = .imageLeading
    }

    func animateLoadingIcon() {
        guard let button = statusItem.button, let _ = loadingIcon else { return }
        button.wantsLayer = true
        let animation = CABasicAnimation(keyPath: "transform.rotation")
        animation.fromValue = 0
        animation.toValue = 2 * Double.pi
        animation.duration = 1.0
        animation.repeatCount = .infinity
        button.layer?.add(animation, forKey: "spin")
    }

    // MARK: - Menu Building

    func rebuildMenu() {
        menu.removeAllItems()

        // Active key indicator with platform badge
        let platformBadge: String = {
            switch currentPlatform {
            case .zhipu:   return " 🟣"
            case .kimi:    return " 🟠"
            case .minimax: return " 🟡"
            case .longcat: return " 🔵"
            default:       return ""
            }
        }()
        let keyLabel = NSMenuItem(title: "🔑 当前: \(activeKeyName)\(platformBadge)", action: nil, keyEquivalent: "")
        menu.addItem(keyLabel)

        // Handle platform-without-balance-endpoint case honestly
        if platformUnsupported != nil {
            menu.addItem(NSMenuItem(title: "⚠️ \(currentPlatform.displayName) 未公开余额查询 API", action: nil, keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "请在网页控制台查看余额与用量", action: nil, keyEquivalent: ""))
            let openItem = NSMenuItem(title: "在浏览器中打开 \(currentPlatform.displayName) →", action: #selector(openPlatform), keyEquivalent: "")
            openItem.target = self
            menu.addItem(openItem)
            menu.addItem(NSMenuItem.separator())
            let refreshItem = NSMenuItem(title: "🔄 刷新 (上次: \(lastRefresh))", action: #selector(refreshData), keyEquivalent: "r")
            refreshItem.target = self
            menu.addItem(refreshItem)
            addKeySwitcher()
            addCommonActions()
            return
        }

        if let error = errorMsg {
            menu.addItem(NSMenuItem(title: "❌ 错误: \(error)", action: nil, keyEquivalent: ""))
            addKeySwitcher()
            addCommonActions()
            return
        }

        guard let bal = cachedBalance else {
            menu.addItem(NSMenuItem(title: "加载中...", action: nil, keyEquivalent: ""))
            addKeySwitcher()
            return
        }

        // Balance section
        let statusText = bal.isAvailable ? "✅ 余额充足" : "❌ 余额不足"
        menu.addItem(NSMenuItem(title: "账户状态: \(statusText)", action: nil, keyEquivalent: ""))

        // CNY
        if bal.cnyTotal > 0 || bal.cnyGranted > 0 || bal.cnyToppedUp > 0 {
            menu.addItem(NSMenuItem(title: "💰 CNY 余额: ¥\(fmt(bal.cnyTotal))", action: nil, keyEquivalent: ""))
            if bal.cnyGranted > 0 {
                menu.addItem(NSMenuItem(title: "   ├ 赠金: ¥\(fmt(bal.cnyGranted))", action: nil, keyEquivalent: ""))
            }
            if bal.cnyToppedUp > 0 {
                menu.addItem(NSMenuItem(title: "   └ 充值: ¥\(fmt(bal.cnyToppedUp))", action: nil, keyEquivalent: ""))
            }
        }

        // USD (if any)
        if bal.usdTotal > 0 {
            menu.addItem(NSMenuItem(title: "💵 USD 余额: $\(fmt(bal.usdTotal))", action: nil, keyEquivalent: ""))
        }

        menu.addItem(NSMenuItem.separator())

        // Daily & Monthly usage
        menu.addItem(NSMenuItem(title: "📊 今日用量", action: nil, keyEquivalent: ""))
        let history = loadHistory()
        let todayStr = ISO8601DateFormatter()
        todayStr.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        let today = todayStr.string(from: Date())

        let todayEntry = history.first(where: { $0.date == today })
        let todaySpend = max(0, (todayEntry?.startBalance ?? 0) - (todayEntry?.endBalance ?? 0))
        menu.addItem(NSMenuItem(title: "今日花费: ¥\(fmt4(todaySpend))", action: nil, keyEquivalent: ""))
        if todaySpend > 0.0001 {
            let estTokens = Int(todaySpend / currentPlatform.costPerMillionTokens * 1_000_000)
            menu.addItem(NSMenuItem(title: "预估 Token: ~\(formatNumber(estTokens))", action: nil, keyEquivalent: ""))
        }

        let monthPrefix = String(today.prefix(8))
        let monthSpend = history
            .filter { $0.date.hasPrefix(monthPrefix) }
            .reduce(0.0) { $0 + max(0, ($1.startBalance - $1.endBalance)) }
        if monthSpend > 0 {
            menu.addItem(NSMenuItem(title: "本月累计: ¥\(fmt4(monthSpend))", action: nil, keyEquivalent: ""))
        }

        menu.addItem(NSMenuItem.separator())

        // 7-day chart
        menu.addItem(NSMenuItem(title: "📅 近 7 天消费", action: nil, keyEquivalent: ""))
        let sevenDays = Array(history.sorted(by: { $0.date > $1.date }).prefix(7))
        let maxSpend = sevenDays.map { max(0, $0.startBalance - $0.endBalance) }.max() ?? 1

        for entry in sevenDays {
            let spend = max(0, entry.startBalance - entry.endBalance)
            let dayLabel = String(entry.date.suffix(5))
            let barLen = maxSpend > 0 ? Int(spend / maxSpend * 12) : 0
            let bar = String(repeating: "█", count: barLen) + String(repeating: "░", count: 12 - barLen)
            menu.addItem(NSMenuItem(title: "\(dayLabel) \(bar) ¥\(fmt4(spend))", action: nil, keyEquivalent: ""))
        }

        menu.addItem(NSMenuItem.separator())

        // Model distribution placeholder
        menu.addItem(NSMenuItem(title: "🤖 模型分布", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "⚠️ API 暂不提供此数据", action: nil, keyEquivalent: ""))
        let platformItem = NSMenuItem(title: "在平台面板中查看 →", action: #selector(openPlatform), keyEquivalent: "")
        platformItem.target = self
        menu.addItem(platformItem)

        menu.addItem(NSMenuItem.separator())

        // Refresh
        let refreshMenuItem = NSMenuItem(title: "🔄 刷新 (上次: \(lastRefresh))", action: #selector(refreshData), keyEquivalent: "r")
        refreshMenuItem.target = self
        menu.addItem(refreshMenuItem)

        addKeySwitcher()
        addCommonActions()
    }

    // MARK: - Key Switcher

    func addKeySwitcher() {
        menu.addItem(NSMenuItem.separator())

        let switchMenu = NSMenu()
        for k in config.keys {
            let plat = Platform(rawValue: k.platform) ?? .deepseek
            let badge: String
            switch plat {
            case .deepseek: badge = "🔵"
            case .zhipu:   badge = "🟣"
            case .kimi:    badge = "🟠"
            case .minimax: badge = "🟡"
            case .longcat: badge = "🩵"
            }
            let item = NSMenuItem(title: "\(badge) \(k.name)", action: #selector(switchKey(_:)), keyEquivalent: "")
            item.target = self
            item.state = (k.name == config.active) ? .on : .off
            switchMenu.addItem(item)
        }

        let switchItem = NSMenuItem(title: "🔀 切换 Key", action: nil, keyEquivalent: "")
        menu.addItem(switchItem)
        menu.setSubmenu(switchMenu, for: switchItem)
    }

    @objc func switchKey(_ sender: NSMenuItem) {
        // Extract name (strip emoji prefix like "🔵 " or "🟣 ")
        let rawTitle = sender.title
        let name = rawTitle.components(separatedBy: " ").last ?? rawTitle
        config.active = name
        saveConfig()
        cachedBalance = nil
        errorMsg = nil
        platformUnsupported = nil
        rebuildCombinedIcon()
        setIcon(.loading)
        refreshData()
    }

    // MARK: - Title Update

    func updateTitle() {
        guard let bal = cachedBalance else {
            setIcon(.loading)
            return
        }

        if bal.cnyTotal > 0 {
            let balance = "¥\(fmt(bal.cnyTotal))"
            setIcon(bal.isAvailable ? .normal(balance: balance) : .warning(balance: balance))
        } else if bal.usdTotal > 0 {
            let balance = "$\(fmt(bal.usdTotal))"
            setIcon(bal.isAvailable ? .normal(balance: balance) : .warning(balance: balance))
        } else {
            setIcon(bal.isAvailable ? .normal(balance: "") : .warning(balance: ""))
        }
    }

    // MARK: - Common Actions

    func addCommonActions() {
        menu.addItem(NSMenuItem.separator())

        let platformName = currentPlatform.displayName
        let platformItem = NSMenuItem(title: "🌐 打开 \(platformName) 平台", action: #selector(openPlatform), keyEquivalent: "")
        platformItem.target = self
        menu.addItem(platformItem)

        let settingsItem = NSMenuItem(title: "⚙️ 管理 API Keys...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let configDirItem = NSMenuItem(title: "📂 打开数据目录", action: #selector(openConfigDir), keyEquivalent: "")
        configDirItem.target = self
        menu.addItem(configDirItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出监控", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - API Calls

    @objc func refreshData() {
        let key = activeKey
        if key.isEmpty {
            errorMsg = "请先设置 API Key"
            setIcon(.noKey)
            rebuildMenu()
            return
        }

        let platform = currentPlatform
        platformUnsupported = nil
        guard let urlStr = platform.balanceURL, let url = URL(string: urlStr) else {
            // Platform doesn't expose a balance endpoint — show an honest status
            errorMsg = nil
            cachedBalance = nil
            lastRefresh = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            platformUnsupported = platform
            setIcon(.unsupported)
            rebuildMenu()
            return
        }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.setValue(platform.authHeader(key: key), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMsg = error.localizedDescription
                    self?.setIcon(.error)
                    self?.rebuildMenu()
                    return
                }

                guard let data = data, let httpResp = response as? HTTPURLResponse else {
                    self?.errorMsg = "无响应"
                    self?.setIcon(.error)
                    self?.rebuildMenu()
                    return
                }

                guard httpResp.statusCode == 200 else {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    let reason: String
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errObj = json["error"] as? [String: Any],
                       let msg = errObj["message"] as? String {
                        reason = msg
                    } else if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let msg = json["msg"] as? String {
                        reason = msg
                    } else {
                        reason = body.isEmpty ? "HTTP \(httpResp.statusCode)" : body
                    }
                    self?.errorMsg = reason
                    self?.setIcon(.error)
                    self?.rebuildMenu()
                    return
                }

                // Decode based on platform
                let result = self?.decodeResponse(data: data, platform: platform)

                switch result {
                case .some(.success(let unified)):
                    self?.errorMsg = nil
                    self?.cachedBalance = unified
                    self?.lastRefresh = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
                    self?.updateTitle()
                    self?.updateHistory(with: unified)
                    self?.rebuildMenu()
                case .some(.failure(let err)):
                    self?.errorMsg = err.message
                    self?.setIcon(.error)
                    self?.rebuildMenu()
                case .none:
                    self?.errorMsg = "内部错误: 解码结果为空"
                    self?.setIcon(.error)
                    self?.rebuildMenu()
                }
            }
        }.resume()
    }

// MARK: - Error type for decode

struct DecodeError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

    /// Decode raw API response into UnifiedBalance, handling per-platform formats.
    func decodeResponse(data: Data, platform: Platform) -> Result<UnifiedBalance, DecodeError> {
        let rawJson = String(data: data, encoding: .utf8) ?? "(binary)"

        switch platform {
        case .deepseek:
            guard let resp = try? JSONDecoder().decode(BalanceResponse.self, from: data) else {
                return .failure(DecodeError(message: "解析DeepSeek响应失败: \(rawJson.prefix(120))"))
            }
            let cny = resp.balanceInfos.first(where: { $0.currency == "CNY" })
            let usd = resp.balanceInfos.first(where: { $0.currency == "USD" })
            return .success(UnifiedBalance(
                isAvailable: resp.isAvailable,
                cnyTotal: Double(cny?.totalBalance ?? "0") ?? 0,
                cnyGranted: Double(cny?.grantedBalance ?? "0") ?? 0,
                cnyToppedUp: Double(cny?.toppedUpBalance ?? "0") ?? 0,
                usdTotal: Double(usd?.totalBalance ?? "0") ?? 0,
                rawJson: rawJson
            ))

        case .zhipu:
            // Try strategy 1: DeepSeek-compatible envelope (is_available + balance_infos)
            if let dsStyle = try? JSONDecoder().decode(BalanceResponse.self, from: data),
               !dsStyle.balanceInfos.isEmpty {
                let cny = dsStyle.balanceInfos.first(where: { $0.currency == "CNY" })
                let usd = dsStyle.balanceInfos.first(where: { $0.currency == "USD" })
                return .success(UnifiedBalance(
                    isAvailable: dsStyle.isAvailable,
                    cnyTotal: Double(cny?.totalBalance ?? "0") ?? 0,
                    cnyGranted: Double(cny?.grantedBalance ?? "0") ?? 0,
                    cnyToppedUp: Double(cny?.toppedUpBalance ?? "0") ?? 0,
                    usdTotal: Double(usd?.totalBalance ?? "0") ?? 0,
                    rawJson: rawJson
                ))
            }

            // Try strategy 2: Zhipu-specific envelope (code/success/data)
            if let env = try? JSONDecoder().decode(ZhipuBalanceEnvelope.self, from: data) {
                // Check error
                if let code = env.code, code != 200 {
                    return .failure(DecodeError(message: env.msg ?? "智谱API错误(code=\(code))"))
                }
                if env.success == false {
                    return .failure(DecodeError(message: env.msg ?? "智谱API返回失败"))
                }

                // Has balance_infos inside?
                if let infos = env.balanceInfos, !infos.isEmpty {
                    let cny = infos.first(where: { ($0.currency ?? "").uppercased().contains("CNY") ||
                                                   ($0.currency ?? "").isEmpty })
                    let total = Double(cny?.totalBalance ?? "0") ?? 0
                    let granted = Double(cny?.grantedBalance ?? "0") ?? 0
                    let topped = Double(cny?.toppedUpBalance ?? "0") ?? 0

                    // If still all zero but we have data field, try that too
                    if total == 0 && granted == 0 && topped == 0, let d = env.data {
                        return .success(UnifiedBalance(
                            isAvailable: true,
                            cnyTotal: d.totalBalance ?? d.balance ?? 0,
                            cnyGranted: d.grantedBalance ?? 0,
                            cnyToppedUp: d.toppedUpBalance ?? 0,
                            usdTotal: 0,
                            rawJson: rawJson
                        ))
                    }

                    return .success(UnifiedBalance(
                        isAvailable: env.isAvailable ?? true,
                        cnyTotal: total,
                        cnyGranted: granted,
                        cnyToppedUp: topped,
                        usdTotal: 0,
                        rawJson: rawJson
                    ))
                }

                // Flat data field only
                if let d = env.data {
                    return .success(UnifiedBalance(
                        isAvailable: true,
                        cnyTotal: d.totalBalance ?? d.balance ?? 0,
                        cnyGranted: d.grantedBalance ?? 0,
                        cnyToppedUp: d.toppedUpBalance ?? 0,
                        usdTotal: 0,
                        rawJson: rawJson
                    ))
                }
            }

            // Try strategy 3: Raw top-level numeric fields
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let balVal = numberFrom(json: json, keys: ["balance", "total_balance", "amount", "totalBalance"]) {
                let granted = numberFrom(json: json, keys: ["granted_balance", "grantedBalance"]) ?? 0
                let topped = numberFrom(json: json, keys: ["topped_up_balance", "toppedUpBalance"]) ?? 0
                return .success(UnifiedBalance(
                    isAvailable: balVal > 0,
                    cnyTotal: balVal,
                    cnyGranted: granted,
                    cnyToppedUp: topped,
                    usdTotal: 0,
                    rawJson: rawJson
                ))
            }

            return .failure(DecodeError(message: "无法解析智谱响应: \(rawJson.prefix(200))"))

        case .kimi:
            guard let resp = try? JSONDecoder().decode(KimiBalanceResponse.self, from: data) else {
                return .failure(DecodeError(message: "解析Kimi响应失败: \(rawJson.prefix(120))"))
            }
            // Check for API-level error
            if resp.code != 0 {
                return .failure(DecodeError(message: "Kimi API错误(code=\(resp.code))"))
            }
            let available = resp.data?.availableBalance ?? 0
            let voucher = resp.data?.voucherBalance ?? 0
            let cash = resp.data?.cashBalance ?? 0
            return .success(UnifiedBalance(
                isAvailable: available > 0,
                cnyTotal: available,
                cnyGranted: voucher,
                cnyToppedUp: cash,
                usdTotal: 0,
                rawJson: rawJson
            ))

        case .minimax:
            // MiniMax pay-as-you-go has no public balance REST endpoint.
            // This case should normally not be reached (balanceURL is nil),
            // but handle gracefully if future endpoint becomes available.
            return .failure(DecodeError(message: "MiniMax暂不支持API余额查询，请在网页控制台查看"))
        case .longcat:
            // LongCat free beta has no public balance REST endpoint.
            // This case should normally not be reached (balanceURL is nil),
            // but handle gracefully if future endpoint becomes available.
            return .failure(DecodeError(message: "LongCat暂不支持API余额查询，请在网页控制台查看"))
        }
    }

    /// Helper: extract a Double from dict trying multiple possible keys.
    private func numberFrom(json: [String: Any], keys: [String]) -> Double? {
        for k in keys {
            if let v = json[k] as? Double { return v }
            if let v = json[k] as? Int { return Double(v) }
            if let v = json[k] as? String { return Double(v) }
        }
        return nil
    }

    // MARK: - History

    func loadHistory() -> [DayRecord] {
        if let data = try? Data(contentsOf: URL(fileURLWithPath: historyFile)),
           let history = try? JSONDecoder().decode([DayRecord].self, from: data) {
            return history
        }
        return []
    }

    func updateHistory(with bal: UnifiedBalance) {
        var history = loadHistory()
        let todayStr = ISO8601DateFormatter()
        todayStr.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        let today = todayStr.string(from: Date())
        let cnyBal = bal.cnyTotal

        if let idx = history.firstIndex(where: { $0.date == today }) {
            history[idx].endBalance = cnyBal
        } else {
            history.append(DayRecord(date: today, startBalance: cnyBal, endBalance: cnyBal))
        }

        if history.count > 60 { history = Array(history.suffix(60)) }
        if let data = try? JSONEncoder().encode(history) {
            try? data.write(to: URL(fileURLWithPath: historyFile))
        }
    }

    // MARK: - Timer

    func startTimer() {
        timer = Timer.scheduledTimer(timeInterval: 300, target: self, selector: #selector(refreshData), userInfo: nil, repeats: true)
    }

    // MARK: - Actions

    @objc func openPlatform() {
        NSWorkspace.shared.open(URL(string: currentPlatform.platformURL)!)
    }

    @objc func openConfigDir() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: configDir)
    }

    @objc func openSettings() {
        let alert = NSAlert()
        alert.messageText = "管理 API Keys"

        let list = config.keys.enumerated().map { i, k -> String in
            let plat = Platform(rawValue: k.platform) ?? .deepseek
            let badge: String
            switch plat {
            case .deepseek: badge = "DS"
            case .zhipu:   badge = "ZP"
            case .kimi:    badge = "KM"
            case .minimax: badge = "MM"
            case .longcat: badge = "LC"
            }
            let maskedKey = masked(k.key)
            let activeMark = (k.name == config.active) ? " ← 当前" : ""
            return "\(i+1). [\(badge)] \(k.name): \(maskedKey)\(activeMark)"
        }.joined(separator: "\n")

        alert.informativeText = "\(list)\n\n输入格式: 名称=sk-xxx 或 名称=sk-xxx@platform\n平台: deepseek / zhipu\n每行一个 Key"

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: 110))
        scroll.hasVerticalScroller = true
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 100))
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        // Show with platform suffix
        textView.string = config.keys.map { "\($0.name)=\($0.key)@\($0.platform)" }.joined(separator: "\n")
        scroll.documentView = textView
        alert.accessoryView = scroll

        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")

        if alert.runModal() == .alertFirstButtonReturn {
            let lines = textView.string.split(separator: "\n", omittingEmptySubsequences: true)
            var newKeys: [ApiKey] = []
            for line in lines {
                let parts = String(line).split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    let namePart = parts[0].trimmingCharacters(in: .whitespaces)
                    let rhs = parts[1].trimmingCharacters(in: .whitespaces)
                    // Parse optional @platform suffix
                    var key = rhs
                    var platform = "deepseek"
                    if let atIdx = rhs.lastIndex(of: "@") {
                        let keyPrefix = rhs[rhs.startIndex..<atIdx]
                        let platSuffix = rhs[rhs.index(after: atIdx)...]
                        let platStr = String(platSuffix).trimmingCharacters(in: .whitespaces)
                        if ["deepseek", "zhipu", "kimi", "minimax", "longcat"].contains(platStr.lowercased()) {
                            key = String(keyPrefix)
                            platform = platStr.lowercased()
                        }
                    }
                    if !namePart.isEmpty && !key.isEmpty {
                        newKeys.append(ApiKey(name: namePart, key: key, platform: platform))
                    }
                }
            }

            if !newKeys.isEmpty {
                if !newKeys.contains(where: { $0.name == config.active }) {
                    config.active = newKeys.first!.name
                }
                config.keys = newKeys
                saveConfig()
                preloadKeyIcons()
                rebuildCombinedIcon()
                cachedBalance = nil
                refreshData()
            }
        }
    }

    func masked(_ key: String) -> String {
        if key.count <= 8 { return "****" }
        return String(key.prefix(4)) + "****" + String(key.suffix(4))
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Formatting

    func fmt(_ v: Double) -> String  { String(format: "%.2f", v) }
    func fmt4(_ v: Double) -> String { String(format: "%.4f", v) }
    func formatNumber(_ n: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: n), number: .decimal)
    }
}

// MARK: - Main
let app = NSApplication.shared
let monitor = DeepSeekMonitor()
app.delegate = monitor
app.run()
