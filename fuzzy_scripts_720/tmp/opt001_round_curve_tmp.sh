#!/bin/bash
# AOT-OPT-001 §5.8 逐轮（1→5）点亮曲线（任务 #101，只读、零源码改动、零插桩、非门控）
#
# 本轮要补的缺口（§5.7.6-2 登记）：
#   #97 在迭代 3 上取到 C1 面 chain_hit=9；#100 在迭代 5 上取到签名面 17/19、输出面红 18/19。
#   ⇒ 只有**两端点**，没有曲线 ⇒ 「轮数是面变量」已实证，但「哪一轮点亮哪一枚」未知，
#     而这正是 PERF-001 §7 裁决项 1（max_iterations 3→5）唯一的定价依据：
#     若红面从第 2 轮就开始增长，则「抬到 5 轮」的风险不是台阶而是斜坡。
#
# 层 A（签名，--no-link，#99/#100 实测单臂 0.01–0.02 s）：
#   臂 = base(默认，LICM 关) / r1 / r2 / r3 / r4 ⇒ 每臂唯一变量 = --aot-max-iterations=N（配合 --aot-enable-pass=licm）
#   r5 的签名与输出读数**已由 #100 落盘**（opt001_c9_face_tmp.tsv，臂名 li5）⇒ 本 harness 不重跑，
#   由汇总器 opt001_round_curve_tmp.py 按列从那份 TSV 取数（禁复制读数字面量）。
#   ⚠ r3 臂与 #97 的 licm 臂（默认迭代 3）应等值 ⇒ 本轮顺带给 r3 做**跨 harness 等值自证**。
# 层 B（输出，全编译+链接+运行，真值 = /opt/homebrew/bin/php，官方 normalize_output）：
#   臂 = r1 / r2 / r3 / r4 ⇒ 与 #100 的 li5（=r5）输出面拼成 1→5 完整红面曲线。
#   逐枚生效性自证：逐轮 main.zig 行数+md5 序列，r1==r4 ⇒ 该枚记 NO_EFFECT。
# 签名口径（第 2 代，禁止取绝对值，只取对 base 的 delta）：
#   C1 phi 同源异值 ／ C6 = 结局 A ／ C9 = 结局 B ／ C4h/C4bh/C7 提升侧（C7 必带 hm/hl vs H 自证分母）
# 环境坑（本轮实测规约）：
#   · 本机 /bin/bash = 3.2 ⇒ **禁用** `declare -A` 关联数组 ⇒ 逐臂记账改用 eval + 间接展开 `${!var}`
#   · 本机 awk = BWK ⇒ **禁用** gawk 的三参 `match(s, r, arr)` 捕获组 ⇒ 曲线汇总交给独立 python 资产
# 铁律：禁止删除任何 .php 源；编译产物一律 aot_compile_*；每臂 IR/生成码用完即删；全部命令带 timeout。
# 定点复算通道：ONLY=<egrep> 落 $TSV.rec（单一固定路径、每次整体重写 ⇒ 需要留证的运行跑完立刻 cp 归档）
#              SKIP_LAYER_B=1 只跑层 A（层 A 秒级，层 B 十分钟级）
cd /Users/wangjianjun/products/parser || exit 1

BIN="zig-out/bin/php-interpreter"
PHP_BIN="/opt/homebrew/bin/php"
SRC_DIR="fuzzy_scripts_720/pass"
TMP_DIR="fuzzy_scripts_720/tmp"
TSV="$TMP_DIR/opt001_round_curve_tmp.tsv"
PY="$TMP_DIR/opt001_ir_stale_hoist_tmp.py"
CURVE_PY="$TMP_DIR/opt001_round_curve_tmp.py"
PREV="$TMP_DIR/opt001_c9_face_tmp.tsv"   # #100 的 r5 签名 + 输出面（同代次）
WORK1="/tmp/opt001_roundcurve_sig"
WORK2="/tmp/opt001_roundcurve_run"

# 名单来源与 #97/#98/#100 同一代 = #94 的 release-fast 语料红面（DIFF ∪ RUNTIME_FAIL）
names=$(awk -F'|' '$3=="DIFF" || $3=="RUNTIME_FAIL" {print $1}' "$TMP_DIR/c007_rf_face_tmp.tsv")

if [ -n "${ONLY:-}" ]; then
  names=$(printf '%s\n' $names | grep -E "$ONLY")
  TSV="$TSV.rec"
  echo "[recovery run] ONLY=$ONLY SKIP_LAYER_B=${SKIP_LAYER_B:-0} -> $TSV（主表不动）"
fi

rm -rf "$WORK1" "$WORK2"; mkdir -p "$WORK1" "$WORK2"
{
  echo "# opt001 §5.8 逐轮点亮曲线 $(date '+%Y-%m-%d %H:%M:%S')"
  echo "bin_md5=$(md5 -q "$BIN")"
  echo "optimizer=$(md5 -q src/aot/optimizer.zig)/$(wc -l < src/aot/optimizer.zig | tr -d ' ')"
  echo "native_linker=$(md5 -q src/aot/native_linker.zig)/$(wc -l < src/aot/native_linker.zig | tr -d ' ')"
  echo "level=default(无 --optimize)  层A=--no-link 签名  层B=全编译输出面  唯一变量=--aot-max-iterations=N"
  echo "r5 来源=$PREV（#100 层A 签名 / 层B 输出，同代次，不重跑）"
  echo "LAYERA_HEADER|shape|arm|C1|C2|C6|C9|C4h|C4bh|C7|H|hm|hl|ir|zig"
} > "$TSV"

# 臂名 rN ⇒ 旗标值取去掉 `r` 后的数字。
# ⚠ #101 实测踩坑：把臂名直接当值传（`--aot-max-iterations=r1`）时，CLI 只打印
#    `Error: Invalid --aot-max-iterations` 却**返回 rc=0** 且不写 IR/生成码
#    （src/main.zig:329-331 parseInt 失败分支）⇒ 本 harness 的臂失败判据必须含「产物文件缺失」，
#    只看 rc 会把整轮洗成 rc=0 的假成功（本轮靠该守卫拦住，未产出假读数）。
fl_for() { case "$1" in base) echo "" ;; *) echo "--aot-enable-pass=licm --aot-max-iterations=${1#r}" ;; esac; }

echo "=== LAYER A · 签名面（红形 × base/r1/r2/r3/r4，--no-link） ==="
a_total=0; a_cfail=0
for n in $names; do
  src="$SRC_DIR/$n.php"
  [ -f "$src" ] || { echo "$n|-|NO_SRC" >> "$TSV"; continue; }
  a_total=$((a_total+1))
  # 逐臂记账（#100 缺陷 1 的教训：一臂失败禁止连坐同形其余臂）；bash 3.2 ⇒ eval/间接展开代替关联数组
  bad_base=0; bad_r1=0; bad_r2=0; bad_r3=0; bad_r4=0
  for arm in base r1 r2 r3 r4; do
    ZIGPHP_AOT_KEEP_TEMP=0 timeout 300 "$BIN" --compile --no-debug-info --no-link $(fl_for "$arm") \
      --output="$WORK1/aot_compile_${n}_${arm}" \
      --emit-ir="$WORK1/ir_${n}_${arm}.txt" --dump-zig-path="$WORK1/zig_${n}_${arm}.txt" \
      "$src" >"$WORK1/${n}_${arm}.cerr" 2>&1
    rc=$?
    rm -f "$WORK1/aot_compile_${n}_${arm}" "$WORK1/aot_compile_${n}_${arm}.zig"
    jv="bad_$arm"
    if [ $rc -ne 0 ] || [ ! -f "$WORK1/ir_${n}_${arm}.txt" ] || [ ! -f "$WORK1/zig_${n}_${arm}.txt" ]; then
      eval "$jv=1"; a_cfail=$((a_cfail+1))
      reason=$(grep -m1 "error:" "$WORK1/${n}_${arm}.cerr" | head -c 140 | tr '\n' ' ')
      echo "$n|$arm|SIG_COMPILE_FAIL|rc=$rc|$reason" >> "$TSV"
      echo "  [$n $arm] SIG_COMPILE_FAIL rc=$rc $reason"
    else
      eval "$jv=0"
    fi
  done
  if [ "$bad_base" = "1" ]; then
    echo "$n|no_base|DELTA_VOID" >> "$TSV"; echo "[$n] base 臂失败 ⇒ 该形 delta 作废"
    rm -f "$WORK1/ir_${n}"_*.txt "$WORK1/zig_${n}"_*.txt; continue
  fi
  rb=$(python3 "$PY" "$WORK1/ir_${n}_base.txt" --zig "$WORK1/zig_${n}_base.txt" --csv); rb_rc=$?
  if [ $rb_rc -ne 0 ] || [ $(printf '%s' "$rb" | tr -cd ',' | wc -c | tr -d ' ') -ne 11 ]; then
    echo "$n|base|SIG_ANALYZE_FAIL|rc=$rb_rc" >> "$TSV"; echo "  [$n] base 分析失败 rc=$rb_rc"
    rm -f "$WORK1/ir_${n}"_*.txt "$WORK1/zig_${n}"_*.txt; continue
  fi
  # 分析器 --csv 列序：c1,c4,c4h,c4b,c4bh,c7,h,hmatch,hloop,c2,c6,c9
  IFS=, read -r _c1b _c4b c4hb _c4bb c4bhb _c7b _hb _hmb _hlb c2b c6b c9b <<<"$rb"
  c1b=$_c1b
  for arm in r1 r2 r3 r4; do
    jv="bad_$arm"; [ "${!jv}" = "1" ] && continue
    ra=$(python3 "$PY" "$WORK1/ir_${n}_${arm}.txt" --base "$WORK1/ir_${n}_base.txt" --zig "$WORK1/zig_${n}_${arm}.txt" --csv)
    ra_rc=$?
    if [ $ra_rc -ne 0 ] || [ $(printf '%s' "$ra" | tr -cd ',' | wc -c | tr -d ' ') -ne 11 ]; then
      echo "$n|$arm|SIG_ANALYZE_FAIL|rc=$ra_rc" >> "$TSV"; echo "  [$n $arm] SIG_ANALYZE_FAIL rc=$ra_rc"; continue
    fi
    IFS=, read -r c1 _c4 c4h _c4b c4bh c7 h hm hl c2 c6 c9 <<<"$ra"
    d1=$((c1 - c1b)); d2=$((c2 - c2b)); d6=$((c6 - c6b)); d9=$((c9 - c9b))
    cls="BLIND"
    [ $d6 -gt 0 ] && cls="A_HIT"
    [ $d9 -gt 0 ] && { [ "$cls" = "A_HIT" ] && cls="A+B_HIT" || cls="B_HIT"; }
    irl=$(wc -l < "$WORK1/ir_${n}_${arm}.txt" | tr -d ' '); zigl=$(wc -l < "$WORK1/zig_${n}_${arm}.txt" | tr -d ' ')
    echo "$n|$arm|C1=$c1b/$c1(d=$d1)|C2=$c2b/$c2(d=$d2)|C6=$c6b/$c6(d=$d6)|C9=$c9b/$c9(d=$d9)|C4h=$c4h|C4bh=$c4bh|C7=$c7/H=$h(hm=$hm,hl=$hl)|END_$cls|ir=$irl|zig=$zigl" >> "$TSV"
    echo "  [$n $arm] C1 d=$d1 C2 d=$d2 C6 d=$d6 C9 d=$d9 C4h=$c4h C4bh=$c4bh C7=$c7/H=$h => $cls"
  done
  rm -f "$WORK1/ir_${n}"_*.txt "$WORK1/zig_${n}"_*.txt
done
echo "LAYERA_DONE total=$a_total arm_compile_fail=$a_cfail arm_rows=$(awk -F'|' '$2 ~ /^r[0-9]$/ && $3 ~ /^C1=/ {n++} END {print n+0}' "$TSV")" | tee -a "$TSV"

if [ "${SKIP_LAYER_B:-0}" = "1" ]; then BNAMES=""; else BNAMES="$names"; fi
echo "=== LAYER B · 输出面（红形 × r1/r2/r3/r4，全编译+链接+运行） SKIP_LAYER_B=${SKIP_LAYER_B:-0} 待跑=$(echo $BNAMES | wc -w | tr -d ' ') 枚 ==="
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

b_total=0
for n in $BNAMES; do
  f="$SRC_DIR/$n.php"
  [ -f "$f" ] || { echo "$n|-|SRC_MISSING" >> "$TSV"; continue; }
  b_total=$((b_total+1))
  php_raw=$(timeout 10 "$PHP_BIN" "$f" 2>&1); php_rc=$?
  if [ $php_rc -ne 0 ]; then echo "$n|-|PHP_EXIT|exit=$php_rc" >> "$TSV"; echo "  [$n] PHP_EXIT $php_rc"; continue; fi
  php_norm=$(printf '%s\n' "$php_raw" | normalize_output)
  gens=""; g_r1=""; g_r2=""; g_r3=""; g_r4=""
  for arm in r1 r2 r3 r4; do
    out="$WORK2/aot_compile_${n}_${arm}"; cerr="$WORK2/${n}_${arm}.cerr"
    ZIGPHP_AOT_KEEP_TEMP=1 timeout 600 "$BIN" --compile --no-debug-info $(fl_for "$arm") --output="$out" "$f" >"$cerr" 2>&1
    c_rc=$?
    tdir=$(awk '/preserved/ {print $NF; exit}' "$cerr")
    gen="NOTEMP"
    if [ -n "$tdir" ] && [ -f "$tdir/main.zig" ]; then
      gen="$(wc -l < "$tdir/main.zig" | tr -d ' ')/$(md5 -q "$tdir/main.zig")"
      rm -rf "$tdir"
    fi
    gv="g_$arm"; eval "$gv=\"\$gen\""; gens="$gens $arm={$gen}"
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
    fi
  done
  eff="EFFECTIVE"
  [ "$g_r1" = "NOTEMP" ] && eff="NO_TEMP"
  if [ "$eff" = "EFFECTIVE" ] && [ "$g_r1" = "$g_r4" ]; then eff="NO_EFFECT"; fi
  echo "$n|curve_eff|$eff|gens=$gens" >> "$TSV"
  echo "  [$n] curve_eff=$eff$gens"
done

# 汇总：逐轮曲线交给独立 python 资产 opt001_round_curve_tmp.py（本机 awk 无 gawk 三参 match；一律列精确取数）
{
  echo "LAYERB_DONE total=$b_total"
  for arm in r1 r2 r3 r4; do
    cnt() { awk -F'|' -v A="$arm" -v V="$1" '$2==A && $3==V {n++} END {print n+0}' "$TSV"; }
    printf "arm %s: PASS=%d DIFF=%d RUNTIME_FAIL=%d TIMEOUT_10S=%d COMPILE_FAIL=%d\n" "$arm" \
      "$(cnt PASS)" "$(cnt DIFF)" "$(cnt RUNTIME_FAIL)" "$(cnt TIMEOUT_10S)" "$(cnt COMPILE_FAIL)"
  done
  python3 "$CURVE_PY" "$TSV" "$PREV"
} | tee -a "$TSV"

echo "ROUND_CURVE_DONE"
