const c = require('./core.js');
const SPEC = require('./cases.json');

// cc/csp/vert/ic 各自的完整参数集（与 options.html 的 DEFAULTS 逐字一致）。
// 每条用例只覆盖它显式给出的键，其余取这里的基线。
const BASE = {
  cc:   {basis:96, K:98, prem:4.45, mrate:0.0425, rollNet:0},
  csp:  {K:95, prem:1.16, apy:0.0335},
  vert: {side:"call", ks:105, kl:110, credit:0.93},
  ic:   {kpl:85, kps:90, kcs:110, kcl:115, cput:0.26, ccall:0.37},
};

const out = [];
for (const cs of SPEC.cases) {
  const p = Object.assign({}, BASE[cs.kind], {n:cs.n, dte:cs.dte, spot:cs.spot, iv:cs.iv});
  for (const k of Object.keys(cs)) {
    if (!['kind','n','dte','spot','iv'].includes(k) && !k.startsWith('_')) p[k] = cs[k];
  }
  const o = c.buildStrategy(cs.kind, p);
  const rs = c.riskStats(o);
  out.push({
    kind: cs.kind, n: cs.n, dte: cs.dte,
    capital: o.capital, credit: o.credit, maxProfit: o.maxProfit, maxLoss: o.maxLoss,
    be: o.be.map(b => b.s),
    eff: o.eff ?? null, roc: o.roc ?? null, annRoc: o.annRoc ?? null,
    annCash: o.annCash ?? null, annNet: o.annNet ?? null, annBp: o.annBp ?? null,
    annPrem: o.annPrem ?? null, annTotal: o.annTotal ?? null,
    interest: o.interest ?? null, cashInt: o.cashInt ?? null,
    pProfit: rs.pProfit, ev: rs.ev, expMove: rs.expMove,
    grid: c.payoffGrid(o, 17).map(g => [g.s, g.pl]),
    // ↓ 文案层。此前没纳入对账,于是 Calc.swift 少五个字、Int() 截断张数,209 值照样全绿。
    warn: o.warn,
    legs: o.legs.map(l => [l.q, l.d]),
    strikes: o.strikes.map(s => [s.k, s.label]),
    beLabels: o.be.map(b => b.label),
    capLabel: o.capLabel ?? null, effLabel: o.effLabel ?? null,
  });
}
console.log(JSON.stringify(out, null, 1));
