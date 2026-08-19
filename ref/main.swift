import Foundation

// 用例源 = ref/cases.json，与 ref/gen.js **同一个文件**。
// 此前两侧各写一份参数，「逐字相同」全靠人盯；独立复核点名了这个隐患：
// 如果两边喂的输入本来就不同，那句「209 值全部一致」是假的。
let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let specData = try! Data(contentsOf: here.appendingPathComponent("cases.json"))
let spec = try! JSONSerialization.jsonObject(with: specData) as! [String: Any]
let cases = spec["cases"] as! [[String: Any]]

func d(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }

var out: [[String: Any]] = []
for cs in cases {
    let kindStr = cs["kind"] as! String
    let kind = Calc.Kind(rawValue: kindStr)!
    let n = d(cs["n"])!, dte = d(cs["dte"])!, spot = d(cs["spot"])!, iv = d(cs["iv"])!

    var p = Calc.Inputs()                       // 基线 = 与 options.html DEFAULTS 逐字一致
    if let v = d(cs["K"]) { if kind == .csp { p.cspK = v } else { p.K = v } }
    if let v = d(cs["prem"]) { if kind == .csp { p.cspPrem = v } else { p.prem = v } }
    if let v = d(cs["basis"]) { p.basis = v }
    if let v = d(cs["credit"]) { p.vcredit = v }
    if let v = d(cs["ks"]) { p.ks = v }
    if let v = d(cs["kl"]) { p.kl = v }

    let o = try! Calc.build(kind, p, n: n, dte: dte, spot: spot, iv: iv)
    let rs = Calc.riskStats(o)
    func j(_ x: Double) -> Any { x.isFinite ? x : NSNull() }
    out.append([
        "kind": kindStr, "n": n, "dte": dte,
        "capital": j(o.capital), "credit": j(o.credit),
        "maxProfit": j(o.maxProfit), "maxLoss": j(o.maxLoss),
        "be": o.be.map { $0.v },
        "eff": j(o.eff), "roc": j(o.roc), "annRoc": j(o.annRoc),
        "annCash": j(o.annCash), "annNet": j(o.annNet), "annBp": j(o.annBp),
        "annPrem": j(o.annPrem), "annTotal": j(o.annTotal),
        "interest": j(o.interest), "cashInt": j(o.cashInt),
        "pProfit": j(rs.pProfit), "ev": j(rs.ev), "expMove": j(rs.expMove),
        "grid": Calc.payoffGrid(o, rows: 17).map { [$0.s, $0.pl] },
        "warn": o.warn,
        "legs": o.legs.map { [$0.q, $0.d] },
        "strikes": o.strikes.map { [$0.v, $0.label] as [Any] },
        "beLabels": o.be.map { $0.label },
        "capLabel": o.capLabel.isEmpty ? NSNull() : o.capLabel,
        "effLabel": o.effLabel.isEmpty ? NSNull() : o.effLabel,
    ])
}
let data = try! JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])
FileHandle.standardOutput.write(data)
