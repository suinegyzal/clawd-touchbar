import AppKit

@main
enum Main {
    @MainActor static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            Snapshot.write(to: args[i + 1])
            return
        }
        let app = NSApplication.shared
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
        static let source = "runnerSource"
        static let menuBarPet = "menuBarPet"
    }
    private static let barID = NSTouchBarItem.Identifier("com.local.ClaudeTouchBar.playground")
    private static let trayID = NSTouchBarItem.Identifier("com.local.ClaudeTouchBar.tray")
    private static let brightnessID = NSTouchBarItem.Identifier("com.local.ClaudeTouchBar.brightness")
    private static let volumeID = NSTouchBarItem.Identifier("com.local.ClaudeTouchBar.volume")
    private static let metricsID = NSTouchBarItem.Identifier("com.local.ClaudeTouchBar.metrics")
    private static let controlWidth: CGFloat = 46
    private static let maxPets = 6

    private let previewMode: Bool
    private let defaults = UserDefaults.standard
    private let world = Playground()
    private let stats = SystemStats()
    private lazy var metricsView = MetricsView(stats: stats)
    private var statsTimer: Timer?
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
    private var isShowing = false
    private var muteButton: NSButton?

    private var countItem: NSMenuItem!
    private var linkItem: NSMenuItem!
    private var showItem: NSMenuItem!
    private var addItem: NSMenuItem!
    private var removeItem: NSMenuItem!
    private var bigItem: NSMenuItem!
    private var wideItem: NSMenuItem!
    private var controlsItem: NSMenuItem!
    private var metricsItem: NSMenuItem!
    private var statsLines: [NSMenuItem] = []
    private let ideasMenu = NSMenu()
    private var menuBarPet: MenuBarPet?
    private var menuBarPetItem: NSMenuItem!
    private var sourceItems: [NSMenuItem] = []

    init(preview: Bool) {
        previewMode = preview
        super.init()
        defaults.register(defaults: [Key.count: 1, Key.big: true, Key.wide: false, Key.controls: true, Key.metrics: true, Key.menuBarPet: true])
    }

    private var petCount: Int {
        get { min(max(defaults.integer(forKey: Key.count), 1), Self.maxPets) }
        set { defaults.set(newValue, forKey: Key.count) }
    }
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
    /// Control Strip을 남겨 둘 때는 앱 영역(실제 폭에 맞춰 줄어듦), 덮을 때는 esc 자리만 빼고 전체.
    /// 옆에 붙는 아이템들 사이에는 8pt씩 간격이 생긴다.
    private var barWidth: CGFloat {
        var width: CGFloat = useWide ? 1004 : 685
        if hasControls { width -= (Self.controlWidth + 8) * 5 }
        if hasMetrics { width -= MetricsView.width + 8 }
        return width - 6
    }

    // MARK: - 시작/종료

    func applicationDidFinishLaunching(_ notification: Notification) {
        world.px = big ? 2 : 1.5
        world.width = barWidth
        world.setPetCount(petCount)
        try? FileManager.default.createDirectory(at: ClaudeLink.directory, withIntermediateDirectories: true)
        world.link = ClaudeLink(pendingFile: ClaudeLink.pendingFile)
        world.ideas = IdeaBox()
        if !previewMode {
            menuBarPet = MenuBarPet(link: world.link, ideas: world.ideas)
            menuBarPet?.petCount = petCount
            if defaults.bool(forKey: Key.menuBarPet) { menuBarPet?.show() }
        }
        startStats()
        playground.preferredWidth = barWidth
        playground.onVisibilityChange = { [weak self] visible in
            guard let self, !self.previewMode else { return }
            self.isShowing = visible
        }
        setupStatusItem()

        if previewMode {
            showPreviewWindow()
        } else {
            installTrayItem()
            showOnTouchBar()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
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
            self.metricsView.busy = busy
            self.menuBarPet?.world.busy = busy
            self.metricsView.tick()
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
            item.view = playground
            return item
        case Self.metricsID:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = metricsView
            return item
        case Self.brightnessID:
            return NSGroupTouchBarItem(identifier: identifier, items: [
                controlButton("brightness-down", "sun.min.fill", #selector(brightnessDown)),
                controlButton("brightness-up", "sun.max.fill", #selector(brightnessUp)),
            ])
        case Self.volumeID:
            let mute = controlButton("mute", "speaker.slash.fill", #selector(toggleMute), repeats: false)
            muteButton = mute.view as? NSButton
            syncMuteButton()
            return NSGroupTouchBarItem(identifier: identifier, items: [
                mute,
                controlButton("volume-down", "speaker.wave.1.fill", #selector(volumeDown)),
                controlButton("volume-up", "speaker.wave.3.fill", #selector(volumeUp)),
            ])
        default:
            return nil
        }
    }

    /// 누르고 있으면 계속 조절되는 밝기·소리 버튼
    private func controlButton(_ name: String, _ symbol: String, _ action: Selector, repeats: Bool = true) -> NSCustomTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: NSTouchBarItem.Identifier("com.local.ClaudeTouchBar." + name))
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: name) ?? NSImage()
        let button = NSButton(image: image, target: self, action: action)
        if repeats {
            button.isContinuous = true
            button.setPeriodicDelay(0.35, interval: 0.08)
        }
        button.widthAnchor.constraint(equalToConstant: Self.controlWidth).isActive = true
        item.view = button
        return item
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
        world.showGauge(.brightness, level: level)
    }

    private func changeVolume(_ direction: Float) {
        guard let level = SystemControls.stepVolume(direction) else { return }
        world.showGauge(SystemControls.isMuted ? .muted : .volume, level: level)
        syncMuteButton()
    }

    @objc private func toggleMute() {
        let muted = SystemControls.toggleMute()
        world.showGauge(muted ? .muted : .volume, level: muted ? 0 : SystemControls.volume ?? 0)
        syncMuteButton()
    }

    /// Control Strip에 작은 Clawd 버튼을 달아서, 눌러서 놀이터를 열고 닫을 수 있게 한다.
    private func installTrayItem() {
        let item = NSCustomTouchBarItem(identifier: Self.trayID)
        item.view = NSButton(image: ClawdSprite.icon(px: 1.5), target: self, action: #selector(toggleTouchBar))
        TouchBarPrivate.addSystemTrayItem(item)
        TouchBarPrivate.setControlStripPresence(Self.trayID, true)
        trayItem = item
    }

    private func showOnTouchBar() {
        touchBar.defaultItemIdentifiers = [Self.barID] + (hasMetrics ? [Self.metricsID] : [])
            + (hasControls ? [Self.brightnessID, Self.volumeID] : [])
        playground.preferredWidth = barWidth
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
        window.title = "Clawd Touch Bar 미리보기"
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
        item.button?.toolTip = "Clawd Touch Bar"

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        countItem = menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
        countItem.isEnabled = false
        linkItem = menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
        linkItem.isEnabled = false
        menu.addItem(.separator())
        // RunCat처럼 Mac 상태를 한눈에
        statsLines = (0..<6).map { _ in
            let line = menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
            line.isEnabled = false
            return line
        }
        let sourceMenu = NSMenu()
        sourceItems = RunnerSource.allCases.map { source in
            let choice = sourceMenu.addItem(withTitle: source.title, action: #selector(chooseSource(_:)), keyEquivalent: "")
            choice.representedObject = source.rawValue
            choice.target = self
            return choice
        }
        let sourceItem = menu.addItem(withTitle: "달리기 기준", action: nil, keyEquivalent: "")
        sourceItem.submenu = sourceMenu
        menu.addItem(.separator())
        showItem = menu.addItem(withTitle: "Touch Bar에 보이기", action: #selector(toggleTouchBar), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "완료 알림 모두 확인", action: #selector(acknowledgeAll), keyEquivalent: "")
        menu.addItem(withTitle: "💡 아이디어", action: nil, keyEquivalent: "").submenu = ideasMenu
        menu.addItem(withTitle: "간식 떨어뜨리기 ✻", action: #selector(dropTreat), keyEquivalent: "")
        addItem = menu.addItem(withTitle: "Clawd 한 마리 더", action: #selector(addPet), keyEquivalent: "")
        removeItem = menu.addItem(withTitle: "Clawd 한 마리 보내기", action: #selector(removePet), keyEquivalent: "")
        menu.addItem(.separator())
        bigItem = menu.addItem(withTitle: "크게 보기", action: #selector(toggleBig), keyEquivalent: "")
        wideItem = menu.addItem(withTitle: "넓게 쓰기 (Control Strip 가리기)", action: #selector(toggleWide), keyEquivalent: "")
        controlsItem = menu.addItem(withTitle: "밝기·소리 버튼", action: #selector(toggleControls), keyEquivalent: "")
        metricsItem = menu.addItem(withTitle: "Touch Bar에 Mac 상태 보기", action: #selector(toggleMetrics), keyEquivalent: "")
        menuBarPetItem = menu.addItem(withTitle: "메뉴 막대에서 돌아다니기", action: #selector(toggleMenuBarPet), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "종료", action: #selector(quit), keyEquivalent: "q")
        for menuItem in menu.items where menuItem.action != nil { menuItem.target = self }

        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu !== ideasMenu else { return }
        rebuildIdeasMenu()
        countItem.title = "Clawd × \(world.pets.count)"
        linkItem.title = world.link?.summaryLine ?? ""
        func percent(_ value: Double) -> Int { Int((value * 100).rounded()) }
        var lines = [
            "CPU \(percent(stats.cpu))% · GPU \(percent(stats.gpu))%",
            String(format: "메모리 %.1fGB 사용 (%d%%)", stats.memoryUsedGB, percent(stats.memory)),
            String(format: "저장 공간 %.0fGB 남음 (%d%% 사용)", stats.diskFreeGB, percent(stats.disk)),
            stats.battery.map { "배터리 \(percent($0.level))%" + ($0.charging ? " (충전 중)" : "") } ?? "전원 어댑터 사용 중",
            "네트워크 ↓\(MetricsRenderer.rate(stats.download))/s ↑\(MetricsRenderer.rate(stats.upload))/s",
        ]
        if let usage = stats.claude {
            let parts = [usage.fiveHour.map { "5시간 \(percent($0.used))%" }, usage.sevenDay.map { "7일 \(percent($0.used))%" },
                         usage.context.map { "컨텍스트 \(percent($0))%" }].compactMap { $0 }
            lines.append("Claude 사용량 " + (parts.isEmpty ? (usage.model ?? "") : parts.joined(separator: " · ")))
        }
        for (i, line) in statsLines.enumerated() {
            line.title = i < lines.count ? lines[i] : ""
            line.isHidden = i >= lines.count
        }
        for choice in sourceItems {
            choice.state = choice.representedObject as? String == runnerSource.rawValue ? .on : .off
        }
        showItem.state = isShowing || previewMode ? .on : .off
        addItem.isEnabled = world.pets.count < Self.maxPets
        removeItem.isEnabled = world.pets.count > 1
        bigItem.state = big ? .on : .off
        wideItem.state = useWide ? .on : .off
        wideItem.isEnabled = !previewMode && !controlStripOnly
        wideItem.toolTip = controlStripOnly ? "Touch Bar가 확장된 Control Strip 모드라서 항상 넓게 표시돼요" : nil
        controlsItem.state = showControls ? .on : .off
        controlsItem.isEnabled = useWide && !previewMode
        metricsItem.state = showMetrics ? .on : .off
        menuBarPetItem.state = menuBarPet?.isShowing == true ? .on : .off
        menuBarPetItem.isEnabled = menuBarPet != nil
        metricsItem.isEnabled = !previewMode
    }

    /// 💡 아이디어 메뉴: 최근 아이디어(● = 아직 안 봄), 하나 던지기, 보고서 폴더
    private func rebuildIdeasMenu() {
        ideasMenu.removeAllItems()
        ideasMenu.autoenablesItems = false
        guard let box = world.ideas else { return }
        box.reload()
        if box.ideas.isEmpty {
            ideasMenu.addItem(withTitle: "아직 아이디어가 없어요 (리서치 루틴이 3시간마다 채워요)", action: nil, keyEquivalent: "").isEnabled = false
        }
        for idea in box.ideas.prefix(12) {
            let item = ideasMenu.addItem(withTitle: (box.isSeen(idea) ? "" : "● ") + idea.topic + " · " + idea.title,
                                         action: #selector(openIdea(_:)), keyEquivalent: "")
            item.representedObject = idea.id
            item.toolTip = idea.detail
            item.target = self
        }
        ideasMenu.addItem(.separator())
        let pitch = ideasMenu.addItem(withTitle: "지금 하나 던져 줘", action: #selector(pitchIdea), keyEquivalent: "")
        pitch.target = self
        pitch.isEnabled = !box.unseen.isEmpty
        ideasMenu.addItem(withTitle: "리서치 보고서 폴더 열기", action: #selector(openReports), keyEquivalent: "").target = self
    }

    @objc private func openIdea(_ sender: NSMenuItem) {
        guard let box = world.ideas, let idea = box.ideas.first(where: { $0.id == sender.representedObject as? String }) else { return }
        box.markSeen(idea)
        IdeaBox.open(idea)
    }

    @objc private func pitchIdea() {
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
        if !isShowing && !previewMode { showOnTouchBar() }
        world.dropTreat()
        menuBarPet?.world.dropTreat()
    }

    @objc private func addPet() {
        guard world.pets.count < Self.maxPets else { return }
        world.addPet()
        petCount = world.pets.count
        menuBarPet?.world.addPet()
        menuBarPet?.petCount = petCount
    }

    @objc private func removePet() {
        guard world.pets.count > 1 else { return }
        world.setPetCount(world.pets.count - 1)
        petCount = world.pets.count
        menuBarPet?.world.setPetCount(petCount)
        menuBarPet?.petCount = petCount
    }

    @objc private func toggleBig() {
        big.toggle()
        world.px = big ? 2 : 1.5
    }

    @objc private func chooseSource(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let source = RunnerSource(rawValue: raw) else { return }
        runnerSource = source
        world.busy = stats.value(for: source)
        metricsView.busy = world.busy
    }

    @objc private func toggleMenuBarPet() {
        guard let menuBarPet else { return }
        let show = !menuBarPet.isShowing
        defaults.set(show, forKey: Key.menuBarPet)
        show ? menuBarPet.show() : menuBarPet.hide()
    }

    @objc private func toggleMetrics() {
        showMetrics.toggle()
        representIfShowing()
    }

    @objc private func toggleControls() {
        showControls.toggle()
        representIfShowing()
    }

    @objc private func toggleWide() {
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
