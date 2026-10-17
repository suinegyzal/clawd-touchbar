import AppKit

/// 어떤 동물로 보일지. 행동·기분·소품은 모두 같고 그림만 다르다 (Clawd와 같은 Frame을 받아 그린다).
enum Species: String, CaseIterable {
    case clawd, sheep, mindeswan, salmon

    var title: String {
        switch self {
        case .clawd: return "Clawd"
        case .sheep: return tr("유목양", "Nomad sheep")
        case .mindeswan: return "mindeswan"
        case .salmon: return tr("한달연어", "Month-stay salmon")
        }
    }

    private static let key = "species"
    /// 메뉴에서 고른 캐릭터. CLAWD_SPECIES=sheep 으로 실행하면 그걸 쓴다 (문서·확인용 그림)
    static var current: Species {
        get {
            if let forced = ProcessInfo.processInfo.environment["CLAWD_SPECIES"].flatMap(Species.init(rawValue:)) { return forced }
            return Species(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .clawd
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    var cols: Int {
        switch self {
        case .clawd: return ClawdSprite.cols
        case .sheep: return SheepSprite.cols
        case .mindeswan: return SwanSprite.cols
        case .salmon: return SalmonSprite.cols
        }
    }
    var rows: Int {
        switch self {
        case .clawd: return ClawdSprite.rows
        case .sheep: return SheepSprite.rows
        case .mindeswan: return SwanSprite.rows
        case .salmon: return SalmonSprite.rows
        }
    }

    /// 그림 한 칸의 크기. px는 Clawd 기준 크기이고, 양은 몸집이 커서 칸을 줄인다 (레티나에서 또렷하게 0.5pt 단위로).
    /// Touch Bar 기본 1.5 → 1pt, 크게 2 → 1.5pt, 화면 위 3 → 2pt, 4 → 3pt
    func cellPx(_ px: CGFloat) -> CGFloat {
        switch self {
        case .clawd: return px
        case .sheep, .mindeswan, .salmon: return max(0.5, (px * 0.75 * 2).rounded(.down) / 2)
        }
    }

    func width(_ px: CGFloat) -> CGFloat { CGFloat(cols) * cellPx(px) }
    func height(_ px: CGFloat) -> CGFloat { CGFloat(rows) * cellPx(px) }
    /// 앉았을 때 머리 꼭대기 높이
    func sittingHeight(_ px: CGFloat) -> CGFloat {
        switch self {
        case .clawd: return px * 8
        case .sheep: return cellPx(px) * CGFloat(SheepSprite.rows - SheepSprite.sitDrop)
        case .mindeswan: return cellPx(px) * CGFloat(SwanSprite.rows - SwanSprite.sitDrop)
        case .salmon: return height(px)   // 바닥에 눕기만 한다
        }
    }
    /// 머리 위 팻말(시계·레벨 바)의 가운데. 양은 등에 지므로 머리를 피해 몸통 뒤쪽으로 옮긴다
    func signOffset(facing: CGFloat, px: CGFloat) -> CGFloat {
        switch self {
        case .clawd: return 0
        case .sheep: return (facing > 0 ? -8 : 8) * cellPx(px)
        case .mindeswan: return (facing > 0 ? -6 : 6) * cellPx(px)
        case .salmon: return 0
        }
    }
    /// 팻말을 머리 꼭대기보다 얼마나 낮게 놓을지. 양은 등 털에 반쯤 얹는다 (Touch Bar 높이 안에 들어오게)
    func signSink(px: CGFloat) -> CGFloat {
        switch self {
        case .clawd: return 0
        case .sheep: return 4 * cellPx(px)
        case .mindeswan: return CGFloat(SwanSprite.signDuck) * cellPx(px)   // 고개를 숙이고 날개로 받친다
        case .salmon: return 2 * cellPx(px)   // 배 밑에 살짝 겹쳐 매단다
        }
    }

    /// 물속에 산다: Touch Bar 아래쪽이 출렁이는 물이 되고, 둥실둥실 떠서 헤엄친다
    var swims: Bool { self == .salmon }

    /// 무엇을 먹는지: Clawd는 반짝이, 양은 땅에서 자라는 풀, 스완은 빵 부스러기
    var treat: Treat.Kind {
        switch self {
        case .clawd: return .spark
        case .sheep: return .grass
        case .mindeswan: return .crumb
        case .salmon: return .flake
        }
    }
    /// 입으로 먹을 때 입이 몸 가운데에서 머리 쪽으로 얼마나 떨어져 있는지
    func mouthOffset(px: CGFloat) -> CGFloat {
        switch self {
        case .clawd: return 0
        case .sheep: return 10 * cellPx(px)
        case .mindeswan: return CGFloat(SwanSprite.mouthOffset) * cellPx(px)
        case .salmon: return 11 * cellPx(px)
        }
    }

    /// 메뉴의 간식 주기
    var treatTitle: String {
        switch treat {
        case .spark: return tr("간식 떨어뜨리기 ✻", "Drop a treat ✻")
        case .grass: return tr("풀 자라게 하기 🌱", "Grow some grass 🌱")
        case .crumb: return tr("빵 부스러기 뿌리기 🍞", "Toss bread crumbs 🍞")
        case .flake: return tr("물고기밥 뿌리기 🐟", "Sprinkle fish food 🐟")
        }
    }
    /// 화면 위 모드의 오른쪽 클릭 메뉴
    var giveTreatTitle: String {
        switch treat {
        case .spark: return tr("간식 주기 ✻", "Give a treat ✻")
        case .grass: return tr("풀 키워 주기 🌱", "Grow grass 🌱")
        case .crumb: return tr("빵 부스러기 주기 🍞", "Give bread crumbs 🍞")
        case .flake: return tr("물고기밥 주기 🐟", "Feed fish food 🐟")
        }
    }

    /// 팻말(시계·소리·밝기)을 몸 아래로 든다: 물고기는 물속에서 배 밑에 매달고 다닌다 (수면 위로 잘리지 않게)
    var signBelow: Bool { self == .salmon }
    /// 팻말 높이 (렌더러와 같은 7칸)
    static func signHeight(px: CGFloat) -> CGFloat { 7 * max(1, (px * 0.75 * 2).rounded() / 2) }
    /// 팻말 아래쪽 높이. 보통은 머리 위(signSink만큼 걸친다), signBelow면 배 밑(signSink만큼 겹친다)
    func signBottom(petBottom: CGFloat, petTop: CGFloat, px: CGFloat) -> CGFloat {
        signBelow ? petBottom + signSink(px: px) - Self.signHeight(px: px) : petTop - signSink(px: px)
    }

    /// 머리가 있는 쪽 (1 오른쪽, -1 왼쪽). Clawd는 몸 전체가 머리라 오른쪽에 붙인다
    func headSide(facing: CGFloat) -> CGFloat { self == .clawd ? 1 : facing }

    /// outline: 밝은 바탕에 그릴 때 (흰 동물이 묻히지 않게)
    func draw(_ frame: ClawdSprite.Frame, in ctx: CGContext, centerX: CGFloat, bottom: CGFloat, px: CGFloat,
              scale: CGFloat = 2, heat: CGFloat = 0, outline: Bool = false) {
        switch self {
        case .clawd:
            ClawdSprite.draw(frame, in: ctx, centerX: centerX, bottom: bottom, px: px, scale: scale, color: Palette.clawd(heat: heat))
        case .sheep:
            SheepSprite.draw(frame, in: ctx, centerX: centerX, bottom: bottom, px: cellPx(px), scale: scale, heat: heat, outline: outline)
        case .mindeswan:
            SwanSprite.draw(frame, in: ctx, centerX: centerX, bottom: bottom, px: cellPx(px), scale: scale, heat: heat, outline: outline)
        case .salmon:
            SalmonSprite.draw(frame, in: ctx, centerX: centerX, bottom: bottom, px: cellPx(px), scale: scale, heat: heat)
        }
    }

    /// 버튼·메뉴용 아이콘. outline이면 밝은 바탕용 테두리 (테두리 한 칸만큼 크다)
    func icon(px: CGFloat, outline: Bool = false) -> NSImage {
        let pad = outline ? cellPx(px) : 0
        let size = NSSize(width: width(px) + pad * 2, height: height(px) + pad * 2)
        return NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            self.draw(ClawdSprite.Frame(facing: 1), in: ctx, centerX: size.width / 2, bottom: pad, px: px, outline: outline)
            return true
        }
    }
}

/// 30×17칸 유목양. 디놈들 도감(No.10)의 그림을 그대로 옮기고, Clawd가 하는 자세·표정·소품을 양에 맞게 붙였다.
/// 원본은 왼쪽을 본다. 오른쪽을 볼 땐 좌우로 뒤집는다.
enum SheepSprite {
    static let cols = 30
    static let rows = 17
    /// 앉으면 몸이 내려가는 칸 수
    static let sitDrop = 3

    private static let wool = CGColor(gray: 1, alpha: 1)
    private static let belly = CGColor(srgbRed: 0xE9 / 255, green: 0xDF / 255, blue: 0xCF / 255, alpha: 1)
    private static let eyeWhite = CGColor(gray: 1, alpha: 1)

    /// 얼굴·귀·다리. 짜증이 날수록 붉어진다
    static func skin(heat: CGFloat) -> CGColor {
        let t = min(max(heat, 0), 1)
        return CGColor(srgbRed: (138 + (214 - 138) * t) / 255, green: (129 + (84 - 129) * t) / 255,
                       blue: (120 + (70 - 120) * t) / 255, alpha: 1)
    }

    // 원본 도감 그림 (왼쪽 위가 0,0)
    private static let puffs = [(9, 1), (13, 0), (17, 1), (21, 0), (25, 1), (8, 4), (8, 8), (27, 4), (27, 8), (11, 12), (16, 12), (21, 12)]
    private static let legX = [11, 15, 20, 24]
    private static let eyeX = [4, 7]
    private static let eyeY = 4

    /// outline: 밝은 바탕(메뉴 막대·화면 위)에서 흰 털이 묻히지 않게 털 둘레에 진한 테두리를 두른다
    static func draw(_ frame: ClawdSprite.Frame, in ctx: CGContext, centerX: CGFloat, bottom: CGFloat, px: CGFloat,
                     scale: CGFloat = 2, heat: CGFloat = 0, outline: Bool = false) {
        let left = ClawdSprite.snap(centerX - CGFloat(cols) * px / 2, scale)
        let base = ClawdSprite.snap(bottom, scale)
        let flip = frame.facing > 0
        func cell(_ c: Int, _ r: Int) -> CGRect {
            let x = flip ? cols - 1 - c : c
            return CGRect(x: left + CGFloat(x) * px, y: base + CGFloat(rows - 1 - r) * px, width: px, height: px)
        }
        func block(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> [(Int, Int)] {
            (0..<h).flatMap { j in (0..<w).map { i in (x + i, y + j) } }
        }
        // 색별로 칸을 모았다가 순서대로 칠한다 (뒤에 칠한 것이 위)
        var layers: [(CGColor, [(Int, Int)])] = []

        var dumbbellUp: Bool?
        if case .dumbbell(let up) = frame.prop { dumbbellUp = up }
        let holdsSign: Bool = { if case .holdSign = frame.prop { return true }; return false }()
        // 앉기 3칸, 아령 스쿼트 2칸 내려간다
        let drop = frame.sitting ? sitDrop : dumbbellUp == false ? 2 : 0
        // 팔을 드는 자세(환호·부르기·떨어지기)는 앞다리를 들고 고개를 든다
        let rearing = frame.armsUp && !frame.sitting && !holdsSign && dumbbellUp == nil
        let head = drop - (rearing ? 1 : 0) + frame.headDown
        let skinColor = skin(heat: heat)

        // 다리
        if !frame.sitting {
            var legs: [(Int, Int)] = []
            for (i, x) in legX.enumerated() {
                var top = 14, height = 3
                switch frame.legs {
                case .stand: break
                case .stepA: if i % 2 == 1 { height = 2 }
                case .stepB: if i % 2 == 0 { height = 2 }
                case .tucked: height = 1
                }
                if rearing && i < 2 { top = 13; height = 2 }   // 앞다리를 든다
                legs += block(x, top, 2, height)
            }
            layers.append((skinColor, legs))
        }

        // 몸통 털과 배
        var body = block(9, 2 + drop, 18, 10)
        for (x, y) in puffs { body += block(x, y + drop, 3, 2) }
        let forelock = block(3, 0 + head, 6, 2)
        layers.append((wool, body))
        layers.append((belly, block(10, 9 + drop, 17, 2)))

        // 얼굴과 귀, 앞머리
        layers.append((skinColor, block(2, 2 + head, 8, 7) + block(0, 3 + head, 2, 2) + block(10, 3 + head, 2, 2)))
        layers.append((wool, forelock))

        // 눈: Clawd와 같은 표정을 흰 눈으로. 오른눈은 좌우로 뒤집어 > < 가 되게
        let shift = frame.look * (flip ? -1 : 1)
        let eyes = eyeX.map { min(8, max(3, $0 + shift)) }
        let row = eyeY + head
        var eyeCells: [(Int, Int)] = []
        for (dx, dy) in eyeOffsets(frame.eyes) {
            eyeCells.append((eyes[0] + dx, row + dy))
            eyeCells.append((eyes[1] - dx, row + dy))
        }
        layers.append((eyeWhite, eyeCells))
        if frame.shades > 0 {
            layers.append((CGColor(gray: 0.06, alpha: 0.3 + 0.7 * min(1, frame.shades)), block(eyes[0] - 1, row, 3, 2) + block(eyes[1] - 1, row, 3, 2)))
            if frame.shades > 0.75 { layers.append((CGColor(gray: 1, alpha: 0.9), [(eyes[0] - 1, row), (eyes[1] - 1, row)])) }
        }

        // 소품
        func paint(_ art: [String], col: Int, row: Int) {
            for (r, line) in art.enumerated() {
                for (c, ch) in line.enumerated() {
                    guard let color = Palette.props[ch] else { continue }
                    layers.append((color, [(col + c, row + r)]))
                }
            }
        }
        switch frame.prop {
        case .none, .holdSign:
            break   // 팻말은 렌더러가 등 위에 그린다
        case .book(let page):
            paint(ClawdSprite.bookArt(page), col: 0, row: 12)
        case .laptop(let typing):
            paint(ClawdSprite.laptopArt, col: 0, row: 12)
            layers.append((skinColor, [(typing % 2 == 0 ? 1 : 10, 11)]))   // 앞발로 번갈아 타닥타닥
        case .dumbbell:
            // 등에 바벨을 지고 스쿼트
            paint(["gg" + String(repeating: ".", count: 14) + "gg",
                   "ggbbbbbbbbbbbbbbgg",
                   "gg" + String(repeating: ".", count: 14) + "gg"], col: 9, row: -3 + drop)
        }

        if outline {
            // 털(몸·앞머리) 둘레의 빈칸에 테두리
            struct Key: Hashable { let x: Int; let y: Int }
            let filled = Set(layers.flatMap(\.1).map { Key(x: $0.0, y: $0.1) })
            var ring = Set<Key>()
            for (x, y) in body + forelock {
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let k = Key(x: x + dx, y: y + dy)
                    if !filled.contains(k) { ring.insert(k) }
                }
            }
            ctx.setFillColor(CGColor(gray: 0.32, alpha: 1))
            ctx.fill(ring.map { cell($0.x, $0.y) })
        }
        for (color, cells) in layers {
            ctx.setFillColor(color)
            ctx.fill(cells.map { cell($0.0, $0.1) })
        }
    }

    /// 왼쪽 눈 기준 (dx, dy). 오른쪽 눈은 dx를 뒤집는다
    private static func eyeOffsets(_ eyes: ClawdSprite.Eyes) -> [(Int, Int)] {
        switch eyes {
        case .open: return [(0, 0), (0, 1)]
        case .blink: return [(0, 1)]
        case .up: return [(0, -1), (0, 0)]
        case .happy: return [(0, 0), (-1, 1), (1, 1)]
        case .closed: return [(-1, 1), (0, 1)]
        case .tired: return [(0, 1)]
        case .frustrated: return [(-1, -1), (0, 0), (-1, 1)]
        }
    }
}
