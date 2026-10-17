import AppKit

/// 24×19칸 mindeswan. 디지털 노마드 워크 라운지 마인데스크의 하얀 백조.
/// 작은 머리, 가늘고 긴 S자 목, 뒤가 치켜올라간 배 모양 몸통, 부리 뿌리의 검은 혹.
/// 공부할 땐 마인데스크 로고처럼 다리 셋 달린 책상에 탁상 램프를 켜고 하늘색 책을 읽는다.
/// 원본은 왼쪽을 본다. 오른쪽을 볼 땐 좌우로 뒤집는다.
enum SwanSprite {
    static let cols = 24
    static let rows = 19
    /// 앉으면 몸이 내려가는 칸 수 (다리 길이)
    static let sitDrop = 2
    /// 팻말이 머리 꼭대기보다 낮게 내려오는 칸 수: 등 위로 세운 날개에 얹힌다 (Touch Bar 높이 안에 들어오게)
    static let signDuck = 6
    /// 몸 가운데에서 부리 끝까지 (빵 부스러기를 쪼을 자리)
    static let mouthOffset = 11

    /// 마인데스크 남색 (테두리·눈)
    static let ink = CGColor(srgbRed: 0, green: 51 / 255, blue: 87 / 255, alpha: 1)
    /// 마인데스크 하늘색 (책 표지·램프 갓)
    static let sky = CGColor(srgbRed: 199 / 255, green: 235 / 255, blue: 254 / 255, alpha: 1)
    private static let shade = CGColor(srgbRed: 0.78, green: 0.85, blue: 0.92, alpha: 1)
    private static let beak = CGColor(srgbRed: 0.98, green: 0.58, blue: 0.22, alpha: 1)
    private static let knob = CGColor(srgbRed: 0.1, green: 0.1, blue: 0.12, alpha: 1)
    /// 백조 발은 거무스름하다 (Touch Bar 검은 바탕에서도 보이게 회청색)
    private static let feet = CGColor(srgbRed: 0.38, green: 0.44, blue: 0.52, alpha: 1)
    private static let woodTop = CGColor(srgbRed: 0.84, green: 0.66, blue: 0.46, alpha: 1)
    private static let wood = CGColor(srgbRed: 0.63, green: 0.45, blue: 0.3, alpha: 1)
    private static let lampMetal = CGColor(srgbRed: 0.74, green: 0.78, blue: 0.84, alpha: 1)
    private static let bulb = CGColor(srgbRed: 1, green: 0.93, blue: 0.62, alpha: 1)
    private static let spine = CGColor(srgbRed: 0.55, green: 0.76, blue: 0.9, alpha: 1)
    private static let glow = (r: 1.0, g: 0.86, b: 0.55)

    /// 깃털. 짜증이 날수록 분홍빛으로 달아오른다
    static func feather(heat: CGFloat) -> CGColor {
        let t = min(max(heat, 0), 1)
        return CGColor(srgbRed: 1, green: 1 - 0.4 * t, blue: 1 - 0.45 * t, alpha: 1)
    }

    // 원본 그림 (왼쪽 위가 0,0). H 머리, b 부리, k 혹
    private static let headArt = [
        ".....HHHH",
        "....HHHHHH",
        ".bbkHHHHHH",
        "bbbbHHHHH",
        "......HH",
    ]
    /// 가늘고 긴 S자 목: 머리 뒤에서 내려와 등 쪽으로 휘었다가 가슴으로 (행, 시작 열, 끝 열)
    private static let neckRows = [(4, 8, 9), (5, 8, 9), (6, 9, 10), (7, 9, 10), (8, 10, 11), (9, 10, 11), (10, 10, 11), (11, 9, 10), (12, 8, 9)]
    /// 배 모양 몸통: 가슴은 낮고 꼬리 쪽이 치켜 올라간다
    private static let bodyRows = [(9, 21, 22), (10, 17, 23), (11, 13, 23), (12, 10, 22), (13, 7, 22), (14, 7, 21), (15, 8, 20), (16, 10, 18)]
    /// 접은 날개의 물결 깃
    private static let wingLines = [(12, 13), (15, 13), (18, 13), (21, 13), (13, 14), (14, 14), (16, 14), (17, 14), (19, 14), (20, 14)]
    /// 날개를 등 위로 둥글게 세운다 (백조가 뽐낼 때처럼)
    private static let raisedRows = [(5, 14, 22), (6, 13, 23), (7, 13, 23), (8, 14, 23), (9, 15, 22)]
    private static let raisedTips = [(15, 4), (16, 4), (18, 4), (19, 4), (21, 4)]
    private static let raisedLines = [(15, 7), (18, 7), (21, 7), (16, 8), (17, 8), (19, 8), (20, 8)]
    private static let legX = [13, 17]
    private static let eyeX = [5, 8]
    private static let eyeY = 1
    /// 팻말을 들 때 숙인 머리 높이
    private static let bowedHead = 6

    private static func span(_ rows: [(Int, Int, Int)], dy: Int = 0) -> [(Int, Int)] {
        rows.flatMap { r, a, b in (a...b).map { ($0, r + dy) } }
    }

    private static func cells(_ art: [String], _ mark: Character, dy: Int) -> [(Int, Int)] {
        art.enumerated().flatMap { r, line in line.enumerated().compactMap { c, ch in ch == mark ? (c, r + dy) : nil } }
    }

    /// outline: 밝은 바탕(메뉴 막대·화면 위)에서 흰 깃털이 묻히지 않게 마인데스크 남색 테두리를 두른다
    static func draw(_ frame: ClawdSprite.Frame, in ctx: CGContext, centerX: CGFloat, bottom: CGFloat, px: CGFloat,
                     scale: CGFloat = 2, heat: CGFloat = 0, outline: Bool = false) {
        let left = ClawdSprite.snap(centerX - CGFloat(cols) * px / 2, scale)
        let base = ClawdSprite.snap(bottom, scale)
        let flip = frame.facing > 0
        func cell(_ c: Int, _ r: Int) -> CGRect {
            let x = flip ? cols - 1 - c : c
            return CGRect(x: left + CGFloat(x) * px, y: base + CGFloat(rows - 1 - r) * px, width: px, height: px)
        }
        var layers: [(CGColor, [(Int, Int)])] = []

        var dumbbellUp: Bool?
        if case .dumbbell(let up) = frame.prop { dumbbellUp = up }
        let holdsSign: Bool = { if case .holdSign = frame.prop { return true }; return false }()
        // 앉기 2칸, 바벨 스쿼트 1칸 내려간다
        let drop = frame.sitting ? sitDrop : dumbbellUp == false ? 1 : 0
        // 팻말은 세운 날개로 받치고 고개는 숙여 팻말 밑으로. 빵을 쪼을 땐 부리가 땅까지 (headDown 6 = 땅, 5 = 반쯤)
        let lowered = frame.headDown > 0 ? frame.headDown * 2 + 1 : holdsSign ? bowedHead : 0
        let head = drop + lowered
        let featherColor = feather(heat: heat)

        // 다리와 물갈퀴
        var legCells: [(Int, Int)] = []
        if !frame.sitting {
            for (i, x) in legX.enumerated() {
                let lifted: Bool
                switch frame.legs {
                case .stand: lifted = false
                case .stepA: lifted = i == 0
                case .stepB: lifted = i == 1
                case .tucked: lifted = true
                }
                legCells += lifted ? [(x - 1, 17), (x, 17)] : [(x, 17), (x - 1, 18), (x, 18)]
            }
            layers.append((feet, legCells))
        }

        // 몸통과 날개
        let body = span(bodyRows, dy: drop)
        layers.append((featherColor, body))
        layers.append((shade, wingLines.map { ($0.0, $0.1 + drop) }))
        var wings: [(Int, Int)] = []
        if frame.armsUp && !frame.sitting && dumbbellUp != false {
            wings = span(raisedRows, dy: drop) + raisedTips.map { ($0.0, $0.1 + drop) }
            layers.append((featherColor, wings))
            layers.append((shade, raisedLines.map { ($0.0, $0.1 + drop) }))
        }

        // 바벨은 목 뒤로 (목·머리가 앞을 가린다): 들면 날개 위, 내리면 등 위
        if let up = dumbbellUp {
            paint(["gg" + String(repeating: ".", count: 14) + "gg",
                   "ggbbbbbbbbbbbbbbgg",
                   "gg" + String(repeating: ".", count: 14) + "gg"], col: 5, row: (up ? 1 : 8) + drop, into: &layers)
        }

        // 목과 머리. 고개를 숙이면 머리 위로 남는 목은 감춘다
        let neckTop = lowered > 0 ? min(head, 11 + drop) : 0
        let neck = span(neckRows, dy: drop).filter { $0.1 >= neckTop }
        let headCells = cells(headArt, "H", dy: head)
        let beakCells = cells(headArt, "b", dy: head)
        layers.append((featherColor, neck + headCells))
        layers.append((beak, beakCells))
        layers.append((knob, cells(headArt, "k", dy: head)))

        // 눈: Clawd와 같은 표정을 남색 눈으로. 오른눈은 좌우로 뒤집어 > < 가 되게
        let shift = frame.look * (flip ? -1 : 1)
        let eyes = [min(6, max(4, eyeX[0] + shift)), min(8, max(7, eyeX[1] + shift))]
        let row = eyeY + head
        var eyeCells: [(Int, Int)] = []
        for (dx, dy) in eyeOffsets(frame.eyes) {
            eyeCells.append((eyes[0] + dx, row + dy))
            eyeCells.append((eyes[1] - dx, row + dy))
        }
        layers.append((ink, eyeCells))
        if frame.shades > 0 {
            let lenses = [eyes[0], eyes[1]].flatMap { e in (e - 1...e + 1).flatMap { c in [(c, row), (c, row + 1)] } }
            layers.append((CGColor(gray: 0.06, alpha: 0.3 + 0.7 * min(1, frame.shades)), lenses))
            if frame.shades > 0.75 { layers.append((CGColor(gray: 1, alpha: 0.9), [(eyes[0] - 1, row), (eyes[1] - 1, row)])) }
        }

        // 소품
        var light: [(Int, Int, CGFloat)] = []
        switch frame.prop {
        case .none, .holdSign, .dumbbell:
            break   // 팻말은 렌더러가 등 위에 그린다
        case .book(let page):
            light = studyDesk(page: page, drop: drop, feather: featherColor, into: &layers)
        case .laptop(let typing):
            paint(ClawdSprite.laptopArt, col: 0, row: 15, into: &layers)
            layers.append((featherColor, [(typing % 2 == 0 ? 3 : 9, 14)]))   // 날개 끝으로 타닥타닥
        }

        // 램프 불빛은 맨 뒤에 은은하게
        for (c, r, alpha) in light {
            ctx.setFillColor(CGColor(srgbRed: glow.r, green: glow.g, blue: glow.b, alpha: alpha))
            ctx.fill(cell(c, r))
        }
        if outline {
            // 동물(깃털·부리·발) 둘레의 빈칸에 테두리
            struct Key: Hashable { let x: Int; let y: Int }
            let animal = body + neck + headCells + beakCells + wings + legCells
            let filled = Set(layers.flatMap(\.1).map { Key(x: $0.0, y: $0.1) })
            var ring = Set<Key>()
            for (x, y) in animal {
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let k = Key(x: x + dx, y: y + dy)
                    if !filled.contains(k) { ring.insert(k) }
                }
            }
            ctx.setFillColor(ink)
            ctx.fill(ring.map { cell($0.x, $0.y) })
        }
        for (color, cells) in layers {
            ctx.setFillColor(color)
            ctx.fill(cells.map { cell($0.0, $0.1) })
        }
    }

    /// 마인데스크 로고처럼 다리 셋 달린 책상과 탁상 램프. 책상은 스완 앞(부리 쪽)에 놓인다.
    /// 램프 불빛이 책상과 그 앞 어두운 곳을 은은하게 밝힌다. 돌려주는 값은 불빛 칸과 밝기
    private static func studyDesk(page: Int, drop: Int, feather: CGColor, into layers: inout [(CGColor, [(Int, Int)])]) -> [(Int, Int, CGFloat)] {
        let top = 10 + drop   // 책상 윗면
        // 책상: 윗면, 둥근 서랍 앞판, 다리 셋
        layers.append((woodTop, (-10...5).map { ($0, top) }))
        layers.append((wood, (-9...4).map { ($0, top + 1) } + (-6...1).map { ($0, top + 2) }))
        let legs = [-9, -3, 4].flatMap { x in ((x == -3 ? top + 3 : top + 2)...(rows - 1)).map { (x, $0) } }
        layers.append((wood, legs))

        // 책상에 세워 펼친 하늘색 책 (스완 쪽에서 읽으니 뒤표지가 보인다). 넘길 때마다 종이 한 장이 펄럭
        layers.append((sky, (-3...2).flatMap { c in (top - 4...top - 1).map { (c, $0) } }))
        layers.append((spine, (top - 4...top - 1).map { (0, $0) }))
        layers.append((Palette.props["p"]!, [(-2, top - 5), (-1, top - 5), (1, top - 5), (2, top - 5)] + (page % 2 == 0 ? [] : [(1, top - 6)])))
        // 날개 끝으로 책을 받친다
        layers.append((feather, page % 2 == 0 ? [(3, top - 3), (4, top - 3)] : [(3, top - 4), (4, top - 4), (4, top - 3)]))

        // 탁상 램프: 받침, 기둥, 둥근 갓과 뾰족한 꼭지, 갓 아래 전구
        let lampX = -8
        layers.append((lampMetal, [(lampX - 1, top - 1), (lampX, top - 1), (lampX + 1, top - 1)] + (top - 4...top - 2).map { (lampX, $0) }))
        layers.append((sky, [(lampX, top - 8)] + (lampX - 1...lampX + 1).map { ($0, top - 7) } + (lampX - 2...lampX + 2).map { ($0, top - 6) }))
        layers.append((bulb, [(lampX - 1, top - 5), (lampX, top - 5), (lampX + 1, top - 5)]))

        // 불빛: 갓 아래로 퍼지는 원뿔, 그 둘레는 아주 옅게
        let center = (x: CGFloat(lampX), y: CGFloat(top - 4))
        var light: [(Int, Int, CGFloat)] = []
        for r in (top - 6)...(rows - 1) {
            for c in (lampX - 9)...(lampX + 13) {
                let dx = CGFloat(c) - center.x, dy = CGFloat(r) - center.y
                let distance = (dx * dx + dy * dy).squareRoot()
                let below = dy >= 0 && abs(dx) <= dy * 1.1 + 2   // 갓 아래 원뿔
                let alpha: CGFloat = below && distance < 9 ? 0.26 : distance < 7 ? 0.14 : distance < 11 ? 0.07 : 0
                if alpha > 0 { light.append((c, r, alpha)) }
            }
        }
        return light
    }

    private static func paint(_ art: [String], col: Int, row: Int, into layers: inout [(CGColor, [(Int, Int)])]) {
        for (r, line) in art.enumerated() {
            for (c, ch) in line.enumerated() {
                guard let color = Palette.props[ch] else { continue }
                layers.append((color, [(col + c, row + r)]))
            }
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
