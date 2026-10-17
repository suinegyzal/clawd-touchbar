import AppKit

@main
enum Main {
    @MainActor static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            Snapshot.write(to: args[i + 1])
            return
        }
        if let i = args.firstIndex(of: "--render-docs"), i + 1 < args.count {
            DocsArt.write(to: args[i + 1])
            return
        }
        if let i = args.firstIndex(of: "--render-gifs"), i + 1 < args.count {
            DocsGif.write(to: args[i + 1])
            return
        }
        if let i = args.firstIndex(of: "--render-usage"), i + 1 < args.count {
            DocsGif.writeUsage(to: args[i + 1])
            return
        }
        if let i = args.firstIndex(of: "--render-species"), i + 1 < args.count {
            SpeciesSheet.write(to: args[i + 1])
            return
        }
        if let i = args.firstIndex(of: "--render-reddit"), i + 1 < args.count {
            DocsGif.write(to: args[i + 1], square: true)
            return
        }
        let app = NSApplication.shared
        if args.contains("--desktop") { UserDefaults.standard.set(true, forKey: "desktopMode") }
        let delegate = AppDelegate(preview: args.contains("--preview"))
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSTouchBarDelegate, NSMenuDelegate {
    private enum Key {
        static let count = "petCount"
        static let big = "bigPixels"
        static let wide = "wideMode"
        static let controls = "showControls"
        static let metrics = "showMetrics"
        static let usage = "showUsage"
        static let levelHUD = "levelHUD"
        static let doneSound = "doneSound"
        static let source = "runnerSource"
        static let menuBarPet = "menuBarPet"
        static let desktop = "desktopMode"
        static let declined = "declinedClaudeConnect"
    }
    private static let barID = NSTouchBarItem.Identifier("com.local.ClaudeTouchBar.playground")
    private static let trayID = NSTouchBarItem.Identifier("com.local.ClaudeTouchBar.tray")
    private static let controlsID = NSTouchBarItem.Identifier("com.local.ClaudeTouchBar.controls")
    private static let metricsID = NSTouchBarItem.Identifier("com.local.ClaudeTouchBar.metrics")
    private static let usageID = NSTouchBarItem.Identifier("com.local.ClaudeTouchBar.usage")
    private static let controlWidth: CGFloat = 46
    private static let maxPets = 6

    private let previewMode: Bool
    private let defaults = UserDefaults.standard
    private let world = Playground()
    private let stats = SystemStats()
    private lazy var metricsView = MetricsView(stats: stats)
    private lazy var usageView = UsageView(stats: stats)
    private var statsTimer: Timer?
    private var statsTicks = 0
    /// 소리·밝기를 바꾸면 화면에 뜨는 Clawd
    private let levelHUD = LevelHUD()
    private let levelWatcher = LevelWatcher()
    /// Claude가 일을 마치면 울릴 macOS 소리 ("" = 끄기)
    private static let doneSounds = ["Glass", "Ping", "Pop", "Purr", "Hero", "Tink", "Submarine"]
    private var lastDoneSound = Date.distantPast
    private let runner = RunnerClock()
    private lazy var runnerImages = RunnerClock.menuBarImages(px: 1.5)
    private lazy var playground = PlaygroundView(world: world)
    private lazy var touchBar: NSTouchBar = {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [Self.barID]
        return bar
    }()
    private var trayItem: NSCustomTouchBarItem?
    private var statusItem: NSStatusItem?
    private var previewWindow: NSWindow?
    /// 화면 위 모드(Touch Bar 없는 맥): 떠다니는 Clawd 창들
    private var petWindows: [PetWindow] = []
    private var isShowing = false
    private var muteButton: NSButton?
    /// 밝기·소리 버튼 줄
    private lazy var controlPad: ControlPad = {
        let mute = controlButton("speaker.slash.fill", #selector(toggleMute), repeats: false)
        muteButton = mute
        syncMuteButton()
        return ControlPad(buttons: [
            controlButton("sun.min.fill", #selector(brightnessDown)),
            controlButton("sun.max.fill", #selector(brightnessUp)),
            mute,
            controlButton("speaker.wave.1.fill", #selector(volumeDown)),
            controlButton("speaker.wave.3.fill", #selector(volumeUp)),
        ], buttonWidth: Self.controlWidth)
    }()
    /// 놀이터 아이템. 버튼이 바로 옆이면 한 아이템에 붙여 강물이 끊기지 않게
    private lazy var barContainer = BarContainer(playground: playground)
    /// 버튼을 놀이터 아이템에 붙일지 (사이에 사용량·Mac 상태가 없을 때)
    private var padJoinsBar: Bool { hasControls && !hasUsage && !hasMetrics }

    /// 메뉴 맨 위 한 줄: 몇 마리 · Claude가 뭘 하는지
    private var statusLineItem: NSMenuItem!
    private var showItem: NSMenuItem!
    private var treatItem: NSMenuItem!
    private var addItem: NSMenuItem!
    private var removeItem: NSMenuItem!
    private var acknowledgeItem: NSMenuItem!
    private var usageItem: NSMenuItem!
    /// [Mac 상태 | Claude 사용량] 탭 판을 띄우는 창
    private lazy var usageWindow = UsageWindow(stats: stats) { [weak self] in self?.showCalibration() }
    private let ideasMenu = NSMenu()
    private var menuBarPet: MenuBarPet?
    /// 자주 안 바꾸는 것들은 메뉴 대신 설정 창에
    private lazy var settings = SettingsWindow { [weak self] in self?.settingsPanes() ?? [] }

    init(preview: Bool) {
        previewMode = preview
        super.init()
        defaults.register(defaults: [Key.count: 1, Key.big: true, Key.wide: false, Key.controls: true, Key.metrics: true, Key.usage: true, Key.levelHUD: true, Key.doneSound: "Glass", Key.menuBarPet: true])
    }

    private var petCount: Int {
        get { min(max(defaults.integer(forKey: Key.count), 1), Self.maxPets) }
        set { defaults.set(newValue, forKey: Key.count) }
    }
    private var desktopMode: Bool {
        get { defaults.bool(forKey: Key.desktop) }
        set { defaults.set(newValue, forKey: Key.desktop) }
    }
    private var desktopPixel: CGFloat { big ? 4 : 3 }
    private var big: Bool {
        get { defaults.bool(forKey: Key.big) }
        set { defaults.set(newValue, forKey: Key.big) }
    }
    private var wide: Bool {
        get { defaults.bool(forKey: Key.wide) }
        set { defaults.set(newValue, forKey: Key.wide) }
    }
    /// Touch Bar가 "확장된 Control Strip"·"기능 키" 모드면 앱 영역이 없어서 넓게 덮는 방식만 보인다.
    private var controlStripOnly: Bool {
        let mode = UserDefaults(suiteName: "com.apple.touchbar.agent")?.string(forKey: "PresentationModeGlobal") ?? "appWithControlStrip"
        return mode != "app" && mode != "appWithControlStrip"
    }
    private var useWide: Bool { wide || controlStripOnly }
    private var showControls: Bool {
        get { defaults.bool(forKey: Key.controls) }
        set { defaults.set(newValue, forKey: Key.controls) }
    }
    /// Control Strip까지 덮을 때는 밝기·소리 버튼을 직접 단다
    private var hasControls: Bool { useWide && showControls && !previewMode }
    private var runnerSource: RunnerSource {
        get { RunnerSource(rawValue: defaults.string(forKey: Key.source) ?? "") ?? .cpu }
        set { defaults.set(newValue.rawValue, forKey: Key.source) }
    }
    private var showMetrics: Bool {
        get { defaults.bool(forKey: Key.metrics) }
        set { defaults.set(newValue, forKey: Key.metrics) }
    }
    private var hasMetrics: Bool { showMetrics && !previewMode }
    private var showUsage: Bool {
        get { defaults.bool(forKey: Key.usage) }
        set { defaults.set(newValue, forKey: Key.usage) }
    }
    private var hasUsage: Bool { showUsage && !previewMode }
    private var showLevelHUD: Bool {
        get { defaults.bool(forKey: Key.levelHUD) }
        set { defaults.set(newValue, forKey: Key.levelHUD) }
    }
    /// Control Strip을 남겨 둘 때는 앱 영역(실제 폭에 맞춰 줄어듦), 덮을 때는 esc 자리만 빼고 전체.
    /// 옆에 붙는 아이템들 사이에는 8pt씩 간격이 생긴다.
    private var barWidth: CGFloat {
        var width: CGFloat = useWide ? 1004 : 685
        if hasControls { width -= ControlPad.width(buttonWidth: Self.controlWidth, count: 5) + 8 }
        if hasMetrics { width -= MetricsView.width + 8 }
        if hasUsage { width -= UsageView.width + 8 }
        return width - 6
    }

    // MARK: - 시작/종료

    func applicationDidFinishLaunching(_ notification: Notification) {
        ClaudeSetup.installScripts()
        // 처음 켤 때: Touch Bar 없는 맥이면 화면 위 모드를 기본으로
        if defaults.object(forKey: Key.desktop) == nil { defaults.set(!ClaudeSetup.hasTouchBar, forKey: Key.desktop) }
        world.px = big ? 2 : 1.5
        world.width = barWidth
        world.setPetCount(petCount)
        try? FileManager.default.createDirectory(at: ClaudeLink.directory, withIntermediateDirectories: true)
        world.species = Species.current
        levelHUD.species = Species.current
        world.link = ClaudeLink(pendingFile: ClaudeLink.pendingFile)
        world.link?.onFinish = { [weak self] in self?.playDoneSound() }
        world.ideas = IdeaBox()
        if !previewMode {
            menuBarPet = MenuBarPet(link: world.link, ideas: world.ideas)
            menuBarPet?.world.species = Species.current
            menuBarPet?.petCount = petCount
            if defaults.bool(forKey: Key.menuBarPet) { menuBarPet?.show() }
        }
        startStats()
        // 키보드나 다른 곳에서 소리·밝기를 바꿔도 Clawd가 바를 들어 보인다
        levelWatcher.onChange = { [weak self] kind, level in self?.levelChanged(kind, level: level) }
        if !previewMode { levelWatcher.start() }
        playground.preferredWidth = barWidth
        playground.onVisibilityChange = { [weak self] visible in
            guard let self, !self.previewMode else { return }
            self.isShowing = visible
        }
        setupStatusItem()

        if previewMode {
            showPreviewWindow()
        } else if desktopMode {
            showDesktop()
        } else {
            installTrayItem()
            showOnTouchBar()
        }
        if !previewMode && !ClaudeSetup.isConnected && !defaults.bool(forKey: Key.declined) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.offerConnection() }
        }
        // 확인·문서 그림용: --show-settings [탭 번호], --show-usage, --show-menu
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--show-settings") {
            let tab = args.indices.contains(i + 1) ? Int(args[i + 1]) : nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.settings.show(tab: tab) }
        }
        if args.contains("--show-usage") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.usageWindow.show() }
        }
        if args.contains("--show-menu") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.statusItem?.button?.performClick(nil) }   // 사용량 기록을 다 읽은 뒤
        }
    }

    // MARK: - Claude Code 연결 (터미널 없이)

    private func offerConnection() {
        let alert = NSAlert()
        alert.messageText = tr("Clawd를 Claude Code와 연결할까요?", "Connect Clawd to Claude Code?")
        alert.informativeText = tr("Claude Code 설정(~/.claude/settings.json)에 훅을 추가해서, Claude가 일하면 Clawd도 따라 움직이게 해요. 쓰던 다른 설정은 건드리지 않고, 바꾸기 전 원본은 settings.json.bak-clawd 로 남겨요. 메뉴 막대의 Clawd 메뉴에서 언제든 끊을 수 있어요.", "This adds hooks to your Claude Code settings (~/.claude/settings.json) so Clawd moves along when Claude works. Your other settings stay untouched, and the original is backed up as settings.json.bak-clawd. You can disconnect anytime from the Clawd menu in the menu bar.")
        alert.addButton(withTitle: tr("연결", "Connect"))
        alert.addButton(withTitle: tr("나중에", "Later"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            connectClaude()
        } else {
            defaults.set(true, forKey: Key.declined)
        }
    }

    private func connectClaude() {
        let alert = NSAlert()
        do {
            alert.messageText = tr("연결 완료", "Connected")
            alert.informativeText = try ClaudeSetup.connect()
            defaults.removeObject(forKey: Key.declined)
        } catch {
            alert.alertStyle = .warning
            alert.messageText = tr("연결하지 못했어요", "Couldn't connect")
            alert.informativeText = "\(error.localizedDescription)\n\n" + tr("~/.claude/settings.json 이 올바른 JSON인지 확인해 주세요.", "Please check that ~/.claude/settings.json is valid JSON.")
        }
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func toggleConnect() {
        if ClaudeSetup.isConnected {
            try? ClaudeSetup.disconnect()
            defaults.set(true, forKey: Key.declined)
        } else {
            connectClaude()
        }
    }

    private func toggleLogin() {
        ClaudeSetup.launchesAtLogin.toggle()
    }

    // MARK: - 화면 위 모드

    /// 두 마리가 가까이 지나치면 서로 인사한다 (한 쌍당 25초에 한 번)
    private func greetNeighbors() {
        let now = CACurrentMediaTime()
        for i in petWindows.indices {
            for j in petWindows.indices where j > i {
                let a = petWindows[i], b = petWindows[j]
                guard now - a.lastGreet > 25, now - b.lastGreet > 25 else { continue }
                let dx = b.screenCenter.x - a.screenCenter.x
                guard abs(dx) < 150, abs(b.screenCenter.y - a.screenCenter.y) < 90 else { continue }
                a.greet(toward: dx)
                b.greet(toward: -dx)
            }
        }
    }

    private func showDesktop() {
        while petWindows.count < petCount { addPetWindow() }
    }

    private func hideDesktop() {
        for w in petWindows { w.close() }
        petWindows = []
    }

    private func addPetWindow() {
        let w = PetWindow(px: desktopPixel, link: world.link, slot: petWindows.count)
        w.world.species = Species.current
        w.onAddPet = { [weak self] in self?.addPet() }
        w.onTreat = { [weak self] treat, source in
            guard let self else { return }
            for other in self.petWindows where other !== source && abs(other.screenCenter.x - source.screenCenter.x) < 700 {
                other.race(for: treat, in: source)
            }
        }
        w.onRemovePet = { [weak self] w in
            guard let self, self.petWindows.count > 1, let i = self.petWindows.firstIndex(where: { $0 === w }) else { return }
            self.petWindows.remove(at: i).close()
            PetLedger.shared.remove(at: i)
            for (slot, rest) in self.petWindows.enumerated() { rest.world.sessionOffset = slot; rest.slot = slot }
            self.petCount = self.petWindows.count
        }
        w.world.busy = world.busy
        if petWindows.isEmpty { w.world.ideas = world.ideas }   // 아이디어는 한 마리만 던진다
        petWindows.append(w)
    }

    private func toggleDesktop() {
        desktopMode.toggle()
        if desktopMode {
            if isShowing { hideFromTouchBar() }
            showDesktop()
        } else {
            hideDesktop()
            if trayItem == nil { installTrayItem() }
            showOnTouchBar()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        PetLedger.shared.saveIfNeeded()
        guard !previewMode else { return }
        TouchBarPrivate.dismiss(touchBar)
        TouchBarPrivate.setControlStripPresence(Self.trayID, false)
        if let trayItem { TouchBarPrivate.removeSystemTrayItem(trayItem) }
    }

    /// 1초마다 Mac 상태를 재서 대시보드와 Clawd(바쁠수록 빨리 달림)에 알려 준다
    private func startStats() {
        stats.sample()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.stats.sample()
            let busy = self.stats.value(for: self.runnerSource)
            self.world.busy = busy
            for w in self.petWindows { w.world.busy = busy }
            self.greetNeighbors()
            self.metricsView.busy = busy
            self.menuBarPet?.world.busy = busy
            self.metricsView.tick()
            self.usageView.tick()
            self.usageWindow.refresh()
            self.statsTicks += 1
            if self.statsTicks % 60 == 5 { UsageLimits.autoCalibrate(self.stats) }   // 상태줄이 공식 %를 주면 기준을 다시 맞춘다
        }
        RunLoop.main.add(timer, forMode: .common)
        statsTimer = timer

        // RunCat처럼 메뉴 막대와 대시보드의 Clawd가 바쁜 만큼 빨리 달린다
        runner.busy = { [weak self] in self.map { $0.stats.value(for: $0.runnerSource) } ?? 0 }
        runner.onFrame = { [weak self] frame in
            guard let self else { return }
            self.statusItem?.button?.image = self.runnerImages[frame]
            if self.metricsView.window != nil { self.metricsView.runnerFrame = frame }
        }
        runner.start()
    }

    // MARK: - Touch Bar

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case Self.barID:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = barContainer
            return item
        case Self.metricsID:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = metricsView
            return item
        case Self.usageID:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = usageView
            return item
        case Self.controlsID:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = controlPad
            return item
        default:
            return nil
        }
    }

    /// 누르고 있으면 계속 조절되는 밝기·소리 버튼
    private func controlButton(_ symbol: String, _ action: Selector, repeats: Bool = true) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: symbol) ?? NSImage()
        let button = NSButton(image: image, target: self, action: action)
        if repeats {
            button.isContinuous = true
            button.setPeriodicDelay(0.35, interval: 0.08)
        }
        return button
    }

    private func syncMuteButton() {
        muteButton?.bezelColor = SystemControls.isMuted ? Palette.accent : nil
    }

    @objc private func brightnessDown() { changeBrightness(-1) }
    @objc private func brightnessUp() { changeBrightness(1) }
    @objc private func volumeDown() { changeVolume(-1) }
    @objc private func volumeUp() { changeVolume(1) }

    private func changeBrightness(_ direction: Float) {
        guard let level = SystemControls.stepBrightness(direction) else { return }
        levelChanged(.brightness, level: level)
    }

    /// 소리·밝기가 바뀌었다: Touch Bar의 Clawd가 바를 들고, 켜 두었으면 화면에도 큰 Clawd가 나온다
    private func levelChanged(_ kind: Playground.Gauge.Kind, level: Float) {
        levelWatcher.remember()
        world.showGauge(kind, level: level)
        if showLevelHUD && !previewMode { levelHUD.show(kind, level: level) }
    }

    private func changeVolume(_ direction: Float) {
        guard let level = SystemControls.stepVolume(direction) else { return }
        levelChanged(SystemControls.isMuted ? .muted : .volume, level: level)
        syncMuteButton()
    }

    @objc private func toggleMute() {
        let muted = SystemControls.toggleMute()
        levelChanged(muted ? .muted : .volume, level: muted ? 0 : SystemControls.volume ?? 0)
        syncMuteButton()
    }

    /// Control Strip에 작은 Clawd 버튼을 달아서, 눌러서 놀이터를 열고 닫을 수 있게 한다.
    private func installTrayItem() {
        let item = NSCustomTouchBarItem(identifier: Self.trayID)
        item.view = NSButton(image: Species.current.icon(px: 1.5), target: self, action: #selector(toggleTouchBar))
        TouchBarPrivate.addSystemTrayItem(item)
        TouchBarPrivate.setControlStripPresence(Self.trayID, true)
        trayItem = item
    }

    private func showOnTouchBar() {
        touchBar.defaultItemIdentifiers = [Self.barID] + (hasUsage ? [Self.usageID] : []) + (hasMetrics ? [Self.metricsID] : [])
            + (hasControls && !padJoinsBar ? [Self.controlsID] : [])
        playground.preferredWidth = barWidth
        barContainer.setPad(padJoinsBar ? controlPad : nil)
        TouchBarPrivate.showsCloseBoxWhenFrontmost(true)
        TouchBarPrivate.present(touchBar, placement: useWide ? 1 : 0, trayItem: Self.trayID)
        playground.start()
        isShowing = true
    }

    private func hideFromTouchBar() {
        TouchBarPrivate.minimize(touchBar)
        playground.stop()
        isShowing = false
    }

    @objc private func toggleTouchBar() {
        if previewMode {
            previewWindow?.makeKeyAndOrderFront(nil)
            return
        }
        isShowing ? hideFromTouchBar() : showOnTouchBar()
    }

    private func showPreviewWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: barWidth, height: 30),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = tr("Clawd Pet 미리보기", "Clawd Pet Preview")
        window.isReleasedWhenClosed = false
        window.contentView = playground
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        previewWindow = window
    }

    // MARK: - 메뉴 막대

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = runnerImages[0]
        item.button?.toolTip = "Clawd Pet"
        item.menu = makeMenu()
        statusItem = item
    }

    /// 메뉴 막대 메뉴: 자주 하는 것만. 사용량과 설정은 창으로 연다. 언어를 바꾸면 새로 만든다.
    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusLineItem = menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
        statusLineItem.isEnabled = false
        menu.addItem(.separator())
        showItem = menu.addItem(withTitle: tr("Touch Bar에 보이기", "Show on Touch Bar"), action: #selector(toggleTouchBar), keyEquivalent: "")
        treatItem = menu.addItem(withTitle: "", action: #selector(dropTreat), keyEquivalent: "")
        addItem = menu.addItem(withTitle: "", action: #selector(addPet), keyEquivalent: "")
        removeItem = menu.addItem(withTitle: "", action: #selector(removePet), keyEquivalent: "")
        menu.addItem(withTitle: tr("💡 아이디어", "💡 Ideas"), action: nil, keyEquivalent: "").submenu = ideasMenu
        acknowledgeItem = menu.addItem(withTitle: "", action: #selector(acknowledgeAll), keyEquivalent: "")
        menu.addItem(.separator())
        usageItem = menu.addItem(withTitle: "", action: #selector(openUsage), keyEquivalent: "u")
        menu.addItem(withTitle: tr("설정…", "Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: tr("종료", "Quit"), action: #selector(quit), keyEquivalent: "q")
        for menuItem in menu.items where menuItem.action != nil { menuItem.target = self }
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu !== ideasMenu else { return }
        rebuildIdeasMenu()
        let name = Species.current.title
        statusLineItem.title = "\(name) × \(petTotal)" + (world.link.map { " · " + $0.summaryLine } ?? "")
        // 화면 위 모드에선 Touch Bar를 쓰지 않는다
        showItem.isHidden = desktopMode
        showItem.state = isShowing || previewMode ? .on : .off
        treatItem.title = Species.current.treatTitle
        addItem.title = tr("\(name) 한 마리 더", "Add a \(name)")
        addItem.isEnabled = petTotal < Self.maxPets
        removeItem.title = tr("\(name) 한 마리 보내기", "Send a \(name) home")
        removeItem.isEnabled = petTotal > 1
        // 확인 안 한 완료 알림이 있을 때만
        let unread = world.link?.unreadDones ?? 0
        acknowledgeItem.isHidden = unread == 0
        acknowledgeItem.title = tr("완료 알림 \(unread)개 모두 확인", unread == 1 ? "Mark 1 done notice read" : "Mark \(unread) done notices read")
        // 창을 열지 않아도 한도 %는 한눈에
        let five = UsageLimits.fiveHour(stats).percent, week = UsageLimits.weekly(stats).percent
        let glance = [five.map { tr("5시간 ", "5h ") + $0 }, week.map { tr("주간 ", "week ") + $0 }].compactMap { $0 }.joined(separator: " · ")
        let title = NSMutableAttributedString(string: tr("사용량·Mac 상태 보기…", "Usage & Mac stats…"), attributes: [.font: NSFont.menuFont(ofSize: 0)])
        if !glance.isEmpty {
            title.append(NSAttributedString(string: "   " + glance, attributes: [.font: NSFont.menuFont(ofSize: 0), .foregroundColor: NSColor.secondaryLabelColor]))
        }
        usageItem.attributedTitle = title
    }

    @objc private func openUsage() {
        usageWindow.show()
    }

    // MARK: - 설정 창

    @objc private func openSettings() {
        settings.show()
    }

    /// 지금 몇 마리인지 (Touch Bar든 화면 위든)
    private var petTotal: Int { desktopMode ? petWindows.count : world.pets.count }

    private func settingsPanes() -> [SettingsPane] {
        typealias Option = SettingRow.Option
        let species = Species.allCases.map { Option(title: $0.title, image: $0.icon(px: $0 == .clawd ? 1 : 1.5, outline: true), value: $0.rawValue) }
        let languages = L10n.Choice.allCases.map { choice -> Option in
            switch choice {
            case .auto: return Option(title: tr("자동 (Mac 언어 따라)", "Auto (match Mac)"), value: choice.rawValue)
            case .english: return Option(title: "English", value: choice.rawValue)
            case .korean: return Option(title: "한국어", value: choice.rawValue)
            }
        }
        let livesOn = { [weak self] in self?.desktopMode == true ? "desktop" : "touchBar" }
        let setLivesOn = { [weak self] (value: String) -> Void in self?.setDesktopMode(value == "desktop") }
        let general = SettingsPane(title: tr("일반", "General"), symbol: "gearshape", rows: [
            SettingRow(label: tr("캐릭터", "Character"),
                       control: .popup(species, get: { Species.current.rawValue },
                                       set: { [weak self] in Species(rawValue: $0).map { self?.setSpecies($0) } })),
            SettingRow(label: tr("크기", "Size"),
                       control: .toggle(tr("크게 보기", "Bigger"), get: { [weak self] in self?.big ?? true }, set: { [weak self] _ in self?.toggleBig() })),
            SettingRow(label: tr("사는 곳", "Lives on"),
                       control: .radio(Option(title: "Touch Bar", value: "touchBar"), get: livesOn, set: setLivesOn),
                       note: { ClaudeSetup.hasTouchBar ? nil : tr("이 Mac에는 Touch Bar가 없어요", "This Mac has no Touch Bar") },
                       enabled: { [weak self] in self?.previewMode == false }),
            SettingRow(control: .radio(Option(title: tr("화면 위에 띄우기", "Floating on screen"), value: "desktop"), get: livesOn, set: setLivesOn),
                       enabled: { [weak self] in self?.previewMode == false }),
            SettingRow(control: .toggle(tr("메뉴 막대에서도 돌아다니기", "Also roam the menu bar"),
                                        get: { [weak self] in self?.menuBarPet?.isShowing == true }, set: { [weak self] _ in self?.toggleMenuBarPet() }),
                       enabled: { [weak self] in self?.menuBarPet != nil }),
            SettingRow(label: tr("달리는 기준", "Runs with"),
                       control: .popup(RunnerSource.allCases.map { Option(title: $0.title, value: $0.rawValue) },
                                       get: { [weak self] in self?.runnerSource.rawValue ?? "" },
                                       set: { [weak self] in RunnerSource(rawValue: $0).map { self?.setRunnerSource($0) } }),
                       note: { tr("Mac이 바쁠수록 빨리 달려요. 메뉴 막대 아이콘도 같은 박자로", "The busier your Mac, the faster it runs, menu bar icon included") }),
            SettingRow(label: tr("소리·밝기", "Volume & brightness"),
                       control: .toggle(tr("바꿀 때 화면에도 크게 보이기", "Also show big on screen when changed"),
                                        get: { [weak self] in self?.showLevelHUD ?? true }, set: { [weak self] _ in self?.toggleLevelHUD() }),
                       note: { tr("Dock 바로 위에서 바를 들고 2초쯤 보였다 사라져요", "Holds the level bar just above the Dock for about 2 seconds") },
                       enabled: { [weak self] in self?.previewMode == false }),
            SettingRow(label: "언어 · Language",   // 어느 언어로 보고 있든 찾을 수 있게
                       control: .popup(languages, get: { L10n.choice.rawValue },
                                       set: { [weak self] in L10n.Choice(rawValue: $0).map { self?.setLanguage($0) } })),
            SettingRow(label: tr("시작", "Startup"),
                       control: .toggle(tr("로그인할 때 자동 실행", "Open at login"), get: { ClaudeSetup.launchesAtLogin },
                                        set: { [weak self] _ in self?.toggleLogin() }),
                       enabled: { ClaudeSetup.canAutoLaunch }),
        ])

        let touchBarOnly = { [weak self] in self.map { !$0.previewMode && !$0.desktopMode } ?? false }
        let touchBar = SettingsPane(title: "Touch Bar", symbol: "slider.horizontal.below.rectangle", rows: [
            SettingRow(label: tr("폭", "Width"),
                       control: .toggle(tr("넓게 쓰기 (Control Strip 가리기)", "Full width (cover the Control Strip)"),
                                        get: { [weak self] in self?.useWide ?? false }, set: { [weak self] _ in self?.toggleWide() }),
                       note: { [weak self] in
                           guard let self else { return nil }
                           if self.desktopMode { return tr("지금은 화면 위에 띄우는 중이라 Touch Bar를 쓰지 않아요", "Clawd is floating on screen now, so the Touch Bar isn't used") }
                           return self.controlStripOnly ? tr("Touch Bar가 확장된 Control Strip 모드라서 늘 넓게 보여요", "Your Touch Bar uses the Expanded Control Strip, so it's always full width") : nil
                       },
                       enabled: { [weak self] in touchBarOnly() && self?.controlStripOnly == false }),
            SettingRow(label: tr("옆에 함께", "Next to Clawd"),
                       control: .toggle(tr("Claude 사용량", "Claude usage"), get: { [weak self] in self?.showUsage ?? true },
                                        set: { [weak self] _ in self?.toggleUsageBar() }),
                       enabled: touchBarOnly),
            SettingRow(control: .toggle(tr("Mac 상태", "Mac stats"), get: { [weak self] in self?.showMetrics ?? true },
                                        set: { [weak self] _ in self?.toggleMetrics() }),
                       enabled: touchBarOnly),
            SettingRow(control: .toggle(tr("밝기·소리 버튼", "Brightness & volume buttons"), get: { [weak self] in self?.showControls ?? true },
                                        set: { [weak self] _ in self?.toggleControls() }),
                       note: { tr("넓게 쓸 때 Control Strip 대신 달아요", "Shown in full width, in place of the Control Strip") },
                       enabled: { [weak self] in touchBarOnly() && self?.useWide == true }),
        ])

        let soundOptions = ([""] + Self.doneSounds).map { Option(title: $0.isEmpty ? tr("끄기", "Off") : $0, value: $0) }
        let claude = SettingsPane(title: "Claude", symbol: "sparkle", rows: [
            SettingRow(label: tr("Claude Code", "Claude Code"),
                       control: .actions(status: { ClaudeSetup.isConnected ? tr("✓ 연결됨", "✓ Connected") : tr("연결 안 됨", "Not connected") },
                                         [SettingRow.Action(title: { ClaudeSetup.isConnected ? tr("연결 끊기", "Disconnect") : tr("연결하기", "Connect") },
                                                            run: { [weak self] in self?.toggleConnect() })]),
                       note: { tr("훅을 넣어 Claude가 일하면 따라 움직여요. 새로 시작한 세션부터 적용돼요", "Adds hooks so Clawd follows Claude. Applies to sessions started afterwards") }),
            SettingRow(label: tr("완료 소리", "Done sound"),
                       control: .popup(soundOptions, get: { [weak self] in self?.defaults.string(forKey: Key.doneSound) ?? "" },
                                       set: { [weak self] in self?.setDoneSound($0) }),
                       note: { tr("Claude가 일을 마치면 울려요. 고르면 미리 들려줘요", "Plays when Claude finishes. Picking one plays a preview") }),
            SettingRow(label: tr("사용량 한도", "Usage limits"),
                       control: .actions(status: nil, [
                           SettingRow.Action(title: { tr("한도 맞추기…", "Calibrate…") }, run: { [weak self] in self?.showCalibration() }),
                           SettingRow.Action(title: { tr("claude.ai 사용량 열기", "Open claude.ai usage") },
                                             run: { NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!) }),
                       ]),
                       note: { [weak self] in self?.calibrationNote() }),
        ])
        return [general, touchBar, claude]
    }

    /// 한도를 무엇으로 맞췄는지
    private func calibrationNote() -> String {
        if let usage = stats.claude, usage.isFresh, usage.sevenDay != nil {
            return tr("터미널 claude의 상태줄에서 공식 %를 받고 있어요", "Getting the official % from the claude status line")
        }
        if let calibration = UsageCalibration.current, calibration.weeklyLimit != nil {
            let day = calibration.updated.formatted(.dateTime.month(.defaultDigits).day().locale(Locale(identifier: tr("ko_KR", "en_US"))))
            return calibration.fromStatusLine
                ? tr("\(day)에 터미널 상태줄로 저절로 맞췄어요. claude.ai와 다르면 다시 맞춰 주세요", "Synced from the claude status line on \(day). Calibrate again if it drifts from claude.ai")
                : tr("\(day)에 맞췄어요. claude.ai와 다르면 다시 맞춰 주세요", "Calibrated on \(day). Calibrate again if it drifts from claude.ai")
        }
        return tr("claude.ai의 주간 %를 한 번 넣으면 계속 따라가요. 터미널에서 claude를 쓰면 저절로 맞춰져요", "Enter your weekly % from claude.ai once to keep tracking it. Using claude in a terminal syncs it automatically")
    }

    // MARK: - 설정 바꾸기

    private func setLanguage(_ choice: L10n.Choice) {
        guard choice != L10n.choice else { return }
        L10n.choice = choice
        // 아이디어 하위 메뉴는 계속 쓰니까 옛 메뉴에서 떼어 낸다 (한 메뉴는 한 곳에만 달 수 있다)
        statusItem?.menu?.items.forEach { if $0.submenu === ideasMenu { $0.submenu = nil } }
        statusItem?.menu = makeMenu()
        previewWindow?.title = tr("Clawd Pet 미리보기", "Clawd Pet Preview")
        for place in [world, menuBarPet?.world] + petWindows.map(\.world) { place?.relocalize() }
        // 설정 창도 새 말로 (이 함수는 설정 창의 팝업에서 불리므로 다음 차례에)
        DispatchQueue.main.async { [weak self] in
            self?.settings.rebuild()
            self?.usageWindow.rebuild()
        }
    }

    private func setDesktopMode(_ on: Bool) {
        guard on != desktopMode else { return }
        toggleDesktop()
    }

    private func setRunnerSource(_ source: RunnerSource) {
        runnerSource = source
        world.busy = stats.value(for: source)
        metricsView.busy = world.busy
    }

    // MARK: - 한도 맞추기

    private func showCalibration() {
        CalibrationDialog.run(stats: stats)
    }

    /// 💡 아이디어 메뉴: 최근 아이디어(● = 아직 안 봄), 하나 던지기, 보고서 폴더
    private func rebuildIdeasMenu() {
        ideasMenu.removeAllItems()
        ideasMenu.autoenablesItems = false
        guard let box = world.ideas else { return }
        box.reload()
        if box.ideas.isEmpty {
            ideasMenu.addItem(withTitle: tr("아직 아이디어가 없어요 (리서치 루틴이 3시간마다 채워요)", "No ideas yet (an idea routine fills this up)"), action: nil, keyEquivalent: "").isEnabled = false
        }
        for idea in box.ideas.prefix(12) {
            let item = ideasMenu.addItem(withTitle: (box.isSeen(idea) ? "" : "● ") + idea.topic + " · " + idea.title,
                                         action: #selector(openIdea(_:)), keyEquivalent: "")
            item.representedObject = idea.id
            item.toolTip = idea.detail
            item.target = self
        }
        ideasMenu.addItem(.separator())
        let pitch = ideasMenu.addItem(withTitle: tr("지금 하나 던져 줘", "Pitch one now"), action: #selector(pitchIdea), keyEquivalent: "")
        pitch.target = self
        pitch.isEnabled = !box.unseen.isEmpty
        ideasMenu.addItem(withTitle: tr("리서치 보고서 폴더 열기", "Open research reports folder"), action: #selector(openReports), keyEquivalent: "").target = self
    }

    @objc private func openIdea(_ sender: NSMenuItem) {
        guard let box = world.ideas, let idea = box.ideas.first(where: { $0.id == sender.representedObject as? String }) else { return }
        box.markSeen(idea)
        IdeaBox.open(idea)
    }

    @objc private func pitchIdea() {
        if desktopMode { petWindows.first?.world.pitchIdeaNow(); return }
        if !isShowing && !previewMode { showOnTouchBar() }
        world.pitchIdeaNow()
        menuBarPet?.world.pitchIdeaNow()
    }

    @objc private func openReports() {
        let folder = world.ideas?.ideas.first?.report.map { URL(fileURLWithPath: $0).deletingLastPathComponent() }
        NSWorkspace.shared.open(folder ?? IdeaBox.file.deletingLastPathComponent())
    }

    @objc private func acknowledgeAll() {
        world.acknowledgeAll()
    }

    @objc private func dropTreat() {
        if desktopMode { petWindows.randomElement()?.giveTreat(); return }
        if !isShowing && !previewMode { showOnTouchBar() }
        world.dropTreat()
        menuBarPet?.world.dropTreat()
    }

    @objc private func addPet() {
        if desktopMode {
            guard petWindows.count < Self.maxPets else { return }
            addPetWindow()
            petCount = petWindows.count
            return
        }
        guard world.pets.count < Self.maxPets else { return }
        world.addPet()
        petCount = world.pets.count
        menuBarPet?.world.addPet()
        menuBarPet?.petCount = petCount
    }

    @objc private func removePet() {
        if desktopMode {
            guard petWindows.count > 1 else { return }
            petWindows.removeLast().close()
            PetLedger.shared.remove(at: petWindows.count)
            petCount = petWindows.count
            return
        }
        guard world.pets.count > 1 else { return }
        world.setPetCount(world.pets.count - 1)
        petCount = world.pets.count
        menuBarPet?.world.setPetCount(petCount)
        menuBarPet?.petCount = petCount
    }

    private func toggleBig() {
        big.toggle()
        world.px = big ? 2 : 1.5
        for w in petWindows { w.setPixel(desktopPixel) }
    }

    private func toggleMenuBarPet() {
        guard let menuBarPet else { return }
        let show = !menuBarPet.isShowing
        defaults.set(show, forKey: Key.menuBarPet)
        show ? menuBarPet.show() : menuBarPet.hide()
    }

    private func toggleMetrics() {
        showMetrics.toggle()
        representIfShowing()
    }

    // MARK: - 캐릭터

    private func setSpecies(_ species: Species) {
        Species.current = species
        for place in [world, menuBarPet?.world] + petWindows.map(\.world) { place?.species = species }
        levelHUD.species = species
        runnerImages = RunnerClock.menuBarImages(px: 1.5, species: species)
        statusItem?.button?.image = runnerImages[runner.frame]
        (trayItem?.view as? NSButton)?.image = species.icon(px: 1.5)
        barContainer.refresh()
        metricsView.needsDisplay = true
    }

    // MARK: - 완료 알림 소리

    private func playDoneSound() {
        guard !previewMode, let name = defaults.string(forKey: Key.doneSound), !name.isEmpty,
              Date().timeIntervalSince(lastDoneSound) > 1.5 else { return }   // 여러 세션이 한꺼번에 끝나도 한 번만
        lastDoneSound = Date()
        NSSound(named: NSSound.Name(name))?.play()
    }

    private func setDoneSound(_ name: String) {
        defaults.set(name, forKey: Key.doneSound)
        if !name.isEmpty { NSSound(named: NSSound.Name(name))?.play() }   // 미리 듣기
    }

    private func toggleLevelHUD() {
        showLevelHUD.toggle()
        // 켜자마자 어떻게 보이는지 한 번 보여 준다
        if showLevelHUD, let volume = SystemControls.volume { levelHUD.show(SystemControls.isMuted ? .muted : .volume, level: SystemControls.isMuted ? 0 : volume) }
    }

    private func toggleUsageBar() {
        showUsage.toggle()
        representIfShowing()
    }

    private func toggleControls() {
        showControls.toggle()
        representIfShowing()
    }

    private func toggleWide() {
        wide.toggle()
        representIfShowing()
    }

    private func representIfShowing() {
        guard isShowing else { return }
        TouchBarPrivate.dismiss(touchBar)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.showOnTouchBar() }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
