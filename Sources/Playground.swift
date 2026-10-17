import AppKit

final class Treat {
    var x: CGFloat
    var y: CGFloat
    var vy: CGFloat = 0
    var age: Double = 0
    var eaten = false

    enum Kind {
        /// 하늘에서 떨어지는 반짝이 (Clawd). 닿으면 펄쩍 뛰며 먹는다
        case spark
        /// 땅에서 자라나는 풀떼기 (양). 고개를 숙이고 뜯어 먹는다
        case grass
        /// 흩뿌려지는 빵 부스러기 (스완). 하나씩 콕콕 쪼아 먹는다
        case crumb
        /// 물 위에 둥둥 뜨는 물고기밥 (연어). 일하던 녀석까지 미친 듯이 달려든다
        case flake
    }
    /// 물고기밥이 물 위에 떠 있다 (물결 따라 오르내리고 하류로 천천히 흘러간다)
    var afloat = false
    var kind = Kind.spark
    /// 입으로 먹는 간식 (머리가 닿는 자리까지 가서 고개를 숙인다)
    var eatenByMouth: Bool { kind != .spark }
    /// 남은 양 (풀은 0에서 자라 1이 되고, 먹으면 줄어든다)
    var grown: CGFloat = 1
    /// 누가 먹기 시작했다 (그 뒤로는 풀이 더 자라지 않는다)
    var bitten = false
    /// 지금 먹고 있는 녀석. 한 조각은 한 마리만 (둘이 머리를 맞대면 얼굴이 겹친다)
    weak var grazer: Clawd?

    /// 이 녀석이 먹으러 가도 되는지: 다른 양이 뜯는 중이 아니면 (들려 가는 등 자리를 뜨면 다시 비었다)
    func isFree(for pet: Clawd?) -> Bool {
        guard let grazer, grazer !== pet else { return true }
        return grazer.activity != .graze
    }

    init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
    }
}

struct Particle {
    enum Kind {
        case heart
        case dust
        case sweat
        case steam
        case text(String, NSColor, CGFloat)
    }

    var kind: Kind
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat = 0
    var vy: CGFloat = 0
    var life: Double
    var age: Double = 0

    var alpha: CGFloat { CGFloat(max(0, min(1, (life - age) / min(life, 0.35)))) }
}

/// Touch Bar 위의 작은 세계: Clawd들, 간식, 파티클.
final class Playground {
    var height: CGFloat = 30
    var width: CGFloat = 685 {
        didSet { if width != oldValue { clampEverything() } }
    }
    var px: CGFloat = 2 {
        didSet { clampEverything() }
    }
    let gravity: CGFloat = 700

    /// Mac이 얼마나 바쁜지 (0...1, 기준은 CPU·메모리·GPU 중 고른 것). RunCat처럼 바쁠수록 Clawd가 빨리 달린다.
    var busy = 0.0

    /// 메뉴 막대처럼 다른 화면 위에 겹쳐 그릴 때: 검은 바탕 없이, 글자엔 어두운 받침
    var transparent = false

    /// Claude Code 훅과의 연결. 없으면 그냥 자유롭게 논다.
    var link: ClaudeLink?
    /// 세계가 여럿일 때(화면 위 모드) 이 세계가 맡는 세션 순번의 시작
    var sessionOffset = 0
    private var pollIn = 0.0
    private let startedAt = Date()

    var idleSeconds: TimeInterval { link?.idleSeconds ?? Date().timeIntervalSince(startedAt) }

    /// 밝기·소리를 바꾸면 Clawd 한 마리가 레벨 바를 머리 위로 들어 보인다
    struct Gauge {
        enum Kind { case brightness, volume, muted }
        var kind: Kind
        var level: Float
        var age = 0.0
        /// 바를 든 Clawd
        var holder: ObjectIdentifier?
    }
    private(set) var gauge: Gauge?
    /// 바가 떠 있는 시간
    static let gaugeLife = 1.8

    func showGauge(_ kind: Gauge.Kind, level: Float) {
        // 계속 누르는 동안엔 같은 Clawd가 든다. 처음엔 시계 당번 → 쉬는 Clawd → 아무나
        var holder = gauge?.holder.flatMap { id in pets.first { ObjectIdentifier($0) == id } }
        holder = holder ?? pets.first { $0.showsClock } ?? pets.first { !$0.hasJob } ?? pets.first
        gauge = Gauge(kind: kind, level: level, holder: holder.map(ObjectIdentifier.init))
    }

    private(set) var pets: [Clawd] = []
    private(set) var treats: [Treat] = []
    var particles: [Particle] = []

    /// 어떤 동물로 그릴지 (행동은 모두 같다)
    var species = Species.clawd {
        didSet { for pet in pets { pet.swims = species.swims } }
    }
    var spriteWidth: CGFloat { species.width(px) }
    var spriteHeight: CGFloat { species.height(px) }
    /// 앉았을 때 머리 꼭대기
    var sittingHeight: CGFloat { species.sittingHeight(px) }
    var headroom: CGFloat { height - spriteHeight }
    var minX: CGFloat { spriteWidth / 2 + 1 }
    var maxX: CGFloat { max(minX, width - spriteWidth / 2 - 1) }

    /// 머리가 천장에 닿기 직전까지 뛰는 초속
    func jumpVelocity(_ fraction: CGFloat = 1) -> CGFloat {
        sqrt(2 * gravity * max(2, (headroom - 1) * fraction))
    }

    // MARK: - 물 (헤엄치는 캐릭터)

    /// 헤엄치는 높이의 한계 (물 표면). 아래 70%가 물이다
    var swimLevel: CGFloat { (height * 0.7).rounded() }
    /// 그려지는 물 높이. 헤엄치는 캐릭터일 때만, 투명한 화면 위·메뉴 막대는 물 없이 (헤엄은 똑같이 친다)
    var waterLevel: CGFloat? { species.swims && !transparent ? swimLevel : nil }
    /// 물결 시계와 출렁임 세기 (첨벙할 때마다 커졌다가 잦아든다)
    private(set) var clock = 0.0
    private(set) var slosh: CGFloat = 0
    /// 강물 흐름 세기 (0.25 잔잔 ~ 1 세참). 누가 일하며 물살을 거슬러 오를 때 세진다
    private(set) var current: CGFloat = 0.25
    /// 물살 줄무늬가 하류로 흘러간 거리
    private(set) var flow: CGFloat = 0

    /// 물살이 세지면 강이 상류(왼쪽)로 갈수록 높아지는 오르막이 된다 (한쪽 끝에서 가운데까지 높이 차)
    var tilt: CGFloat { species.swims ? max(0, current - 0.25) / 0.75 * height * 0.16 : 0 }

    /// 이 x에서 물 높이 (물결 없이). 오르막이면 왼쪽이 높다. 밝기·소리 키 쪽(오른쪽 밖)까지 이어진다
    func level(at x: CGFloat) -> CGFloat {
        let along = min(max(x / max(width, 1), 0), 1.4)
        return swimLevel + tilt * (1 - 2 * along)
    }

    /// 이 x에서 물 표면 높이 (오르막 + 두 물결을 겹쳐 출렁인다)
    func waterSurface(at x: CGFloat) -> CGFloat? {
        guard waterLevel != nil else { return nil }
        let amp = px * (0.7 + slosh)
        let t = CGFloat(clock)
        return level(at: x) + amp * sin(x / 16 + t * 1.7) + amp * 0.5 * sin(x / 7 - t * 2.6)
    }

    /// 물속에서 아주 살짝 둥실둥실 (깊이는 물고기가 직접 바꾼다)
    func swimLift(_ pet: Clawd, sitting: Bool) -> CGFloat {
        guard species.swims, !pet.isAirborne else { return 0 }
        return CGFloat(sin(pet.time * 1.8 + Double(pet.x) / 40)) * species.cellPx(px) * (sitting ? 0.25 : 0.5)
    }

    /// 물을 가르며 첨벙: 물방울이 튀고 물결이 크게 출렁인다
    func splash(at x: CGFloat, level: CGFloat, size: Int) {
        for _ in 0..<size {
            emit(.sweat, x: x + CGFloat.random(in: -6...6), y: level, vx: CGFloat.random(in: -35...35), vy: CGFloat.random(in: 25...60), life: 0.55)
        }
        slosh = min(2.5, slosh + CGFloat(size) * 0.2)
    }

    // MARK: - 구성

    func setPetCount(_ count: Int) {
        while pets.count < count { addPet() }
        while pets.count > count { pets.removeLast() }
    }

    func addPet(at x: CGFloat? = nil) {
        let pet = Clawd(x: x ?? CGFloat.random(in: minX...maxX))
        pet.swims = species.swims
        pet.y = height
        pet.activity = .fall
        pets.append(pet)
    }

    @discardableResult
    func dropTreat(at x: CGFloat? = nil) -> Treat {
        let tx = min(max(x ?? CGFloat.random(in: minX...maxX), 5), width - 5)
        let treat: Treat
        switch species.treat {
        case .grass:
            // 풀떼기가 땅에서 쑥쑥
            treat = Treat(x: tx, y: 0)
            treat.kind = .grass
            treat.grown = 0
            emit(.dust, x: tx - 3, y: 1, vx: -10, vy: 6, life: 0.3)
            emit(.dust, x: tx + 3, y: 1, vx: 10, vy: 6, life: 0.3)
        case .crumb:
            // 빵 부스러기 세 조각을 흩뿌린다 (조금씩 다른 높이에서 떨어진다)
            treat = Treat(x: tx, y: height - 2)
            treat.kind = .crumb
            for (dx, dy) in [(-7, 5), (6, 10)] as [(CGFloat, CGFloat)] {
                let crumb = Treat(x: min(max(tx + dx, 5), width - 5), y: height + dy)
                crumb.kind = .crumb
                treats.append(crumb)
            }
        case .flake:
            // 물고기밥 다섯 알을 흩뿌린다
            treat = Treat(x: tx, y: height)
            treat.kind = .flake
            for (dx, dy) in [(-14, 6), (-6, 3), (7, 9), (15, 4)] as [(CGFloat, CGFloat)] {
                let flake = Treat(x: min(max(tx + dx, 5), width - 5), y: height + dy)
                flake.kind = .flake
                treats.append(flake)
            }
        case .spark:
            treat = Treat(x: tx, y: height - 4)
        }
        while treats.count >= 12 { treats.removeFirst() }
        treats.append(treat)
        for pet in pets { pet.noticeTreat(in: self) }
        return treat
    }

    func pet(at x: CGFloat) -> Clawd? {
        // 말풍선을 쳐도 그 Clawd를 친 것으로 본다
        pets.reversed().first { $0.bubbleFrame.map { ($0.minX...$0.maxX).contains(x) } ?? false }
            ?? pets.reversed().first { abs($0.x - x) <= spriteWidth / 2 + 6 }
    }

    /// 리서치 루틴이 남긴 아이디어 상자. 가끔 놀고 있는 Clawd가 하나씩 던진다.
    var ideas: IdeaBox?
    private var ideaIn = 2.0

    private func checkIdeas() {
        guard let ideas else { return }
        ideas.reload()
        guard !pets.contains(where: { $0.activity == .idea }) else { return }
        let free = pets.filter { !$0.hasJob && ![.held, .fall, .chase].contains($0.activity) }
        guard !free.isEmpty, let idea = ideas.due() else { return }
        // 그 주제를 다뤘던 Clawd가 먼저, 아니면 시계 담당이 아닌 아무나
        let pitcher = free.first { pet in pet.lastTopic.map { $0.contains(idea.topic) || idea.topic.contains($0) } ?? false }
            ?? free.first { $0.clockRole != .keeper } ?? free[0]
        pitcher.pitch(idea, in: self)
    }

    func pitchIdeaNow() {
        ideas?.pitchSoon()
        ideaIn = 0
    }

    func ideaTapped(_ idea: IdeaBox.Idea) {
        ideas?.markSeen(idea)
        IdeaBox.open(idea)
    }

    func ideaPassed(_ idea: IdeaBox.Idea) {
        ideas?.shown(idea)
    }

    private var lastHour: Int?
    private var clockIn = 0.0

    /// 놀고 있는 Clawd가 둘 이상이면 한 마리는 늘 시계를 들고, 혼자면 가끔 든다. 정각엔 "땡!"
    private func assignClockKeeper() {
        let free = pets.filter { !$0.hasJob }
        for pet in pets {
            if !free.contains(where: { $0 === pet }) {
                pet.clockRole = .none
            } else if free.count >= 2 {
                pet.clockRole = pet === free.first ? .keeper : .none
            } else {
                pet.clockRole = .sometimes
            }
        }

        let hour = Calendar.current.component(.hour, from: Date())
        if let lastHour, lastHour != hour {
            (pets.first { $0.showsClock } ?? pets.first { $0.clockRole == .keeper })?.chime(in: self)
        }
        lastHour = hour
    }

    /// 완료 알림 확인
    func acknowledge(_ pet: Clawd) {
        if let id = pet.sessionID {
            link?.focusApp(of: id)   // 작업하던 창으로 데려다 준다
            link?.acknowledge(id)
        }
        pollIn = 0
    }

    /// 앱 언어를 바꿨을 때 떠 있는 이름표·말풍선을 새 언어로
    func relocalize() {
        pets.forEach { $0.relocalize() }
    }

    func acknowledgeAll() {
        link?.acknowledgeAll()
        pollIn = 0
    }

    /// 풀이 다 자라는 데 걸리는 초
    static let grassGrowth = 0.9

    /// for: 그 녀석이 먹을 수 있는 것만 (다른 양이 뜯고 있는 풀은 빼고)
    func nearestTreat(to x: CGFloat, for pet: Clawd? = nil) -> Treat? {
        treats.filter { !$0.eaten && $0.isFree(for: pet) }.min { abs($0.x - x) < abs($1.x - x) }
    }

    func eat(_ treat: Treat) {
        treat.eaten = true
        treats.removeAll { $0 === treat }
    }

    func emit(_ kind: Particle.Kind, x: CGFloat, y: CGFloat, vx: CGFloat = 0, vy: CGFloat = 0, life: Double) {
        particles.append(Particle(kind: kind, x: x, y: y, vx: vx, vy: vy, life: life))
    }

    func puffDust(at x: CGFloat) {
        for dir in [-1.0, 1.0] as [CGFloat] {
            for i in 0..<2 {
                emit(.dust, x: x + dir * (spriteWidth * 0.3 + CGFloat(i) * 2), y: 1,
                     vx: dir * CGFloat.random(in: 12...28), vy: CGFloat.random(in: 4...12), life: 0.35)
            }
        }
    }

    /// 세계 안의 모든 것을 옆으로 옮긴다 (화면 위 모드에서 Clawd를 창 가운데에 두기 위해)
    func shift(by dx: CGFloat) {
        for pet in pets { pet.x -= dx }
        for treat in treats { treat.x -= dx }
        for i in particles.indices { particles[i].x -= dx }
    }

    private func clampEverything() {
        for pet in pets { pet.x = min(max(pet.x, minX), maxX) }
        for treat in treats { treat.x = min(max(treat.x, 5), max(5, width - 5)) }
    }

    // MARK: - 시뮬레이션

    func update(_ dt: Double) {
        let t = CGFloat(dt)
        clock += dt
        slosh = max(0, slosh - t * 1.2)
        if species.swims {
            let rushing = pets.contains { $0.activity.isWorking }
            current += ((rushing ? 1 : 0.25) - current) * min(1, t * 0.8)
            flow += current * t * 70
        }
        let level = waterLevel

        for treat in treats {
            treat.age += dt
            if treat.kind == .grass {
                if !treat.bitten { treat.grown = min(1, treat.grown + CGFloat(dt / Self.grassGrowth)) }
                continue
            }
            if treat.kind == .flake {
                // 물고기밥: 떨어지다 수면에 닿으면 둥둥 뜬다
                let surface = waterSurface(at: treat.x) ?? self.level(at: treat.x)
                if treat.afloat {
                    treat.y = surface
                    treat.x = min(treat.x + current * 5 * t, width - 4)   // 물살 따라 하류로
                } else {
                    treat.vy -= gravity * 0.4 * t
                    treat.y += treat.vy * t
                    if treat.y <= surface {
                        treat.y = surface
                        treat.vy = 0
                        treat.afloat = true
                        if level != nil { splash(at: treat.x, level: surface, size: 1) }
                    }
                }
                continue
            }
            guard treat.y > 0 || treat.vy != 0 else { continue }
            let here = level.map { _ in self.level(at: treat.x) }
            let wasAbove = here.map { treat.y > $0 } ?? true
            if let level = here, treat.y < level {
                // 물속에선 천천히 가라앉는다
                treat.vy = max(-35, treat.vy - gravity * 0.08 * t)
            } else {
                treat.vy -= gravity * 0.55 * t
            }
            treat.y += treat.vy * t
            if let level = here, wasAbove, treat.y <= level {
                splash(at: treat.x, level: level, size: 3)
                treat.vy *= 0.25
            }
            if treat.y <= 0 {
                treat.y = 0
                treat.vy = abs(treat.vy) > 40 ? -treat.vy * 0.4 : 0
            }
        }

        pollIn -= dt
        if pollIn <= 0, let link {
            pollIn = 0.25
            link.poll()
            let sessions = link.active
            for (i, pet) in pets.enumerated() {
                pet.assign(i + sessionOffset < sessions.count ? sessions[i + sessionOffset] : nil, in: self)
            }
        }
        ideaIn -= dt
        if ideaIn <= 0 {
            ideaIn = 5
            checkIdeas()
        }
        clockIn -= dt
        if clockIn <= 0 {
            clockIn = 0.25
            assignClockKeeper()
        }

        for pet in pets { pet.update(dt, in: self) }

        if level != nil {
            for pet in pets {
                // 몸 가운데가 물 표면을 지나면 첨벙
                let level = self.level(at: pet.x)
                let above = pet.y + swimLift(pet, sitting: false) + spriteHeight / 2 > level
                if above != pet.aboveWater {
                    pet.aboveWater = above
                    splash(at: pet.x, level: level, size: above ? 5 : 7)
                }
                // 물속에서 가끔 보글보글
                if !above, Double.random(in: 0...1) < dt / 3 {
                    let mouth = pet.x + pet.facing * spriteWidth * 0.42
                    emit(.text("°", NSColor(srgbRed: 0.66, green: 0.85, blue: 0.9, alpha: 1), 9), x: mouth,
                         y: pet.y + swimLift(pet, sitting: false) + spriteHeight * 0.4, vx: 0, vy: 9, life: 1.4)
                }
            }
        }

        gauge?.age += dt
        if let g = gauge, g.age > Self.gaugeLife { gauge = nil }

        for i in particles.indices {
            particles[i].age += dt
            particles[i].x += particles[i].vx * t
            particles[i].y += particles[i].vy * t
            switch particles[i].kind {
            case .dust, .sweat: particles[i].vy -= 60 * t
            case .steam: particles[i].vx *= 0.96
            default: break
            }
        }
        particles.removeAll { $0.age >= $0.life }
    }
}
