/* ==== CORE-START ==== 纯计算层（无 DOM，可被 Node 直接加载做回归） ==== */
var MULT = 100;   // 1 张 = 100 股

/* 标准正态 CDF —— Hart 有理逼近，双精度量级。
   锚点：ncdf(0)=0.5，ncdf(1.96)=0.9750021048517796（与真实系统的回归锚一致）。 */
function ncdf(x){
  if(!isFinite(x)) return x > 0 ? 1 : 0;
  var z = Math.abs(x), c;
  if(z > 37){ c = 0; }
  else {
    var e = Math.exp(-z*z/2), b, d;
    if(z < 7.07106781186547){
      b = 3.52624965998911e-02*z + 0.700383064443688;
      b = b*z + 6.37396220353165;  b = b*z + 33.912866078383;
      b = b*z + 112.079291497871;  b = b*z + 221.213596169931;
      b = b*z + 220.206867912376;
      d = 8.83883476483184e-02*z + 1.75566716318264;
      d = d*z + 16.064177579207;   d = d*z + 86.7807322029461;
      d = d*z + 296.564248779674;  d = d*z + 637.333633378831;
      d = d*z + 793.826512519948;  d = d*z + 440.413735824752;
      c = e*b/d;
    } else {
      var q = z + 1/(z + 2/(z + 3/(z + 4/(z + 0.65))));
      c = e/(q*2.506628274631);
    }
  }
  return x > 0 ? 1 - c : c;
}

/* 零漂移对数正态：P(S_T ≥ X)。零漂移 = E[S_T]=S0，保守锚，不替标的假设方向。 */
function pAbove(spot, X, sig, T){
  if(!(spot > 0 && X > 0 && sig > 0 && T > 0)) return NaN;
  var sd = sig*Math.sqrt(T);
  return ncdf((Math.log(spot/X) - sig*sig*T/2)/sd);
}
/* 同一分布的密度 f(S)：ln S_T ~ N(ln S0 − σ²T/2, σ²T) */
function lnDens(S, spot, sig, T){
  var sd = sig*Math.sqrt(T);
  var z = (Math.log(S/spot) + 0.5*sig*sig*T)/sd;
  return Math.exp(-0.5*z*z)/Math.sqrt(2*Math.PI)/(S*sd);
}
/* 中点法数值积分，**在对数价格空间上**取网格：u = ln S，积分区间 = 均值 ±12σ。
   为什么不在价格空间等距取点：σ√T 一大（比如 IV 120% 的年线），价格空间的上界会跑到
   几千倍现价，等距网格的步长就大过整个概率质量所在的区间，积分结果直接塌成 0.4 ——
   而它看上去仍然是个「算出来了」的数。对数空间下 σ 多大都是同样密的采样。 */
function integrate(fn, spot, sig, T, N){
  if(!(spot > 0 && sig > 0 && T > 0)) return NaN;
  N = N || 12000;
  var sd = sig*Math.sqrt(T);
  var m = Math.log(spot) - 0.5*sd*sd;      // ln S_T 的均值（零漂移口径）
  var lo = m - 12*sd, du = 24*sd/N, e = 0;
  for(var i = 0; i < N; i++){
    var u = lo + (i + 0.5)*du, S = Math.exp(u);
    var z = (u - m)/sd;
    // f(S)·dS = φ(z)·dz，而 dz = du/sd —— 这个 1/sd 掉了的话积分会整体乘上 σ√T
    e += fn(S)*Math.exp(-0.5*z*z)/Math.sqrt(2*Math.PI)*du/sd;
  }
  return e;
}
function evOf(payoff, spot, sig, T){ return integrate(payoff, spot, sig, T); }
function pWin(payoff, spot, sig, T){
  return integrate(function(S){ return payoff(S) > 0 ? 1 : 0; }, spot, sig, T);
}

/* ---- 结构构建：kind ∈ cc | csp | vert | ic ----
   返回统一形状：payoff(S) 给「合计 $」，strikes/be 给图，capital = 这笔占用的钱。 */
function buildStrategy(kind, p){
  var n = p.n, o = {kind: kind, n: n, strikes: [], be: [], warn: []};
  if(!(n >= 1)) throw new Error("张数必须 ≥ 1");
  if(!(p.dte >= 1)) throw new Error("距到期天数必须 ≥ 1");

  if(kind === "cc"){
    if(!(p.spot > 0 && p.K > 0)) throw new Error("现价与行权价必须为正");
    var rollPS = (p.rollNet || 0)/(MULT*n);
    var eff = p.basis - p.prem - rollPS;
    var intr = Math.max(p.spot - p.K, 0);
    var ext = p.prem - intr;
    o.eff = eff; o.effLabel = "有效成本";
    o.intrinsic = intr; o.extrinsic = ext;
    o.strikes = [{k: p.K, label: "卖出 call K"}];
    o.be = [{s: eff, label: "保本"}];
    o.payoff = function(S){ return (Math.min(S, p.K) - eff)*MULT*n; };
    o.maxProfit = (p.K - eff)*MULT*n;
    o.maxLoss = -eff*MULT*n;
    o.capital = (p.spot - p.prem)*MULT*n;          // 净成本 = 现在建这笔仓要占/要借的钱
    o.capLabel = "净成本（占用资金）";
    o.credit = p.prem*MULT*n;
    o.interest = o.capital*p.mrate*p.dte/365;
    o.numer = ext*MULT*n - o.interest;
    o.annCash = o.capital > 0 ? (ext*MULT*n)/o.capital*365/p.dte : NaN;   // 全款口径（不扣息）
    o.annNet  = o.capital > 0 ? o.numer/o.capital*365/p.dte : NaN;        // ① 每借一块钱赚多少
    var bp = (0.25*p.spot - p.prem)*MULT*n;
    var bpFloor = 0.25*p.spot*MULT*n*0.10;                                 // 极点保护：分母趋零则发散
    o.bp = bp;
    o.annBp = bp > bpFloor ? o.numer/bp*365/p.dte : NaN;                   // ② 每吃一块额度赚多少
    if(!(bp > bpFloor)) o.warn.push("行权价接近 0.25×现价，购买力占用趋零 → ② 号年化会发散，已隐去。");
    if(ext <= 0) o.warn.push("外在价值 ≤ 0：这张 call 的权利金全是内在价值，这段时间没有租金可收。");
    o.legs = [
      {q: "多 " + (100*n) + " 股", d: "成本 $" + p.basis.toFixed(2) + "/股（税基）"},
      {q: "空 " + n + " 张 call", d: "K=" + p.K.toFixed(2) + "，权利金 $" + p.prem.toFixed(2) +
          "/股 = 内在 $" + intr.toFixed(2) + " + 外在 $" + ext.toFixed(2)}
    ];

  } else if(kind === "csp"){
    if(!(p.spot > 0 && p.K > 0)) throw new Error("现价与行权价必须为正");
    var effP = p.K - p.prem;
    o.eff = effP; o.effLabel = "有效接货成本";
    o.intrinsic = Math.max(p.K - p.spot, 0);
    o.extrinsic = p.prem - o.intrinsic;
    o.strikes = [{k: p.K, label: "卖出 put K"}];
    o.be = [{s: effP, label: "保本 / 接货成本"}];
    o.payoff = function(S){ return (p.prem - Math.max(p.K - S, 0))*MULT*n; };
    o.maxProfit = p.prem*MULT*n;
    o.maxLoss = -effP*MULT*n;
    o.capital = effP*MULT*n;                        // 担保现金 = (K − 权利金)×100×n
    o.capLabel = "锁定担保现金";
    o.credit = p.prem*MULT*n;
    o.interest = 0;
    o.cashInt = o.capital*p.apy*p.dte/365;
    o.annPrem = o.capital > 0 ? (p.prem*MULT*n)/o.capital*365/p.dte : NaN;
    o.annTotal = o.capital > 0 ? (p.prem*MULT*n + o.cashInt)/o.capital*365/p.dte : NaN;
    o.numer = p.prem*MULT*n;
    if(o.extrinsic <= 0) o.warn.push("外在价值 ≤ 0：权利金全是内在价值，没有时间租金。");
    o.legs = [
      {q: "空 " + n + " 张 put", d: "K=" + p.K.toFixed(2) + "，权利金 $" + p.prem.toFixed(2) + "/股"},
      {q: "锁定现金", d: "$" + effP.toFixed(2) + "/股 × 100 × " + n + "；保证金通常不减免这类占用"}
    ];

  } else if(kind === "vert"){
    var W = Math.abs(p.kl - p.ks);
    if(!(W > 0)) throw new Error("两条腿的行权价不能相同");
    if(p.side === "call" && !(p.kl > p.ks)) throw new Error("卖看涨价差：买入腿行权价必须高于卖出腿");
    if(p.side === "put" && !(p.kl < p.ks)) throw new Error("卖看跌价差：买入腿行权价必须低于卖出腿");
    if(!(p.credit > 0)) throw new Error("净权利金必须为正（信用价差才有 credit）");
    if(p.credit >= W) throw new Error("净权利金不可能 ≥ 翼宽（那是无风险套利，报价错了）");
    var beV = p.side === "call" ? p.ks + p.credit : p.ks - p.credit;
    o.width = W;
    o.strikes = [{k: p.ks, label: "卖出腿"}, {k: p.kl, label: "买入腿"}];
    o.be = [{s: beV, label: "保本"}];
    o.payoff = p.side === "call"
      ? function(S){ return (p.credit - Math.min(Math.max(S - p.ks, 0), W))*MULT*n; }
      : function(S){ return (p.credit - Math.min(Math.max(p.ks - S, 0), W))*MULT*n; };
    o.maxProfit = p.credit*MULT*n;
    o.maxLoss = -(W - p.credit)*MULT*n;
    o.capital = (W - p.credit)*MULT*n;
    o.capLabel = "占用 / 最大风险";
    o.credit = p.credit*MULT*n;
    o.roc = p.credit/(W - p.credit);
    o.annRoc = o.roc*365/p.dte;
    o.legs = [
      {q: "空 " + n + " 张 " + (p.side === "call" ? "call" : "put"), d: "K=" + p.ks.toFixed(2) + "（收租那条腿）"},
      {q: "多 " + n + " 张 " + (p.side === "call" ? "call" : "put"), d: "K=" + p.kl.toFixed(2) + "（保护腿，把亏损封死）"},
      {q: "翼宽 / 净收", d: "W=$" + W.toFixed(2) + "/股，C=$" + p.credit.toFixed(2) + "/股"}
    ];

  } else if(kind === "ic"){
    var pw = p.kps - p.kpl, cw = p.kcl - p.kcs;
    if(!(pw > 0)) throw new Error("put 侧：买入腿行权价必须低于卖出腿");
    if(!(cw > 0)) throw new Error("call 侧：买入腿行权价必须高于卖出腿");
    if(!(p.kcs > p.kps)) throw new Error("call 卖出腿必须高于 put 卖出腿（否则两侧重叠，不是铁鹰）");
    if(!(p.cput > 0 && p.ccall > 0)) throw new Error("两侧净权利金都必须为正");
    if(p.cput >= pw || p.ccall >= cw) throw new Error("单侧净权利金不可能 ≥ 该侧翼宽");
    var tc = p.cput + p.ccall;
    var putReq = (pw - p.cput)*MULT*n, callReq = (cw - p.ccall)*MULT*n;
    o.putWidth = pw; o.callWidth = cw; o.totalCredit = tc;
    o.putReq = putReq; o.callReq = callReq;
    o.sumBoth = putReq + callReq;
    o.capital = Math.max(putReq, callReq);       // 真占用 = 较大的一侧，不是相加
    o.capLabel = "真占用（max 侧）";
    o.strikes = [{k: p.kpl, label: "买 put"}, {k: p.kps, label: "卖 put"},
                 {k: p.kcs, label: "卖 call"}, {k: p.kcl, label: "买 call"}];
    o.be = [{s: p.kps - tc, label: "下保本"}, {s: p.kcs + tc, label: "上保本"}];
    o.payoff = function(S){
      return (tc - Math.min(Math.max(p.kps - S, 0), pw) - Math.min(Math.max(S - p.kcs, 0), cw))*MULT*n;
    };
    o.maxProfit = tc*MULT*n;
    o.maxLoss = -(Math.max(pw, cw) - tc)*MULT*n;   // 单边被穿时，另一侧的 credit 仍然收到
    o.credit = tc*MULT*n;
    o.roc = o.capital > 0 ? o.maxProfit/o.capital : NaN;
    o.annRoc = o.roc*365/p.dte;
    o.legs = [
      {q: "空 " + n + " 张 put", d: "K=" + p.kps.toFixed(2) + "；保护腿 K=" + p.kpl.toFixed(2) +
          "，翼宽 $" + pw.toFixed(2) + "，本侧净收 $" + p.cput.toFixed(2)},
      {q: "空 " + n + " 张 call", d: "K=" + p.kcs.toFixed(2) + "；保护腿 K=" + p.kcl.toFixed(2) +
          "，翼宽 $" + cw.toFixed(2) + "，本侧净收 $" + p.ccall.toFixed(2)},
      {q: "两侧要求", d: "put 侧 $" + Math.round(putReq).toLocaleString() +
          "，call 侧 $" + Math.round(callReq).toLocaleString() +
          " → 真占用取较大者 $" + Math.round(o.capital).toLocaleString() +
          "（相加得 $" + Math.round(o.sumBoth).toLocaleString() + " 是错的）"}
    ];
  } else {
    throw new Error("未知结构：" + kind);
  }

  if(p.dte < 7) o.warn.push("剩余 " + p.dte + " 天：×365/天数 会把年化放大成名义虚高的数（gamma 完全没建模），只做参考。");
  o.dte = p.dte; o.spot = p.spot; o.iv = p.iv;
  return o;
}

/* 概率与期望：统一走结构自己的 payoff，不为每种结构另写一份解析式（避免口径漂移）。 */
function riskStats(o){
  var sig = o.iv/100, T = o.dte/365;
  if(!(sig > 0 && T > 0)) return {pProfit: NaN, ev: NaN, expMove: NaN};
  return {
    pProfit: pWin(o.payoff, o.spot, sig, T),
    ev: evOf(o.payoff, o.spot, sig, T),
    expMove: o.spot*sig*Math.sqrt(T)
  };
}

/* 收益网格：到期价 → 合计盈亏 + 对占用资金的回报率 */
function payoffGrid(o, rows){
  rows = rows || 17;
  var ks = o.strikes.map(function(x){ return x.k; });
  var lo = Math.min.apply(null, [o.spot*0.70].concat(ks.map(function(k){ return k*0.92; })));
  var hi = Math.max.apply(null, [o.spot*1.30].concat(ks.map(function(k){ return k*1.08; })));
  lo = Math.max(lo, 0.01);
  var step = (hi - lo)/(rows - 1), out = [];
  for(var i = 0; i < rows; i++){
    var S = lo + i*step, pl = o.payoff(S);
    out.push({s: S, pl: pl, ret: o.capital > 0 ? pl/o.capital : NaN,
              vsSpot: (S - o.spot)/o.spot});
  }
  return out;
}
/* ==== CORE-END ==== */

module.exports = { MULT, ncdf, pAbove, integrate, evOf, pWin, buildStrategy, riskStats, payoffGrid };
