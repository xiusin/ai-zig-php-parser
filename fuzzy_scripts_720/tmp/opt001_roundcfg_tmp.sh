#!/bin/bash
# AOT-OPT-001 §5.10：逐轮 × cfg_cleanup 两维交互（签名侧）（任务 #103，只读、零插桩、**零源码改动**）
#
# 本轮问题（承 §5.8.6 遗留 6）：#98/#100 只在**轮 5**（li5nc）量到一次「关 cfg_cleanup 后签名熄灭、
#   但输出面仍红」的症状迁移 ⇒ 该迁移是「轮 5 特有」还是「轮数无关」？
#   #101 已证判定面轮 2 封顶、幅值面轮 3 封顶 ⇒ 若 cfg_cleanup 的承重作用轮数无关，
#   则 §6 P0「删臂准入」判据在**任何** ≥2 轮档位同形；若在轮 2/3 关闭 cfg_cleanup 会把签名洗成 BLIND
#   而输出仍红，则「签名熄灭」不能读成「与 cfg_cleanup 无关」（#100 已立的禁令需在低轮复验）。
#
# 通道 = 层 A 只读签名（`--no-link`，#99/#101 实测单臂 0.01–0.02 s）：整轮秒级，不占编译资源。
#   base  = 默认档（不加旗标）= 1 轮、licm off
#   r2    = --aot-enable-pass=licm --aot-max-iterations=2
#   r2nc  = r2 + --aot-disable-pass=cfg-cleanup
#   r3    = 同上、轮 3
#   r3nc  = r3 + --aot-disable-pass=cfg-cleanup
#   （r5/r5nc = #100 的 li5/li5nc，同代次，已由汇总按列取自 opt001_c9_face_tmp.tsv ⇒ 禁止重跑）
# 金丝雀口径 = 第 2 代（§5.6.2）：C2/C6 按顶层 `fn` 区间归一、**只取对 base 的 Δ**，禁取绝对值。
# 分析器 = 永久资产 opt001_ir_stale_hoist_tmp.py（--csv 列序 c1,c4,c4h,c4b,c4bh,c7,h,hmatch,hloop,c2,c6,c9）
# 环境坑：/bin/bash 3.2 ⇒ 禁 declare -A；BWK awk ⇒ 禁三参 match；
#   ⚠ --aot-max-iterations 坏值只打印 Error 却 rc=0 且不写产物（main.zig:329-331）⇒ 失败判据必含「产物缺失」
# 铁律：禁止删除任何 .php 源；产物一律 aot_compile_* 且用完即删；全部命令带 timeout。
# 定点复算通道：ONLY=<egrep> 落 $TSV.rec（单一固定路径、每次整体重写 ⇒ 需要留证立刻 cp 归档，主表不动）
cd /Users/wangjianjun/products/parser || exit 1

BIN="zig-out/bin/php-interpreter"
SRC_DIR="fuzzy_scripts_720/pass"
TMP_DIR="fuzzy_scripts_720/tmp"
TSV="$TMP_DIR/opt001_roundcfg_tmp.tsv"
PY="$TMP_DIR/opt001_ir_stale_hoist_tmp.py"
WORK1="/tmp/opt001_roundcfg_sig"

# 名单与 #97/#98/#100/#101 同一代 = #94 release-fast 语料红面（DIFF ∪ RUNTIME_FAIL）
names=$(awk -F'|' '$3=="DIFF" || $3=="RUNTIME_FAIL" {print $1}' "$TMP_DIR/c007_rf_face_tmp.tsv")

if [ -n "${ONLY:-}" ]; then
  names=$(printf '%s\n' $names | grep -E "$ONLY")
  TSV="$TSV.rec"
  echo "[recovery run] ONLY=$ONLY -> $TSV（主表不动）"
fi

rm -rf "$WORK1"; mkdir -p "$WORK1"
{
  echo "# opt001 §5.10 逐轮 × cfg_cleanup 两维交互（签名侧） $(date '+%Y-%m-%d %H:%M:%S')"
  echo "bin_md5=$(md5 -q "$BIN")"
  echo "optimizer=$(md5 -q src/aot/optimizer.zig)/$(wc -l < src/aot/optimizer.zig | tr -d ' ')"
  echo "native_linker=$(md5 -q src/aot/native_linker.zig)/$(wc -l < src/aot/native_linker.zig | tr -d ' ')"
  echo "ir_generator=$(md5 -q src/aot/ir_generator.zig)"
  echo "level=default(无 --optimize)  唯一变量=轮数 × cfg_cleanup 开关"
  echo "r5/r5nc 来源=$TMP_DIR/opt001_c9_face_tmp.tsv（#100 同代次，不重跑）"
  echo "LAYERA_HEADER|shape|arm|C1|C2|C6|C9|C4h|C4bh|C7|H|hm|hl|ir|zig"
} > "$TSV"

START_TS=$(date +%s)

fl_for() {
  case "$1" in
    base) echo "" ;;
    *nc)  echo "--aot-enable-pass=licm --aot-max-iterations=$(printf '%s' "${1#r}" | tr -d 'nc') --aot-disable-pass=cfg-cleanup" ;;
    *)    echo "--aot-enable-pass=licm --aot-max-iterations=${1#r}" ;;
  esac
}

a_total=0; a_cfail=0
for n in $names; do
  src="$SRC_DIR/$n.php"
  [ -f "$src" ] || { echo "$n|-|NO_SRC" >> "$TSV"; continue; }
  a_total=$((a_total+1))
  bad_base=0; bad_r2=0; bad_r2nc=0; bad_r3=0; bad_r3nc=0
  for arm in base r2 r2nc r3 r3nc; do
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
  IFS=, read -r c1b _c4b c4hb _c4bb c4bhb _c7b _hb _hmb _hlb c2b c6b c9b <<<"$rb"

  for arm in r2 r2nc r3 r3nc; do
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

echo "ROUND_CFG_DONE total=$a_total arm_compile_fail=$a_cfail arm_rows=$(awk -F'|' '$2 ~ /^r[0-9](nc)?$/ && $3 ~ /^C1=/ {n++} END {print n+0}' "$TSV")" | tee -a "$TSV"
echo "ELAPSED=$(( $(date +%s) - START_TS ))s" | tee -a "$TSV"
