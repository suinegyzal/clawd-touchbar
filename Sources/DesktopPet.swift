import AppKit

/// 화면 위를 떠다니는 Clawd 한 마리. Touch Bar가 없는 맥을 위한 모드.
///
/// 투명한 창 하나에 작은 놀이터(Playground)를 넣고, Clawd는 늘 창 가운데에 둔다.
/// Clawd가 걸으면 그만큼 창이 화면에서 움직이고, 창 자체는 천천히 위아래로 떠다닌다.
/// 빈 곳은 클릭이 아래 창으로 통과하고, Clawd나 말풍선 위에서만 잡힌다 (Playground.transparent, 메뉴 막대 Clawd와 같은 방식).
final class PetWindow: NSObject {
    static let worldWidth: CGFloat = 480

    let world = Playground()
    let view: PlaygroundView
    let window: NSPanel

    private var driftVX: CGFloat = 0
    private var targetY: CGFloat = 0
    private var retargetIn = 0.0
    private var bob = Double.random(in: 0...6)
    private var heldMouseY: CGFloat?
    private var cursorAwayFor = 10.0
    private var lastMouseX: CGFloat?
    private var shakeDir: CGFloat = 0
    private var shakeCount = 0
    private var shakeTimer = 0.0
    private var announceFor = 0.0
    var lastGreet: CFTimeInterval = 0

    /// 메뉴의 "한 마리 더" / "보내기"
    var onAddPet: (() -> Void)?
    var onRemovePet: ((PetWindow) -> Void)?

    init(px: CGFloat, link: ClaudeLink?, slot: Int) {
        world.transparent = true
        world.px = px
        world.height = 15 * px
        world.width = Self.worldWidth
        world.link = link
        world.sessionOffset = slot
        world.addPet(at: Self.worldWidth / 2)

        view = PlaygroundView(world: world)
        view.preferredWidth = Self.worldWidth

        let size = NSSize(width: Self.worldWidth, height: world.height)
        // 비활성 패널: 클릭해도 쓰던 앱의 포커스를 뺏지 않고, 첫 클릭부터 Clawd에게 간다
        window = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        window.hidesOnDeactivate = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = false
        window.contentView = view
        view.frame = NSRect(origin: .zero, size: size)
        view.translatesAutoresizingMaskIntoConstraints = true
        view.autoresizingMask = [.width, .height]

        let area = Self.screenArea()
        window.setFrameOrigin(NSPoint(x: .random(in: area.minX...max(area.minX, area.maxX - size.width)),
                                      y: .random(in: area.minY...max(area.minY, area.maxY - size.height))))
        targetY = window.frame.minY
        super.init()
        view.onTick = { [weak self] in self?.tick() }
        view.onContextMenu = { [weak self] _, event in self?.showMenu(event) }
        window.orderFrontRegardless()
    }

    var pet: Clawd { world.pets[0] }

    // MARK: - 오른쪽 클릭 메뉴

    private func showMenu(_ event: NSEvent) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (title, action) in [("간식 주기 ✻", #selector(giveTreat)), ("쓰다듬기 ♥", #selector(patPet))] {
            menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Clawd 한 마리 더", action: #selector(addPet), keyEquivalent: "").target = self
        let bye = menu.addItem(withTitle: "이 Clawd 보내기", action: #selector(removePet), keyEquivalent: "")
        bye.target = self
        bye.isEnabled = onRemovePet != nil
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    /// 들고 좌우로 세게 흔들면(1초 안에 방향 전환 5번) 어지러워한다
    private func trackShake(_ mouseX: CGFloat, dt: Double) {
        defer { lastMouseX = mouseX }
        shakeTimer -= dt
        if shakeTimer <= 0 { shakeCount = 0; shakeDir = 0 }
        guard let last = lastMouseX else { return }
        let dx = mouseX - last
        guard abs(dx) > 5 else { return }
        let dir: CGFloat = dx > 0 ? 1 : -1
        if shakeDir != 0 && dir != shakeDir {
            shakeCount += 1
            shakeTimer = 1.0
            if shakeCount >= 5 {
                pet.dizzy(in: world)
                shakeCount = 0
            }
        }
        shakeDir = dir
    }

    /// 화면에서 Clawd가 있는 자리
    var screenCenter: NSPoint { NSPoint(x: window.frame.midX, y: window.frame.minY + world.spriteHeight / 2) }

    /// 다른 Clawd가 옆에 오면 그쪽을 보며 손을 흔든다
    func greet(toward dx: CGFloat) {
        pet.look = dx > 0 ? 1 : -1
        pet.wave()
        lastGreet = CACurrentMediaTime()
    }

    /// 간식은 Clawd 옆 조금 떨어진 곳에 떨어뜨려서 달려가 먹게 한다
    @objc private func giveTreat() {
        let side: CGFloat = Bool.random() ? 1 : -1
        world.dropTreat(at: pet.x + side * .random(in: 70...150))
    }

    @objc private func patPet() { pet.pat(in: world) }
    @objc private func addPet() { onAddPet?() }
    @objc private func removePet() { onRemovePet?(self) }

    func close() {
        view.onTick = nil
        window.orderOut(nil)
    }

    func setPixel(_ px: CGFloat) {
        world.transparent = true
        world.px = px
        world.height = 15 * px
        var frame = window.frame
        frame.size.height = world.height
        window.setFrame(frame, display: true)
    }

    private static func screenArea() -> NSRect {
        (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    /// 매 프레임: Clawd를 창 가운데로 되돌리고 그만큼 창을 옮긴 뒤, 떠다니기와 화면 끝 처리
    private func tick() {
        let dt: CGFloat = 1.0 / 60.0
        let area = (window.screen ?? NSScreen.main)?.visibleFrame ?? Self.screenArea()
        var frame = window.frame

        let dx = pet.x - Self.worldWidth / 2
        if dx != 0 {
            world.shift(by: dx)
            frame.origin.x += dx
        }

        retargetIn -= Double(dt)
        if retargetIn <= 0 {
            retargetIn = .random(in: 4...9)
            targetY = .random(in: area.minY...max(area.minY, area.maxY - frame.height))
            driftVX = .random(in: -10...10)
        }
        // 자거나 일할 때는 거의 멈춰 있고, 놀 때만 떠다닌다
        let still: Bool
        switch pet.activity {
        case .sleep, .rest, .think, .study, .craft, .exercise, .call, .held: still = true
        default: still = false
        }
        if !still {
            frame.origin.x += driftVX * dt
            frame.origin.y += (targetY - frame.origin.y) * min(1, 0.6 * dt)
        }
        // 들어 올린 채 끌면 마우스를 따라 위아래로도 옮긴다 (좌우는 Clawd의 x를 되돌리며 창이 따라간다)
        if pet.activity == .held {
            let mouseY = NSEvent.mouseLocation.y
            if let last = heldMouseY { frame.origin.y += mouseY - last }
            heldMouseY = mouseY
            trackShake(NSEvent.mouseLocation.x, dt: Double(dt))
        } else {
            heldMouseY = nil
            lastMouseX = nil
            shakeCount = 0
        }
        // 완료 알림을 한참 안 보면 커서 옆까지 찾아온다
        announceFor = pet.activity == .announce ? announceFor + Double(dt) : 0
        if announceFor > 45 {
            let mouse = NSEvent.mouseLocation
            let side: CGFloat = mouse.x > frame.midX ? -1 : 1
            let wantX = mouse.x - frame.width / 2 + side * 170
            let wantY = mouse.y - frame.height / 2
            frame.origin.x += (wantX - frame.origin.x) * min(1, 1.2 * dt)
            frame.origin.y += (wantY - frame.origin.y) * min(1, 1.2 * dt)
            pet.look = side > 0 ? -1 : 1
        }
        // 마우스가 다가오면 쳐다보고, 오랜만이면 손을 흔든다
        let mouse = NSEvent.mouseLocation
        if window.frame.insetBy(dx: -60, dy: -60).contains(mouse) {
            let local = view.convert(window.convertPoint(fromScreen: mouse), from: nil)
            if abs(local.x - pet.x) < 160 {
                if cursorAwayFor > 4 { pet.wave() }
                cursorAwayFor = 0
                pet.watch(cursorAt: local.x - pet.x)
            } else {
                cursorAwayFor += Double(dt)
            }
        } else {
            cursorAwayFor += Double(dt)
        }
        bob += Double(dt)
        frame.origin.y += CGFloat(sin(bob * 1.4)) * 0.08

        let maxX = max(area.minX, area.maxX - frame.width)
        if frame.origin.x <= area.minX { frame.origin.x = area.minX; pet.facing = 1; driftVX = abs(driftVX) }
        if frame.origin.x >= maxX { frame.origin.x = maxX; pet.facing = -1; driftVX = -abs(driftVX) }
        frame.origin.y = min(max(frame.origin.y, area.minY), max(area.minY, area.maxY - frame.height))
        if frame.origin != window.frame.origin { window.setFrameOrigin(frame.origin) }

    }
}
