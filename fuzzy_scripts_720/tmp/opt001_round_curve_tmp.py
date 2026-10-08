#!/usr/bin/env python3
"""AOT-OPT-001 §5.8 逐轮点亮曲线汇总（任务 #101，永久资产，禁删）。

输入两份 TSV（均 `|` 分隔）：
  argv[1] = 本轮 opt001_round_curve_tmp.tsv      ：臂名 r1/r2/r3/r4
  argv[2] = #100 的 opt001_c9_face_tmp.tsv       ：臂名 li5 ⇒ 当作 r5 列（同代次，禁止重跑）

行格式（层 A 签名行，与 opt001_c9_face_tmp.sh 落盘一致）：
  shape|arm|C1=b/x(d=Δ)|C2=b/x(d=Δ)|C6=b/x(d=Δ)|C9=b/x(d=Δ)|C4h=..|C4bh=..|C7=../H=..|END_类|ir=..|zig=..
  ⇒ 列 2=C1、4=C6、5=C9，只取 `(d=..)` 的 Δ（第 2 代口径：禁取绝对值）
行格式（层 B 输出行）：shape|arm|PASS|DIFF|RUNTIME_FAIL|TIMEOUT_10S|COMPILE_FAIL|gen=行数/md5|...
  ⇒ 仅认列 3 以 `gen=` 开头的判定行（#100 缺陷 2 的教训：不加此限定会把签名行当输出行计数）

口径要点（写死在此，禁止调用方复制读数字面量）：
  · sig_first = 三枚签名任一 Δ>0 的**最早**轮次；全轮未点亮 = BLIND
  · out_first = 输出面**最早**非 PASS 的轮次；全轮 PASS = GREEN；NA = 该臂未跑（不判为绿）
"""
import collections
import re
import sys

ROUNDS = ['r1', 'r2', 'r3', 'r4']
VERDICTS = ('PASS', 'DIFF', 'RUNTIME_FAIL', 'TIMEOUT_10S', 'COMPILE_FAIL')


def deltas(cols):
    """取 (ΔC1, ΔC6, ΔC9)；缺列或缺 `(d=..)` ⇒ None（不可当作 0）。"""
    out = []
    for i in (2, 4, 5):
        m = re.search(r'\(d=(-?\d+)\)', cols[i]) if len(cols) > i else None
        out.append(int(m.group(1)) if m else None)
    return out


def load(this_tsv, prev_tsv):
    sig = collections.defaultdict(dict)
    verdict = collections.defaultdict(dict)
    # ⚠ #101 实测缺陷（已修）：层 B 判定行只有 4–5 列（shape|arm|VERDICT|gen=..|d=..），
    #    与 12 列的签名行共用 `len(p) < 7` 守卫 ⇒ 全部输出行被静默丢弃 ⇒ CURVE_OUT_FIRSTROUND
    #    曾误报 GREEN=19。守卫必须按行类分别取长度门槛。
    for line in open(this_tsv, encoding='utf-8', errors='replace'):
        p = line.rstrip('\n').split('|')
        if len(p) < 4 or not re.fullmatch(r'r[1-4]', p[1]):
            continue
        if len(p) >= 7 and p[2].startswith('C1='):
            sig[p[0]][p[1]] = deltas(p)
        elif p[2] in VERDICTS and p[3].startswith('gen='):
            verdict[p[0]][p[1]] = p[2]
    for line in open(prev_tsv, encoding='utf-8', errors='replace'):
        p = line.rstrip('\n').split('|')
        if len(p) < 4 or p[1] != 'li5':
            continue
        if len(p) >= 7 and p[2].startswith('C1='):
            sig[p[0]]['r5'] = deltas(p)
        elif p[2] in VERDICTS and p[3].startswith('gen='):
            verdict[p[0]]['r5'] = p[2]
    return sig, verdict


def main():
    if len(sys.argv) != 3:
        print('usage: opt001_round_curve_tmp.py <round_curve.tsv> <c9_face.tsv>')
        return 2
    sig, verdict = load(sys.argv[1], sys.argv[2])
    print('CURVE_HEADER shape|sig_r1|r2|r3|r4|r5|sig_first|out_r1|r2|r3|r4|r5|out_first')
    sc, oc = collections.Counter(), collections.Counter()
    shapes = sorted(set(list(sig.keys()) + list(verdict.keys())))
    for s in shapes:
        marks = []
        for r in ROUNDS + ['r5']:
            d = sig.get(s, {}).get(r)
            marks.append('NA' if d is None else ('HIT' if any(x is not None and x > 0 for x in d) else '-'))
        first = next((str(i) for i, m in enumerate(marks, 1) if m == 'HIT'), 'BLIND')
        sc[first] += 1
        outs = [verdict.get(s, {}).get(r, 'NA') for r in ROUNDS + ['r5']]
        ofirst = next((str(i) for i, v in enumerate(outs, 1) if v not in ('PASS', 'NA')), 'GREEN')
        oc[ofirst] += 1
        print(f'CURVE {s}|{"|".join(marks)}|{first}|{"|".join(outs)}|{ofirst}')
    print('CURVE_SHAPES ' + str(len(shapes)))
    print('CURVE_SIG_FIRSTROUND ' + ' '.join(f'{k}={sc[k]}' for k in sorted(sc, key=str)))
    print('CURVE_OUT_FIRSTROUND ' + ' '.join(f'{k}={oc[k]}' for k in sorted(oc, key=str)))
    # 单调性自证：签名一旦点亮是否会在更高轮次回灭（只看有完整 r1..r5 读数的形）
    nonmono = []
    for s in shapes:
        seq = [any(x is not None and x > 0 for x in sig[s][r]) if r in sig[s] else None
               for r in ROUNDS + ['r5']]
        if any(v is None for v in seq):
            continue
        hit = [i for i, v in enumerate(seq) if v]
        if hit and hit != list(range(hit[0], len(seq))):
            nonmono.append(f'{s}:{"".join("1" if v else "0" for v in seq)}')
    print('CURVE_SIG_NONMONOTONIC ' + (' '.join(nonmono) if nonmono else 'NONE'))
    return 0


if __name__ == '__main__':
    sys.exit(main())
