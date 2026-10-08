#!/bin/bash
# AOT-OPT-001 §5.7 结局 B 面扫 + 默认档 li5 因果面（任务 #100，只读、零源码改动、零插桩、非门控）
#
# 前置读数（同代次，均已落盘）：
#   · #97 金丝雀面扫（opt001_canary_sweep_tmp.tsv，19 红形 × base/licm 两臂，迭代 3）
#       ⇒ C1 签名面 chain_hit=9，第 2 代发射侧签名面 emit_hit=6。
#   · #98 旗标因果面（opt001_cfgclean_discriminant_tmp.tsv，19 红形 × release-fast 关 cfg_cleanup）
#       ⇒ PASS=10 DIFF=5 RUNTIME_FAIL=2 COMPILE_FAIL=2 ⇒ 因果面 10/19 > 签名面 9/19。
#   · #99 残红五形四臂（opt001_resid_hoist_tmp.tsv / opt001_resid_causal_tmp.tsv）
#       ⇒ 5 枚仍错值形全在同一条 R1→R2→R3→(R4)→R5 链上，只差发射结局：
#         4 枚结局 A（C1/C6 可见，臂拷贝全丢，寄存器停 initNull）
#         1 枚（f061）结局 B = **R3′「异块改写支」**：phi 入边被改写成「该前驱自己的名字」⇒
#         两条入边块名不同 ⇒ R4 的 then==else 折叠不触发 ⇒ IR 侧无同源异值 phi ⇒
#         **C1/C6/C2 全盲，只有 C9（PHI 标记的 if/else 一臂空、另一臂有赋值）能看见**。
#
# 本轮要回答的两个**尚未测过**的问题（旧数据无法回答，缺口是口径而非精度）：
#   Q1（结局 B 的面）：#99 的 C9 只在 5 枚残红上、在 li5 臂测过。其余 **14 枚红形从未跑过 li5 臂**
#      （#97 面扫只有 base/licm 两臂、迭代 3）⇒ 无法判断结局 B 是 f061 孤例还是有面。
#      ⚠ 关键：组 II 三形（f051/f061/f135）在迭代 3 是**绿**的，C9 必须在 **li5 臂**上才可能现身；
#      因此层 1 的对照臂取 li5/li5nc，而非 #97 的 licm。
#   Q2（最廉价复现通道的因果面）：#98 的因果面在 **release-fast 档**上取得（抬档 = 13 个变量同时变，
#      且该档 67/67 生成码漂移）。若「默认档 + --aot-enable-pass=licm --aot-max-iterations=5」
#      就能点亮这批红形里的一部分，则 P0 修法的复测代价从「全档回归」降到「两枚旗标」。
#      ⇒ 层 2 逐枚取 li5（应红）/ li5nc（关 cfg_cleanup 后应绿）的**输出面**，并逐枚自证生效性
#      （同形两臂 main.zig 行数+md5 必须不同，否则该形读数记 NO_EFFECT 作废）。
#
# 臂集与唯一变量：
#   层 1（签名，--no-link，实测单臂 0.01–0.02 s）：base(默认) / li5(默认+licm+迭代5) / li5nc(li5 再关 cfg-cleanup)
#   层 2（输出，全编译+链接+运行，真值 = /opt/homebrew/bin/php）：li5 / li5nc
# 签名口径（第 2 代，禁止取绝对值，只取双臂 delta；base 臂底噪已在 #99 实测）：
#   C1 phi 同源异值 ／ C2 本功能区间内声明无正常流赋值（严格版）／ C6 PHI 标记且区间内零赋值 = 结局 A
#   C9 PHI 标记的包裹 if/else 一臂空、另一臂有赋值 = **结局 B（本轮主角）**
#   C4h/C4bh/C7 提升侧签名（#99 在 5 形全否证）⇒ 本轮在 19 形复核面；C7 必带自证分母 hm/hl vs H，
#   hm、hl 不等于 H 时该形 C7 读数作废，禁止把 C7=0 读成「无臂内提升」。
# 铁律：禁止删除任何 .php 源；编译产物一律 aot_compile_*；每臂 IR/生成码用完即删；全部命令带 timeout。
cd /Users/wangjianjun/products/parser || exit 1

BIN="zig-out/bin/php-interpreter"
PHP_BIN="/opt/homebrew/bin/php"
SRC_DIR="fuzzy_scripts_720/pass"
TMP_DIR="fuzzy_scripts_720/tmp"
TSV="$TMP_DIR/opt001_c9_face_tmp.tsv"
PY="$TMP_DIR/opt001_ir_stale_hoist_tmp.py"
WORK1="/tmp/opt001_c9face_sig"
WORK2="/tmp/opt001_c9face_run"

# 19 枚红形名单来源 = #94 的 release-fast 语料面（DIFF ∪ RUNTIME_FAIL），与 #97/#98 同源
names=$(awk -F'|' '$3=="DIFF" || $3=="RUNTIME_FAIL" {print $1}' "$TMP_DIR/c007_rf_face_tmp.tsv")

# 定点复算通道（#100 收尾新增，为回收缺陷读数）：
#   ONLY=<egrep>  只跑名单子集，且落盘改写 $TSV.rec ⇒ **禁止覆盖 19 形主表**
#   SKIP_LAYER2=1 只跑层 1（层 2 全编译为 10 分钟级；签名层 --no-link 为秒级）
# ⚠ 陷阱（#100 实测踩过）：`.rec` 是**单一固定路径、每次运行整体重写**。窄 ONLY 的第二次运行
#    会把前一次全量运行（ONLY=.）的读数洗掉 ⇒ 需要留证的运行必须**跑完立刻 cp 归档**。
if [ -n "${ONLY:-}" ]; then
  names=$(printf '%s\n' $names | grep -E "$ONLY")
  TSV="$TSV.rec"
  echo "[recovery run] ONLY=$ONLY SKIP_LAYER2=${SKIP_LAYER2:-0} -> $TSV（主表不动）"
fi

rm -rf "$WORK1" "$WORK2"; mkdir -p "$WORK1" "$WORK2"
{
  echo "# opt001 §5.7 ending-B face sweep + default-档 li5 causal face $(date '+%Y-%m-%d %H:%M:%S')"
  echo "bin_md5=$(md5 -q "$BIN")"
  echo "optimizer=$(md5 -q src/aot/optimizer.zig)/$(wc -l < src/aot/optimizer.zig | tr -d ' ')"
  echo "native_linker=$(md5 -q src/aot/native_linker.zig)/$(wc -l < src/aot/native_linker.zig | tr -d ' ')"
  echo "level=default(无 --optimize)  层1=--no-link 签名  层2=全编译输出面  唯一变量=licm/迭代5/cfg-cleanup"
  echo "LAYER1_HEADER|shape|arm|C1|C2|C6|C9|C4h|C4bh|C7|H|hm|hl|ir|zig"
} > "$TSV"

echo "=== LAYER 1 · 签名面（19 红形 × base/li5/li5nc，--no-link） ==="
l1_total=0; l1_cfail=0; l1_bface=0; l1_aface=0
for n in $names; do
  src="$SRC_DIR/$n.php"
  [ -f "$src" ] || { echo "$n|-|NO_SRC" >> "$TSV"; continue; }
  l1_total=$((l1_total+1))
  fail_base=0; fail_li5=0; fail_li5nc=0
  for arm in base li5 li5nc; do
    case "$arm" in
      base)  fl="" ;;
      li5)   fl="--aot-enable-pass=licm --aot-max-iterations=5" ;;
      li5nc) fl="--aot-enable-pass=licm --aot-max-iterations=5 --aot-disable-pass=cfg-cleanup" ;;
    esac
    ZIGPHP_AOT_KEEP_TEMP=0 timeout 300 "$BIN" --compile --no-debug-info --no-link $fl \
      --output="$WORK1/aot_compile_${n}_${arm}" \
      --emit-ir="$WORK1/ir_${n}_${arm}.txt" --dump-zig-path="$WORK1/zig_${n}_${arm}.txt" \
      "$src" >"$WORK1/${n}_${arm}.cerr" 2>&1
    rc=$?
    rm -f "$WORK1/aot_compile_${n}_${arm}" "$WORK1/aot_compile_${n}_${arm}.zig"
    bad=0
    { [ $rc -ne 0 ] || [ ! -f "$WORK1/ir_${n}_${arm}.txt" ] || [ ! -f "$WORK1/zig_${n}_${arm}.txt" ]; } && bad=1
    case "$arm" in
      base)   fail_base=$bad ;;
      li5)    fail_li5=$bad ;;
      li5nc)  fail_li5nc=$bad ;;
    esac
    # ⚠ 本轮自我更正（原写法 `ok=0 ⇒ continue` 会因 li5nc 一臂失败丢掉**同形成功臂**的读数，
    #    f124/f134 的 li5 签名即被这样误丢 ⇒ 已改逐臂记账；cfg_cleanup 关闭态编译失败是 #98 的
    #    已知发射侧硬依赖，不是数据，不该连坐其余臂）
    if [ $bad -eq 1 ]; then
      reason=$(grep -m1 "error:" "$WORK1/${n}_${arm}.cerr" | head -c 140 | tr '\n' ' ')
      echo "$n|$arm|SIG_COMPILE_FAIL|rc=$rc|$reason" >> "$TSV"
      echo "  [$n $arm] SIG_COMPILE_FAIL rc=$rc $reason"
    fi
  done
  l1_cfail=$((l1_cfail + fail_base + fail_li5 + fail_li5nc))
  if [ $fail_base -eq 1 ]; then
    echo "$n|no_base|DELTA_VOID" >> "$TSV"; echo "[$n] base 臂失败 ⇒ 该形 delta 作废"
    rm -f "$WORK1/ir_${n}"_*.txt "$WORK1/zig_${n}"_*.txt
    continue
  fi
  # ⚠ 本轮自我更正：分析器一旦异常退出，$rb/$ra 为空 ⇒ 下方 delta 全变假读数（f134 曾因
  #    dom_sets 空块 IndexError 崩掉，被误记为 BLIND）。⇒ 所有分析器调用先校验退出码与 12 列。
  rb=$(python3 "$PY" "$WORK1/ir_${n}_base.txt" --zig "$WORK1/zig_${n}_base.txt" --csv)
  rb_rc=$?
  if [ $rb_rc -ne 0 ] || [ $(printf '%s' "$rb" | tr -cd ',' | wc -c | tr -d ' ') -ne 11 ]; then
    echo "$n|base|SIG_ANALYZE_FAIL|rc=$rb_rc" >> "$TSV"; echo "  [$n] base 分析失败 rc=$rb_rc"
    rm -f "$WORK1/ir_${n}"_*.txt "$WORK1/zig_${n}"_*.txt
    continue
  fi
  IFS=, read -r _c1b _c4b _c4hb _c4bb _c4bhb _c7b _hb _hmb _hlb c2b c6b c9b <<<"$rb"
  c1b=$_c1b
  for arm in li5 li5nc; do
    case "$arm" in
      li5)   [ $fail_li5 -eq 1 ] && continue ;;
      li5nc) [ $fail_li5nc -eq 1 ] && continue ;;
    esac
    ra=$(python3 "$PY" "$WORK1/ir_${n}_${arm}.txt" --base "$WORK1/ir_${n}_base.txt" --zig "$WORK1/zig_${n}_${arm}.txt" --csv)
    ra_rc=$?
    if [ $ra_rc -ne 0 ] || [ $(printf '%s' "$ra" | tr -cd ',' | wc -c | tr -d ' ') -ne 11 ]; then
      echo "$n|$arm|SIG_ANALYZE_FAIL|rc=$ra_rc" >> "$TSV"; echo "  [$n $arm] SIG_ANALYZE_FAIL rc=$ra_rc"; continue
    fi
    # 分析器 --csv 列序（opt001_ir_stale_hoist_tmp.py:404-406）：
    #   c1,c4,c4h,c4b,c4bh,c7,h,hmatch,hloop,c2,c6,c9
    IFS=, read -r c1 _c4 c4h _c4b c4bh c7 h hm hl c2 c6 c9 <<<"$ra"
    d1=$((c1 - c1b)); d2=$((c2 - c2b)); d6=$((c6 - c6b)); d9=$((c9 - c9b))
    cls="BLIND"
    [ $d6 -gt 0 ] && cls="A_HIT"
    [ $d9 -gt 0 ] && { [ "$cls" = "A_HIT" ] && cls="A+B_HIT" || cls="B_HIT"; }
    [ "$cls" = "B_HIT" ] && l1_bface=$((l1_bface+1))
    { [ "$cls" = "A_HIT" ] || [ "$cls" = "A+B_HIT" ]; } && l1_aface=$((l1_aface+1))
    irl=$(wc -l < "$WORK1/ir_${n}_${arm}.txt" | tr -d ' '); zigl=$(wc -l < "$WORK1/zig_${n}_${arm}.txt" | tr -d ' ')
    echo "$n|$arm|C1=$c1b/$c1(d=$d1)|C2=$c2b/$c2(d=$d2)|C6=$c6b/$c6(d=$d6)|C9=$c9b/$c9(d=$d9)|C4h=$c4h|C4bh=$c4bh|C7=$c7/H=$h(hm=$hm,hl=$hl)|END_$cls|ir=$irl|zig=$zigl" >> "$TSV"
    echo "  [$n $arm] C1 d=$d1 C2 d=$d2 C6 d=$d6 C9 d=$d9 C4h=$c4h C4bh=$c4bh C7=$c7/H=$h(hm=$hm,hl=$hl) => $cls"
    if [ -n "${DUMP_EV:-}" ] && [ "$arm" = "$DUMP_EV" ]; then
      {
        echo "===== $n arm=$arm 签名证据（C9 = 结局 B 半拷贝站点） ====="
        python3 "$PY" "$WORK1/ir_${n}_${arm}.txt" --base "$WORK1/ir_${n}_base.txt" --zig "$WORK1/zig_${n}_${arm}.txt" | head -30
      } >> "${EV:-/dev/null}"
    fi
  done
  rm -f "$WORK1/ir_${n}_base.txt" "$WORK1/zig_${n}_base.txt"
done
{
  echo "LAYER1_DONE total=$l1_total arm_compile_fail=$l1_cfail arm_rows=$(awk -F'|' '$2 ~ /^(li5|li5nc)$/ && $3 ~ /^C1=/ {n++} END {print n+0}' "$TSV")"
  echo "LAYER1_FACE B_HIT_only=$l1_bface A_or_AB=$l1_aface"
} | tee -a "$TSV"

if [ "${SKIP_LAYER2:-0}" = "1" ]; then L2NAMES=""; else L2NAMES="$names"; fi
echo "=== LAYER 2 · 输出面（红形 × li5/li5nc，全编译+链接+运行） SKIP_LAYER2=${SKIP_LAYER2:-0} 待跑=$(echo $L2NAMES | wc -w | tr -d ' ') 枚 ==="
normalize_output() {
    sed -E \
        -e 's/[[:space:]]*$//' \
        -e 's/^[[:space:]]*//' \
        -e 's/0x[0-9a-fA-F]{8,}/0xADDR/g' \
        -e 's|/tmp/aot_[a-z0-9_]+|TMPDIR|g' \
        -e 's/microtime\(true\)/MICROTIME/g' \
        -e 's/[0-9]+\.[0-9]{12,}/FLOAT/g' \
        -e 's/[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?/TIMESTAMP/g' \
        -e 's/in[[:space:]]+[^[:space:]:]+\.php:[0-9]+/in FILE:LINE/g' \
        | tr -s '\n' \
        | sed -E -e '/^$/d'
}

l2_total=0
for n in $L2NAMES; do
  f="$SRC_DIR/$n.php"
  [ -f "$f" ] || { echo "$n|-|SRC_MISSING" >> "$TSV"; continue; }
  l2_total=$((l2_total+1))
  php_raw=$(timeout 10 "$PHP_BIN" "$f" 2>&1); php_rc=$?
  if [ $php_rc -ne 0 ]; then echo "$n|-|PHP_EXIT|exit=$php_rc" >> "$TSV"; echo "  [$n] PHP_EXIT $php_rc"; continue; fi
  php_norm=$(printf '%s\n' "$php_raw" | normalize_output)
  gens=""
  G_li5="" G_li5nc=""
  for arm in li5 li5nc; do
    case "$arm" in
      li5)   fl="--aot-enable-pass=licm --aot-max-iterations=5" ;;
      li5nc) fl="--aot-enable-pass=licm --aot-max-iterations=5 --aot-disable-pass=cfg-cleanup" ;;
    esac
    out="$WORK2/aot_compile_${n}_${arm}"; cerr="$WORK2/${n}_${arm}.cerr"
    ZIGPHP_AOT_KEEP_TEMP=1 timeout 600 "$BIN" --compile --no-debug-info $fl --output="$out" "$f" >"$cerr" 2>&1
    c_rc=$?
    tdir=$(awk '/preserved/ {print $NF; exit}' "$cerr")
    gen="NOTEMP"
    if [ -n "$tdir" ] && [ -f "$tdir/main.zig" ]; then
      gen="$(wc -l < "$tdir/main.zig" | tr -d ' ')/$(md5 -q "$tdir/main.zig")"
      rm -rf "$tdir"
    fi
    gens="$gens $arm={$gen}"
    case "$arm" in
      li5)   G_li5="$gen" ;;
      li5nc) G_li5nc="$gen" ;;
    esac
    if [ $c_rc -ne 0 ]; then
      reason=$(grep -m1 "error:" "$cerr" | head -c 160 | tr '\n' ' ')
      echo "$n|$arm|COMPILE_FAIL|gen=$gen|$reason" >> "$TSV"
      echo "  [$n $arm] COMPILE_FAIL $reason"; rm -f "$out" "$cerr"; continue
    fi
    aot_raw=$(timeout 10 "$out" 2>&1); a_rc=$?
    rm -f "$out" "$cerr"
    aot_norm=$(printf '%s\n' "$aot_raw" | normalize_output)
    if [ $a_rc -ne 0 ]; then
      v="RUNTIME_FAIL"; [ $a_rc -eq 124 ] && v="TIMEOUT_10S"
      echo "$n|$arm|$v|gen=$gen|exit=$a_rc" >> "$TSV"; echo "  [$n $arm] $v exit=$a_rc"; continue
    fi
    if [ "$aot_norm" = "$php_norm" ]; then
      echo "$n|$arm|PASS|gen=$gen" >> "$TSV"; echo "  [$n $arm] PASS gen=$gen"
    else
      d=$(diff <(printf '%s\n' "$php_norm") <(printf '%s\n' "$aot_norm") | head -6 | tr '\n' '~' | head -c 300)
      echo "$n|$arm|DIFF|gen=$gen|d=$d" >> "$TSV"; echo "  [$n $arm] DIFF gen=$gen"
      echo "      d=$d"
    fi
  done
  # 生效性自证：同形两臂 main.zig 的行数+md5 必须不同，否则该形输出面读数作废
  if [ "$G_li5" = "NOTEMP" ] || [ "$G_li5nc" = "NOTEMP" ]; then
    eff="NO_TEMP"
  elif [ "$G_li5" = "$G_li5nc" ]; then
    eff="NO_EFFECT"
  else
    eff="EFFECTIVE"
  fi
  echo "$n|causal_eff|$eff|gens=$gens" >> "$TSV"
  echo "  [$n] causal_eff=$eff$gens"
done

# 汇总一律按列精确取数（#99 的 BISECT_SUMMARY 缺陷教训：`grep -c "|$p|"` 永不匹配 `no_$p` 这类标签）
{
  echo "LAYER2_DONE total=$l2_total"
  for arm in li5 li5nc; do
    cnt() { awk -F'|' -v A="$arm" -v V="$1" '$2==A && $3==V {n++} END {print n+0}' "$TSV"; }
    printf "arm %s: PASS=%d DIFF=%d RUNTIME_FAIL=%d TIMEOUT_10S=%d COMPILE_FAIL=%d\n" "$arm" \
      "$(cnt PASS)" "$(cnt DIFF)" "$(cnt RUNTIME_FAIL)" "$(cnt TIMEOUT_10S)" "$(cnt COMPILE_FAIL)"
  done
  printf "causal_eff: EFFECTIVE=%d NO_EFFECT=%d NO_TEMP=%d\n" \
    "$(awk -F'|' '$2=="causal_eff" && $3=="EFFECTIVE" {n++} END {print n+0}' "$TSV")" \
    "$(awk -F'|' '$2=="causal_eff" && $3=="NO_EFFECT" {n++} END {print n+0}' "$TSV")" \
    "$(awk -F'|' '$2=="causal_eff" && $3=="NO_TEMP" {n++} END {print n+0}' "$TSV")"
  # ⚠ 本轮自我更正：层 1 签名行的 $2 同样是 li5/li5nc 且 $3 不是 PASS，原写法 `bad[]` 会把**每一枚**
  #    形都登记进去 ⇒ f152（两臂皆绿、已判 NO_EFFECT）被误计为「关 cfg_cleanup 转绿」，该列读数虚高 1。
  #    ⇒ 已限定为层 2 判定行（$4 以 gen= 开头）。
  echo "LAYER2_GREEN_BY_CLOSING_CFG=$(awk -F'|' '$4 ~ /^gen=/ && $2=="li5" && $3!="PASS" {bad[$1]=1} $4 ~ /^gen=/ && $2=="li5nc" && $3=="PASS" && bad[$1] {n++} END {print n+0}' "$TSV")"
} | tee -a "$TSV"

echo "C9_FACE_DONE"
