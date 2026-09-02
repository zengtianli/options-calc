import SwiftUI

struct ContentView: View {
    /// --kind=<cc|csp|vert|ic> 让截图/回归能确定性落到某一档，不靠模拟点击。
    @State private var kind: Calc.Kind = {
        for a in CommandLine.arguments where a.hasPrefix("--kind=") {
            if let k = Calc.Kind(rawValue: String(a.dropFirst(7))) { return k }
        }
        return .cc
    }()
    @State private var p = Calc.Inputs()
    /// 张数按结构分开存 —— 源 DEFAULTS 里 cc/csp 是 2、vert/ic 是 5，
    /// 共用一个 n 会让 vert/ic 的所有金额缩到 2/5（而保本点、盈利概率与 n 无关，照样对，
    /// 只看那几个数会误判成「全对」）。
    @State private var nByKind: [Calc.Kind: Double] = [.cc: 2, .csp: 2, .vert: 5, .ic: 5]
    @State private var dte = 30.0
    @State private var spot = 100.0
    @State private var iv = 28.0
    /// 手机上算完要反复看结果，折起输入省得一直滑。--results-only 让截图/回归能确定性拍到结果区。
    @State private var showInputs = !CommandLine.arguments.contains("--results-only")

    private var result: Result<Calc.Strategy, Error> {
        Result { try Calc.build(kind, p, n: nByKind[kind] ?? 1, dte: dte, spot: spot, iv: iv) }
    }

    /// 宽屏（iPad 横竖屏 / Mac）= regular：输入与结果并排两栏，一眼看全；
    /// 手机 = compact：一栏上下，靠「只看结果」折起输入（2026-09-02 三平台起）。
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        NavigationStack {
            Group {
                if hSize == .regular {
                    HStack(spacing: 0) {
                        // .grouped：Mac 默认的 columns 式 Form 会把说明文字压成一字一行、分段控件撑出栏外（2026-09-02 窗口截图实证）
                        Form { kindSection; inputSections }
                            .formStyle(.grouped)
                            .frame(minWidth: 340, idealWidth: 400, maxWidth: 460)
                        Divider()
                        Form { resultSections }
                            .formStyle(.grouped)
                    }
                } else {
                    Form {
                        kindSection
                        if showInputs { inputSections }
                        resultSections
                    }
                }
            }
            .navigationTitle("期权决策台")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if hSize != .regular {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(showInputs ? "只看结果" : "改参数") {
                            withAnimation { showInputs.toggle() }
                        }.font(.subheadline)
                    }
                }
            }
        }
        .preferredColorScheme(.light)
    }

    @ViewBuilder private var kindSection: some View {
                Section {
                    Picker("结构", selection: $kind) {
                        ForEach(Calc.Kind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text(kind.blurb)
                        .font(.footnote).foregroundStyle(.secondary)
                }
    }

    @ViewBuilder private var inputSections: some View {
                Section("通用") {
                    Num("现价 S", $spot)
                    Num("张数 n", Binding(get: { nByKind[kind] ?? 1 },
                                          set: { nByKind[kind] = $0 }), fmt: "%.0f")
                    Num("距到期天数", $dte, fmt: "%.0f"); Num("IV %", $iv)
                }

                switch kind {
                case .cc:
                    Section("备兑开仓") {
                        Num("持仓成本（税基）", $p.basis); Num("卖出 call K", $p.K)
                        Num("权利金 /股", $p.prem); Num("融资利率", $p.mrate, fmt: "%.4f")
                        Num("已滚动净收 $", $p.rollNet, fmt: "%.0f")
                    }
                case .csp:
                    Section("现金担保 put") {
                        Num("卖出 put K", $p.cspK); Num("权利金 /股", $p.cspPrem)
                        Num("现金年化 APY", $p.apy, fmt: "%.4f")
                    }
                case .vert:
                    Section("信用价差") {
                        Picker("方向", selection: $p.side) {
                            Text("call").tag("call"); Text("put").tag("put")
                        }.pickerStyle(.segmented)
                        Num("卖出腿 K", $p.ks); Num("买入腿 K", $p.kl)
                        Num("净权利金 /股", $p.vcredit)
                    }
                case .ic:
                    Section("铁鹰") {
                        Num("买 put K", $p.kpl); Num("卖 put K", $p.kps)
                        Num("卖 call K", $p.kcs); Num("买 call K", $p.kcl)
                        Num("put 侧净收 /股", $p.cput); Num("call 侧净收 /股", $p.ccall)
                    }
                }
    }

    @ViewBuilder private var resultSections: some View {
                switch result {
                case .failure(let e):
                    Section {
                        Label(e.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                case .success(let o):
                    ResultSections(o: o)
                }
    }

    @ViewBuilder
    private func Num(_ label: String, _ v: Binding<Double>, fmt: String = "%.2f") -> some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer(minLength: 12)
            TextField(label, value: v, format: .number)
                .labelsHidden()          // Mac 的 TextField 会把 title 再画一遍成前置标签（窗口截图实证），iOS 上 title 只是占位符不受影响
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 130)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct ResultSections: View {
    let o: Calc.Strategy
    var risk: Calc.Risk { Calc.riskStats(o) }

    var body: some View {
        Section("关键数") {
            KV(o.capLabel, usd(o.capital))
            KV("收到权利金", usd(o.credit))
            KV("最大盈利", usd(o.maxProfit), tint: .green)
            KV("最大亏损", usd(o.maxLoss), tint: .red)
            if o.eff.isFinite { KV(o.effLabel, px(o.eff)) }
            ForEach(Array(o.be.enumerated()), id: \.offset) { _, b in KV(b.label, px(b.v)) }
            if o.annRoc.isFinite { KV("年化（对占用）", pct(o.annRoc)) }
            if o.annCash.isFinite { KV("年化 · 全款口径", pct(o.annCash)) }
            if o.annNet.isFinite { KV("年化 · 扣息后", pct(o.annNet)) }
            if o.annBp.isFinite { KV("年化 · 对购买力", pct(o.annBp)) }
            if o.annPrem.isFinite { KV("年化 · 仅权利金", pct(o.annPrem)) }
            if o.annTotal.isFinite { KV("年化 · 含现金息", pct(o.annTotal)) }
        }

        Section("概率与期望（零漂移对数正态，不替标的假设方向）") {
            KV("盈利概率", pct(risk.pProfit))
            KV("期望值 EV", usd(risk.ev), tint: risk.ev >= 0 ? .green : .red)
            KV("预期波动 ±1σ", px(risk.expMove))
        }

        Section("腿") {
            ForEach(Array(o.legs.enumerated()), id: \.offset) { _, l in
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.q).font(.subheadline.weight(.medium))
                    Text(l.d).font(.caption).foregroundStyle(.secondary)
                }
            }
        }

        if !o.warn.isEmpty {
            Section("提醒") {
                ForEach(Array(o.warn.enumerated()), id: \.offset) { _, w in
                    Label(w, systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }

        Section("收益网格（到期价 → 合计盈亏）") {
            ForEach(Calc.payoffGrid(o)) { r in
                HStack {
                    Text(px(r.s)).font(.system(.caption, design: .monospaced))
                    Text(pctSigned(r.vsSpot)).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text(usd(r.pl)).font(.system(.caption, design: .monospaced))
                        .foregroundStyle(r.pl > 0 ? .green : (r.pl < 0 ? .red : .primary))
                }
            }
        }
    }

    @ViewBuilder private func KV(_ k: String, _ v: String, tint: Color = .primary) -> some View {
        HStack { Text(k).font(.subheadline); Spacer()
            Text(v).font(.system(.subheadline, design: .monospaced)).foregroundStyle(tint) }
    }
}

func usd(_ v: Double) -> String {
    guard v.isFinite else { return "—" }
    let a = abs(v)
    let s = a >= 1000 ? String(format: "%.0f", a) : String(format: "%.2f", a)
    return (v < 0 ? "−$" : "$") + s
}
func pct(_ v: Double, _ d: Int = 1) -> String { v.isFinite ? String(format: "%.\(d)f%%", v * 100) : "—" }
func pctSigned(_ v: Double) -> String { v.isFinite ? String(format: "%+.0f%%", v * 100) : "—" }
func px(_ v: Double) -> String { v.isFinite ? String(format: "$%.2f", v) : "—" }
