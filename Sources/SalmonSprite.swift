import AppKit

/// 25×12칸 한달연어. 디놈들 도감(No.05 한 달 살기형)의 그림을 그대로 옮기고, Clawd의 자세를 물고기에 맞게 붙였다.
/// 다리 대신 꼬리를 흔들고, 팔 대신 가슴지느러미를 든다. 원본은 왼쪽을 본다.
enum SalmonSprite {
    static let cols = 25
    static let rows = 12

    private static let eye = CGColor(srgbRed: 0.1, green: 0.1, blue: 0.1, alpha: 1)
    private static let fin = CGColor(srgbRed: 0.86, green: 0.42, blue: 0.3, alpha: 1)

    /// 몸. 짜증이 날수록 더 붉어진다 (도감 색 #F4845F → 새빨강)
    static func flesh(heat: CGFloat) -> CGColor {
        let t = min(max(heat, 0), 1)
        return CGColor(srgbRed: (244 + (222 - 244) * t) / 255, green: (132 + (58 - 132) * t) / 255, blue: (95 + (48 - 95) * t) / 255, alpha: 1)
    }
    /// 배 (#FBC2A8)
    static func belly(heat: CGFloat) -> CGColor {
        let t = min(max(heat, 0), 1)
        return CGColor(srgbRed: (251 + (245 - 251) * t) / 255, green: (194 + (140 - 194) * t) / 255, blue: (168 + (130 - 168) * t) / 255, alpha: 1)
    }

    // 원본 그림 (왼쪽 위가 0,0): (행, 시작 열, 끝 열)
    private static let bodyRows = [(3, 2, 19), (4, 1, 19), (5, 0, 19), (6, 0, 19), (7, 0, 19), (8, 1, 19), (9, 2, 19)]
    private static let bellyRows = [(8, 3, 18), (9, 3, 18)]
    private static let dorsalRows = [(0, 11, 13), (1, 10, 14), (2, 10, 14)]
    private static let pelvic = [(8, 10), (9, 10), (10, 10)]
    /// 꼬리자루와 위아래 꼬리 갈래. lift: 꼬리 끝을 위(-)·아래(+)로 흔든 정도
    private static func tail(lift: Int, tucked: Bool) -> [(Int, Int)] {
        let spread = tucked ? 1 : 0   // 접으면 두 갈래가 가운데로 모인다
        var cells: [(Int, Int)] = []
        for r in 4...8 { cells += [(20, r), (21, r)] }
        for r in 2...5 { cells += [(22, r + lift + spread), (23, r + lift + spread)] }
        for r in 1...3 { cells.append((24, r + lift + spread)) }
        for r in 7...10 { cells += [(22, r + lift - spread), (23, r + lift - spread)] }
        for r in 9...11 { cells.append((24, r + lift - spread)) }
        return cells
    }
    private static let eyeX = 4
    private static let eyeY = 5

    private static func span(_ rows: [(Int, Int, Int)]) -> [(Int, Int)] {
        rows.flatMap { r, a, b in (a...b).map { ($0, r) } }
    }

    /// outline은 쓰지 않는다 (연어 색은 밝은 바탕에서도 잘 보인다)
    static func draw(_ frame: ClawdSprite.Frame, in ctx: CGContext, centerX: CGFloat, bottom: CGFloat, px: CGFloat,
                     scale: CGFloat = 2, heat: CGFloat = 0) {
        let left = ClawdSprite.snap(centerX - CGFloat(cols) * px / 2, scale)
        let base = ClawdSprite.snap(bottom, scale)
        let flip = frame.facing > 0
        func cell(_ c: Int, _ r: Int) -> CGRect {
            let x = flip ? cols - 1 - c : c
            return CGRect(x: left + CGFloat(x) * px, y: base + CGFloat(rows - 1 - r) * px, width: px, height: px)
        }
        var layers: [(CGColor, [(Int, Int)])] = []
        let body = flesh(heat: heat)

        var dumbbellUp: Bool?
        if case .dumbbell(let up) = frame.prop { dumbbellUp = up }

        // 꼬리: 헤엄칠 때 위아래로 번갈아 친다
        let lift: Int
        switch frame.legs {
        case .stand: lift = 0
        case .stepA: lift = -1
        case .stepB: lift = 1
        case .tucked: lift = 0
        }
        var cells = span(bodyRows) + span(dorsalRows) + tail(lift: lift, tucked: frame.legs == .tucked)
        if !frame.sitting { cells += pelvic }   // 바닥에 누우면 배지느러미는 접힌다
        // 입: 먹을 땐(headDown) 덥석 벌린다
        let gulping = frame.headDown > 0
        if gulping {
            let gap = [(0, 6), (1, 6), (0, 7)]
            cells.removeAll { cell in gap.contains { $0 == cell } }
        }
        layers.append((body, cells))
        layers.append((belly(heat: heat), span(bellyRows)))
        layers.append((fin, gulping ? [(2, 6), (1, 7)] : [(0, 7), (1, 7)]))

        // 가슴지느러미: 평소엔 뒤로 눕히고, 팔을 드는 자세(환호·부르기·팻말·바벨)엔 위로 번쩍
        let pectoral = frame.armsUp ? [(7, 5), (8, 4), (8, 5), (9, 3), (9, 4)] : [(6, 7), (7, 7), (8, 8), (9, 8)]
        layers.append((fin, pectoral))

        // 눈 하나 (옆모습). 표정은 Clawd와 같은 모양으로
        let shift = frame.look * (flip ? -1 : 1)
        let x = min(5, max(3, eyeX + shift))
        layers.append((eye, eyeOffsets(frame.eyes).map { (x + $0.0, eyeY + $0.1) }))
        if frame.shades > 0 {
            let lens = (x - 1...x + 1).flatMap { c in [(c, eyeY), (c, eyeY + 1)] } + [(x + 2, eyeY), (x + 3, eyeY)]
            layers.append((CGColor(gray: 0.06, alpha: 0.3 + 0.7 * min(1, frame.shades)), lens))
            if frame.shades > 0.75 { layers.append((CGColor(gray: 1, alpha: 0.9), [(x - 1, eyeY)])) }
        }

        // 소품: 지느러미로 들고 있는 것처럼 머리 앞에
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
            break   // 팻말은 렌더러가 머리 위에 그린다
        case .book(let page):
            paint(ClawdSprite.bookArt(page), col: -8, row: 7)
        case .laptop(let typing):
            paint(ClawdSprite.laptopArt, col: -10, row: 8)
            layers.append((fin, [(typing % 2 == 0 ? -1 : -6, 7)]))   // 지느러미로 타닥타닥
        case .dumbbell:
            // 등 위로 바벨을 들어 올린다
            paint(["gg" + String(repeating: ".", count: 14) + "gg",
                   "ggbbbbbbbbbbbbbbgg",
                   "gg" + String(repeating: ".", count: 14) + "gg"], col: 3, row: dumbbellUp == true ? -4 : -2)
        }

        for (color, cells) in layers {
            ctx.setFillColor(color)
            ctx.fill(cells.map { cell($0.0, $0.1) })
        }
    }

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
