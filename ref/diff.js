// 两侧逐值对账。数值用相对容差；**字符串必须逐字相同**（文案偏离过去正是靠这层漏掉的）。
const exp = require('./expected.json'), act = require('./actual.json');
const TOL = 1e-9;
let bad = [], nNum = 0, nStr = 0;

function cmp(path, a, b) {
  if (a === null || b === null || a === undefined || b === undefined) {
    if (!((a === null || a === undefined) && (b === null || b === undefined)))
      bad.push(`${path}: js=${JSON.stringify(a)} swift=${JSON.stringify(b)}`);
    return;
  }
  if (Array.isArray(a)) {
    if (!Array.isArray(b) || a.length !== b.length) {
      bad.push(`${path}: 长度 js=${a.length} swift=${Array.isArray(b) ? b.length : '非数组'}`); return;
    }
    a.forEach((v, i) => cmp(`${path}[${i}]`, v, b[i])); return;
  }
  if (typeof a === 'object') {
    const ka = Object.keys(a).sort(), kb = Object.keys(b || {}).sort();
    if (ka.join() !== kb.join()) bad.push(`${path}: 键集不同 js=[${ka}] swift=[${kb}]`);
    ka.forEach(k => cmp(`${path}.${k}`, a[k], b && b[k])); return;
  }
  if (typeof a === 'number') {
    nNum++;
    const d = Math.abs(a - b), rel = Math.abs(a) > 1 ? d / Math.abs(a) : d;
    if (!(rel <= TOL)) bad.push(`${path}: js=${a} swift=${b} rel=${rel.toExponential(2)}`);
    return;
  }
  nStr++;
  if (a !== b) bad.push(`${path}:\n      js    = ${JSON.stringify(a)}\n      swift = ${JSON.stringify(b)}`);
}

if (exp.length !== act.length) { console.log(`❌ 用例数不同 js=${exp.length} swift=${act.length}`); process.exit(1); }
if (!exp.length) { console.log('❌ 用例集为空 —— 拒绝在空集上报绿'); process.exit(2); }
exp.forEach((e, i) => cmp(`${e.kind}#${i}(n=${e.n},dte=${e.dte})`, e, act[i]));

console.log(`对账 ${exp.length} 条用例 / ${nNum} 个数值(容差 rel<=${TOL}) + ${nStr} 段文案(逐字)`);
if (bad.length) { console.log(`❌ ${bad.length} 处不一致：`); bad.slice(0, 25).forEach(s => console.log('   ' + s)); process.exit(1); }
console.log('✅ 全部一致');
