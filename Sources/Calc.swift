import Foundation

/// 移植源：~/Dev/stations/apps-site/webapps/options.html 第 422–647 行（CORE-START…CORE-END）。
/// 逐行照搬，不做「我以为更好」的改写 —— 任何算式偏差都会被 ref/expected.json 的回归对账抓到。
enum Calc {
    static let MULT = 100.0   // 1 张 = 100 股

    struct CalcError: LocalizedError {
        let msg: String
        var errorDescription: String? { msg }
    }

    /// 标准正态 CDF —— Hart 有理逼近。锚点 ncdf(0)=0.5，ncdf(1.96)=0.9750021048517796
    static func ncdf(_ x: Double) -> Double {
        if !x.isFinite { return x > 0 ? 1 : 0 }
        let z = abs(x)
        var c = 0.0
        if z > 37 {
            c = 0
        } else {
            let e = exp(-z * z / 2)
            if z < 7.07106781186547 {
                var b = 3.52624965998911e-02 * z + 0.700383064443688
                b = b * z + 6.37396220353165;  b = b * z + 33.912866078383
                b = b * z + 112.079291497871;  b = b * z + 221.213596169931
                b = b * z + 220.206867912376
                var d = 8.83883476483184e-02 * z + 1.75566716318264
                d = d * z + 16.064177579207;   d = d * z + 86.7807322029461
                d = d * z + 296.564248779674;  d = d * z + 637.333633378831
                d = d * z + 793.826512519948;  d = d * z + 440.413735824752
                c = e * b / d
            } else {
                let q = z + 1 / (z + 2 / (z + 3 / (z + 4 / (z + 0.65))))
                c = e / (q * 2.506628274631)
            }
        }
        return x > 0 ? 1 - c : c
    }

    /// 零漂移对数正态：P(S_T ≥ X)。零漂移 = E[S_T]=S0，保守锚，不替标的假设方向。
    static func pAbove(_ spot: Double, _ X: Double, _ sig: Double, _ T: Double) -> Double {
        guard spot > 0, X > 0, sig > 0, T > 0 else { return .nan }
        let sd = sig * sqrt(T)
        return ncdf((log(spot / X) - sig * sig * T / 2) / sd)
    }

    /// 中点法数值积分，**在对数价格空间上**取网格，区间 = 均值 ±12σ。
    /// 不在价格空间等距取点的原因见源注释：σ√T 一大，等距步长会大过整个概率质量区间，
    /// 积分塌成 0.4 —— 而它看上去仍是个「算出来了」的数。
    static func integrate(_ fn: (Double) -> Double, _ spot: Double, _ sig: Double,
                          _ T: Double, _ N: Int = 12000) -> Double {
        guard spot > 0, sig > 0, T > 0 else { return .nan }
        let sd = sig * sqrt(T)
        let m = log(spot) - 0.5 * sd * sd        // ln S_T 的均值（零漂移口径）
        let lo = m - 12 * sd, du = 24 * sd / Double(N)
        var e = 0.0
        for i in 0..<N {
            let u = lo + (Double(i) + 0.5) * du
            let S = exp(u)
            let z = (u - m) / sd
            // f(S)·dS = φ(z)·dz，dz = du/sd —— 这个 1/sd 掉了积分会整体乘上 σ√T
            e += fn(S) * exp(-0.5 * z * z) / sqrt(2 * Double.pi) * du / sd
        }
        return e
    }

    static func evOf(_ payoff: (Double) -> Double, _ spot: Double, _ sig: Double, _ T: Double) -> Double {
        integrate(payoff, spot, sig, T)
    }
    static func pWin(_ payoff: @escaping (Double) -> Double, _ spot: Double, _ sig: Double, _ T: Double) -> Double {
        integrate({ payoff($0) > 0 ? 1 : 0 }, spot, sig, T)
    }

    /// 模拟 JS 的 Number→String。原版腿描述是字符串拼接 `"空 " + n + " 张 call"`,
    /// n=1.5 会印成「1.5」;用 `Int(n)` 截断会印成「1」,而同一组 legs 里
    /// `Int(100*n)` 又是 150 —— 「多 150 股」和「空 1 张 call」自相矛盾。
    static func jsNum(_ d: Double) -> String {
        if d == d.rounded() && abs(d) < 1e15 { return String(Int64(d)) }
        var t = "\(d)"
        if t.hasSuffix(".0") { t.removeLast(2) }
        return t
    }

    /// 模拟 JS 的 `Math.round(x).toLocaleString()` —— 带千分位。
    /// 原版 ic 的「两侧要求」那条腿用的就是它;Swift 侧写 `%.0f` 会印成 $2370 而非 $2,370。
    static let grouping: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")   // 注意:en_US_POSIX 不加千分位
        f.maximumFractionDigits = 0
        return f
    }()

    static func jsLocale(_ d: Double) -> String {
        grouping.string(from: NSNumber(value: d.rounded())) ?? String(Int64(d.rounded()))
    }

    // MARK: - 结构

    enum Kind: String, CaseIterable, Identifiable {
        case cc, csp, vert, ic
        var id: String { rawValue }
        var title: String {
            switch self {
            case .cc: return "备兑开仓"
            case .csp: return "现金担保 put"
            case .vert: return "信用价差"
            case .ic: return "铁鹰"
            }
        }
        var blurb: String {
            switch self {
            case .cc:  return "持有 100 股的整数倍，卖出等量看涨期权收租。上行被行权价封顶，下行几乎全额承担 —— 权利金是垫子不是保险。"
            case .csp: return "卖出看跌期权并锁定足额现金：到期没跌破就白收权利金，跌破了就按行权价接货、成本自动减去已收的权利金。"
            case .vert: return "卖近腿收租、买远腿封顶：把「不会涨过某价」或「不会跌破某价」做成风险有上限的结构。胜率高、赔率差。"
            case .ic:  return "上下各一条信用价差，赌标的到期落在区间内。关键口径：占用是两侧要求的较大者，不是两侧相加。"
            }
        }
    }

    struct Leg { let q: String; let d: String }
    struct Marker { let v: Double; let label: String }

    struct Strategy {
        var kind: Kind
        var n: Double
        var dte: Double
        var spot: Double
        var iv: Double
        var strikes: [Marker] = []
        var be: [Marker] = []
        var warn: [String] = []
        var legs: [Leg] = []
        var payoff: (Double) -> Double = { _ in .nan }
        var capital = Double.nan
        var capLabel = ""
        var credit = Double.nan
        var maxProfit = Double.nan
        var maxLoss = Double.nan
        var eff = Double.nan
        var effLabel = ""
        var intrinsic = Double.nan
        var extrinsic = Double.nan
        var interest = Double.nan
        var cashInt = Double.nan
        var roc = Double.nan
        var annRoc = Double.nan
        var annCash = Double.nan
        var annNet = Double.nan
        var annBp = Double.nan
        var annPrem = Double.nan
        var annTotal = Double.nan
    }

    struct Inputs {
        var spot = 100.0, basis = 96.0, K = 98.0, prem = 4.45
        var n = 2.0, dte = 30.0, iv = 28.0, mrate = 0.0425, rollNet = 0.0
        // csp
        var cspK = 95.0, cspPrem = 1.16, apy = 0.0335
        // vert
        var side = "call", ks = 105.0, kl = 110.0, vcredit = 0.93
        // ic
        var kpl = 85.0, kps = 90.0, kcs = 110.0, kcl = 115.0, cput = 0.26, ccall = 0.37
    }

    static func build(_ kind: Kind, _ p: Inputs, n: Double, dte: Double, spot: Double, iv: Double) throws -> Strategy {
        guard n >= 1 else { throw CalcError(msg: "张数必须 ≥ 1") }
        guard dte >= 1 else { throw CalcError(msg: "距到期天数必须 ≥ 1") }
        var o = Strategy(kind: kind, n: n, dte: dte, spot: spot, iv: iv)

        switch kind {
        case .cc:
            guard spot > 0, p.K > 0 else { throw CalcError(msg: "现价与行权价必须为正") }
            let rollPS = p.rollNet / (MULT * n)
            let eff = p.basis - p.prem - rollPS
            let intr = max(spot - p.K, 0)
            let ext = p.prem - intr
            let K = p.K, prem = p.prem
            o.eff = eff; o.effLabel = "有效成本"
            o.intrinsic = intr; o.extrinsic = ext
            o.strikes = [Marker(v: K, label: "卖出 call K")]
            o.be = [Marker(v: eff, label: "保本")]
            o.payoff = { (min($0, K) - eff) * MULT * n }
            o.maxProfit = (K - eff) * MULT * n
            o.maxLoss = -eff * MULT * n
            o.capital = (spot - prem) * MULT * n        // 净成本 = 建这笔仓要占/要借的钱
            o.capLabel = "净成本（占用资金）"
            o.credit = prem * MULT * n
            o.interest = o.capital * p.mrate * dte / 365
            let numer = ext * MULT * n - o.interest
            o.annCash = o.capital > 0 ? (ext * MULT * n) / o.capital * 365 / dte : .nan
            o.annNet  = o.capital > 0 ? numer / o.capital * 365 / dte : .nan
            let bp = (0.25 * spot - prem) * MULT * n
            let bpFloor = 0.25 * spot * MULT * n * 0.10   // 极点保护：分母趋零则发散
            o.annBp = bp > bpFloor ? numer / bp * 365 / dte : .nan
            if !(bp > bpFloor) { o.warn.append("行权价接近 0.25×现价，购买力占用趋零 → ② 号年化会发散，已隐去。") }
            if ext <= 0 { o.warn.append("外在价值 ≤ 0：这张 call 的权利金全是内在价值，这段时间没有租金可收。") }
            o.legs = [
                Leg(q: "多 \(jsNum(100 * n)) 股", d: String(format: "成本 $%.2f/股（税基）", p.basis)),
                Leg(q: "空 \(jsNum(n)) 张 call",
                    d: String(format: "K=%.2f，权利金 $%.2f/股 = 内在 $%.2f + 外在 $%.2f", K, prem, intr, ext)),
            ]

        case .csp:
            guard spot > 0, p.cspK > 0 else { throw CalcError(msg: "现价与行权价必须为正") }
            let K = p.cspK, prem = p.cspPrem
            let effP = K - prem
            o.eff = effP; o.effLabel = "有效接货成本"
            o.intrinsic = max(K - spot, 0)
            o.extrinsic = prem - o.intrinsic
            o.strikes = [Marker(v: K, label: "卖出 put K")]
            o.be = [Marker(v: effP, label: "保本 / 接货成本")]
            o.payoff = { (prem - max(K - $0, 0)) * MULT * n }
            o.maxProfit = prem * MULT * n
            o.maxLoss = -effP * MULT * n
            o.capital = effP * MULT * n                  // 担保现金 = (K − 权利金)×100×n
            o.capLabel = "锁定担保现金"
            o.credit = prem * MULT * n
            o.interest = 0
            o.cashInt = o.capital * p.apy * dte / 365
            o.annPrem  = o.capital > 0 ? (prem * MULT * n) / o.capital * 365 / dte : .nan
            o.annTotal = o.capital > 0 ? (prem * MULT * n + o.cashInt) / o.capital * 365 / dte : .nan
            if o.extrinsic <= 0 { o.warn.append("外在价值 ≤ 0：权利金全是内在价值，没有时间租金。") }
            o.legs = [
                Leg(q: "空 \(jsNum(n)) 张 put", d: String(format: "K=%.2f，权利金 $%.2f/股", K, prem)),
                Leg(q: "锁定现金",
                    d: String(format: "$%.2f/股 × 100 × ", effP) + jsNum(n) + "；保证金通常不减免这类占用"),
            ]

        case .vert:
            let ks = p.ks, kl = p.kl, credit = p.vcredit, side = p.side
            let W = abs(kl - ks)
            guard W > 0 else { throw CalcError(msg: "两条腿的行权价不能相同") }
            if side == "call" && !(kl > ks) { throw CalcError(msg: "卖看涨价差：买入腿行权价必须高于卖出腿") }
            if side == "put"  && !(kl < ks) { throw CalcError(msg: "卖看跌价差：买入腿行权价必须低于卖出腿") }
            guard credit > 0 else { throw CalcError(msg: "净权利金必须为正（信用价差才有 credit）") }
            guard credit < W else { throw CalcError(msg: "净权利金不可能 ≥ 翼宽（那是无风险套利，报价错了）") }
            let beV = side == "call" ? ks + credit : ks - credit
            o.strikes = [Marker(v: ks, label: "卖出腿"), Marker(v: kl, label: "买入腿")]
            o.be = [Marker(v: beV, label: "保本")]
            o.payoff = side == "call"
                ? { (credit - min(max($0 - ks, 0), W)) * MULT * n }
                : { (credit - min(max(ks - $0, 0), W)) * MULT * n }
            o.maxProfit = credit * MULT * n
            o.maxLoss = -(W - credit) * MULT * n
            o.capital = (W - credit) * MULT * n
            o.capLabel = "占用 / 最大风险"
            o.credit = credit * MULT * n
            o.roc = credit / (W - credit)
            o.annRoc = o.roc * 365 / dte
            o.legs = [
                Leg(q: "空 \(jsNum(n)) 张 \(side)", d: String(format: "K=%.2f（收租那条腿）", ks)),
                Leg(q: "多 \(jsNum(n)) 张 \(side)", d: String(format: "K=%.2f（保护腿，把亏损封死）", kl)),
                Leg(q: "翼宽 / 净收", d: String(format: "W=$%.2f/股，C=$%.2f/股", W, credit)),
            ]

        case .ic:
            let kpl = p.kpl, kps = p.kps, kcs = p.kcs, kcl = p.kcl
            let cput = p.cput, ccall = p.ccall
            let pw = kps - kpl, cw = kcl - kcs
            guard pw > 0 else { throw CalcError(msg: "put 侧：买入腿行权价必须低于卖出腿") }
            guard cw > 0 else { throw CalcError(msg: "call 侧：买入腿行权价必须高于卖出腿") }
            guard kcs > kps else { throw CalcError(msg: "call 卖出腿必须高于 put 卖出腿（否则两侧重叠，不是铁鹰）") }
            guard cput > 0, ccall > 0 else { throw CalcError(msg: "两侧净权利金都必须为正") }
            guard cput < pw, ccall < cw else { throw CalcError(msg: "单侧净权利金不可能 ≥ 该侧翼宽") }
            let tc = cput + ccall
            let putReq = (pw - cput) * MULT * n, callReq = (cw - ccall) * MULT * n
            o.strikes = [Marker(v: kpl, label: "买 put"), Marker(v: kps, label: "卖 put"),
                         Marker(v: kcs, label: "卖 call"), Marker(v: kcl, label: "买 call")]
            o.be = [Marker(v: kps - tc, label: "下保本"), Marker(v: kcs + tc, label: "上保本")]
            o.payoff = { (tc - min(max(kps - $0, 0), pw) - min(max($0 - kcs, 0), cw)) * MULT * n }
            o.maxProfit = tc * MULT * n
            o.maxLoss = -(max(pw, cw) - tc) * MULT * n   // 单边被穿时，另一侧的 credit 仍然收到
            o.capital = max(putReq, callReq)             // 真占用 = 较大的一侧，不是相加
            o.capLabel = "真占用（max 侧）"
            o.credit = tc * MULT * n
            o.roc = o.capital > 0 ? o.maxProfit / o.capital : .nan
            o.annRoc = o.roc * 365 / dte
            o.legs = [
                Leg(q: "空 \(jsNum(n)) 张 put",
                    d: String(format: "K=%.2f；保护腿 K=%.2f，翼宽 $%.2f，本侧净收 $%.2f", kps, kpl, pw, cput)),
                Leg(q: "空 \(jsNum(n)) 张 call",
                    d: String(format: "K=%.2f；保护腿 K=%.2f，翼宽 $%.2f，本侧净收 $%.2f", kcs, kcl, cw, ccall)),
                Leg(q: "两侧要求",
                    d: "put 侧 $" + jsLocale(putReq) + "，call 侧 $" + jsLocale(callReq)
                       + " → 真占用取较大者 $" + jsLocale(max(putReq, callReq))
                       + "（相加得 $" + jsLocale(putReq + callReq) + " 是错的）"),
            ]
        }

        if dte < 7 {
            o.warn.append("剩余 \(jsNum(dte)) 天：×365/天数 会把年化放大成名义虚高的数（gamma 完全没建模），只做参考。")
        }
        return o
    }

    struct Risk { let pProfit: Double; let ev: Double; let expMove: Double }

    static func riskStats(_ o: Strategy) -> Risk {
        let sig = o.iv / 100, T = o.dte / 365
        guard sig > 0, T > 0 else { return Risk(pProfit: .nan, ev: .nan, expMove: .nan) }
        return Risk(pProfit: pWin(o.payoff, o.spot, sig, T),
                    ev: evOf(o.payoff, o.spot, sig, T),
                    expMove: o.spot * sig * sqrt(T))
    }

    struct GridRow: Identifiable { let id: Int; let s: Double; let pl: Double; let ret: Double; let vsSpot: Double }

    /// 收益网格：到期价 → 合计盈亏 + 对占用资金的回报率
    static func payoffGrid(_ o: Strategy, rows: Int = 17) -> [GridRow] {
        let ks = o.strikes.map(\.v)
        let lo0 = ([o.spot * 0.70] + ks.map { $0 * 0.92 }).min() ?? o.spot * 0.7
        let hi = ([o.spot * 1.30] + ks.map { $0 * 1.08 }).max() ?? o.spot * 1.3
        let lo = max(lo0, 0.01)
        let step = (hi - lo) / Double(rows - 1)
        return (0..<rows).map { i in
            let S = lo + Double(i) * step
            let pl = o.payoff(S)
            return GridRow(id: i, s: S, pl: pl,
                           ret: o.capital > 0 ? pl / o.capital : .nan,
                           vsSpot: (S - o.spot) / o.spot)
        }
    }
}
