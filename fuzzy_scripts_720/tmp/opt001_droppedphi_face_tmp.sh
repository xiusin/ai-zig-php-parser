#!/bin/bash
# AOT-OPT-001 §5.11-3 / 任务 #107：被 `cfg_cleanup` 丢弃块内的 phi 计数（**只读、零插桩、零源码改动、非门控**）
#
# 本轮问题：§6 P0 主修的判据是「删块前，若 target 的任一 phi 有以该块为入边、且取值与其它入边不同 ⇒ 拒绝删除」。
#   该判据的 **IR 侧命中面从未量过**（#97~#103 全部只数「已发生的症状」：C1/C6/C9 是发射侧或差分侧读数）。
#   ⇒ 落地前必须知道：P0 会拦下**多少枚**删块事件？其中多少落在 19 枚红形、多少落在语料其余绿形（= 保块代价）？
#   这决定选型的两件事：①P0 判据是否**够用**（红形命中数 vs §6 的 ≤10/19 上界）；②是否**过宽**（绿形命中 ⇒ 生成码变长/编译变慢）。
#
# 通道 = 层 A 双臂 `--no-link`（唯一变量 = `--aot-disable-pass=cfg-cleanup`），臂：
#   on = --aot-enable-pass=licm --aot-max-iterations=2          （清理开 ⇒ 臂块已被删）
#   nc = on + --aot-disable-pass=cfg-cleanup                    （清理关 ⇒ 臂块保留 = 删块前状态）
#   轮 2 = §5.8.5 的**最廉价饱和档**（判定面与轮 5 等值 ⇒ 命中集合不外漏）。
# 计数器 = 同目录永久分析器 opt001_droppedphi_tmp.py（内部 import §7 的 opt001_ir_stale_hoist_tmp.py，禁另写解析）：
#   dropped / label_only / tramp / phi_in_D / refuse_all / refuse_tramp / causeless / on_c1 / funcs / unmatched / err
#   `tramp` = D 内「唯一指令 = 无条件 br」的块 ⇒ **R2 `tryRemoveTrampolineBlock` 的真实准入**
#     （`optimizer.zig:4319` 块内零指令 ∧ `:4323` 终止符 `.br`）；`label_only`（「除终止符外无指令」）是**宽代理**
#     （含 ret/switch 等），只留作上界 ⇒ **P0 选型主读数 = refuse_tramp，禁拿 refuse_all 当验收目标**。
# ⚠ f124/f134 在 nc 臂有已知发射侧硬依赖（#103 的 4 条 SIG_COMPILE_FAIL）⇒ 本脚本**按文件存在性**取 IR：
#   rc≠0 但两枚 `.ir` 均落盘 ⇒ 仍计数，另落 `nc_rc=` 留痕（`--emit-ir` 在发射失败前已写出，读数有效）。
# 两面：FACES="red corpus" ⇒ red = #94 release-fast 红形 19 枚（与 #97~#103 同代次名单）；corpus = 68 枚 pass 语料全量。
# 环境坑：/bin/bash 3.2 禁 declare -A；BWK awk 禁三参 match；控制组 TSV 为竖线分隔；
#   `--aot-max-iterations` 坏值只打印 Error 却 rc=0 且不写产物 ⇒ 失败判据必含「产物缺失」。
# 铁律：禁止删除任何 .php 源；产物一律 aot_compile_* 且用完即删；全部命令带 timeout。
cd /Users/wangjianjun/products/parser || exit 1

BIN="zig-out/bin/php-interpreter"
SRC_DIR="fuzzy_scripts_720/pass"
TMP_DIR="fuzzy_scripts_720/tmp"
TSV="$TMP_DIR/opt001_droppedphi_face_tmp.tsv"
PY="$TMP_DIR/opt001_droppedphi_tmp.py"
WORK="/tmp/opt001_droppedphi"
FACES="${FACES:-red corpus}"
IT="${IT:-2}"
LICM="${LICM:-1}"   # 0 = 真·默认档（无 licm、无迭代旗标 ⇒ 结构体预设的 1 轮），用于实测 P0 的「默认档发射中性」前提
if [ "$LICM" = "0" ]; then
  ARM_FLAGS=""
  IT="default"
else
  ARM_FLAGS="--aot-enable-pass=licm --aot-max-iterations=$IT"
fi

[ -f "$PY" ] || { echo "分析器缺失：$PY" >&2; exit 1; }

case " $FACES " in
  *red*) rednames=$(awk -F'|' '$3=="DIFF" || $3=="RUNTIME_FAIL" {print $1}' "$TMP_DIR/c007_rf_face_tmp.tsv")
         [ -n "$rednames" ] || { echo "红形名单取数失败（禁止把空面读成全 0）" >&2; exit 1; } ;;
  *) rednames="" ;;
esac
if [ -n "${ONLY:-}" ]; then
  rednames=$(printf '%s\n' $rednames | grep -E "$ONLY")
  TSV="$TSV.rec"
  echo "[recovery run] ONLY=$ONLY -> $TSV（主表不动）"
fi
casenames=$(ls "$SRC_DIR" | sed -n 's/^\(.*\)\.php$/\1/p' | sort)

rm -rf "$WORK"; mkdir -p "$WORK"
{
  echo "# opt001 §5.11-3 被 cfg_cleanup 丢弃块内 phi 计数 $(date '+%Y-%m-%d %H:%M:%S')"
  echo "bin_md5=$(md5 -q "$BIN")"
  echo "optimizer=$(md5 -q src/aot/optimizer.zig)/$(wc -l < src/aot/optimizer.zig | tr -d ' ')"
  echo "native_linker=$(md5 -q src/aot/native_linker.zig)/$(wc -l < src/aot/native_linker.zig | tr -d ' ')"
  echo "ir_generator=$(md5 -q src/aot/ir_generator.zig)"
  echo "analyzer=$(md5 -q "$PY") $(md5 -q "$TMP_DIR/opt001_ir_stale_hoist_tmp.py")"
  echo "level=default(无 --optimize)  轮=$IT  唯一变量=cfg_cleanup 开关  faces=$FACES"
  echo "arm_flags=${ARM_FLAGS:-<空=真默认档 1 轮>}  LICM=$LICM"
  echo "HEADER|face|shape|COUNT|dropped|label_only|tramp|phi_in_D|refuse_all|refuse_tramp|causeless|on_c1|funcs|unmatched|err|rc"
} > "$TSV"

START_TS=$(date +%s)

run_face() { # $1=face名 $2=名单
  local face="$1" list="$2" n cnt=0 fail=0 noir=0
  for n in $list; do
    local src="$SRC_DIR/$n.php"
    [ -f "$src" ] || { echo "$face|$n|-|SRC_MISSING" >> "$TSV"; continue; }
    cnt=$((cnt+1))
    : > "$WORK/ir_${n}_on.txt"; : > "$WORK/ir_${n}_nc.txt"
    timeout 300 "$BIN" --compile --no-debug-info --no-link $ARM_FLAGS \
      --output="$WORK/aot_compile_${n}_on" --emit-ir="$WORK/ir_${n}_on.txt" "$src" >"$WORK/${n}_on.cerr" 2>&1
    local rc_on=$?
    timeout 300 "$BIN" --compile --no-debug-info --no-link $ARM_FLAGS \
      --aot-disable-pass=cfg-cleanup --output="$WORK/aot_compile_${n}_nc" --emit-ir="$WORK/ir_${n}_nc.txt" "$src" >"$WORK/${n}_nc.cerr" 2>&1
    local rc_nc=$?
    rm -f "$WORK/aot_compile_${n}_on" "$WORK/aot_compile_${n}_nc" \
          "$WORK/aot_compile_${n}_on.zig" "$WORK/aot_compile_${n}_nc.zig" \
          "$WORK/${n}_on.cerr" "$WORK/${n}_nc.cerr"
    if [ ! -s "$WORK/ir_${n}_on.txt" ] || [ ! -s "$WORK/ir_${n}_nc.txt" ]; then
      noir=$((noir+1))
      echo "$face|$n|NO_IR|rc_on=$rc_on|rc_nc=$rc_nc" >> "$TSV"
      echo "  [$face $n] NO_IR rc_on=$rc_on rc_nc=$rc_nc（该形计数作废，禁读成 0）"
      rm -f "$WORK/ir_${n}"_*.txt
      continue
    fi
    local out rc
    out=$(timeout 120 python3 "$PY" "$WORK/ir_${n}_on.txt" "$WORK/ir_${n}_nc.txt" --csv); rc=$?
    if [ $rc -ne 0 ] || [ "$(printf '%s' "$out" | tr -cd ',' | wc -c | tr -d ' ')" -ne 10 ]; then
      fail=$((fail+1))
      echo "$face|$n|ANALYZE_FAIL|rc=$rc|out=$out" | tr '\n' ' ' >> "$TSV"; echo >> "$TSV"
      echo "  [$face $n] ANALYZE_FAIL rc=$rc"
      rm -f "$WORK/ir_${n}"_*.txt
      continue
    fi
    IFS=, read -r dropped lonly tramp phidrop rall rtramp causeless onc1 funcs unmatched err <<<"$out"
    echo "$face|$n|COUNT|$dropped|$lonly|$tramp|$phidrop|$rall|$rtramp|$causeless|$onc1|$funcs|$unmatched|${err:-OK}|rc_on=$rc_on/rc_nc=$rc_nc" >> "$TSV"
    echo "  [$face $n] dropped=$dropped label_only=$lonly tramp=$tramp phi_in_D=$phidrop refuse_all=$rall refuse_tramp=$rtramp causeless=$causeless on_c1=$onc1 unmatched=$unmatched rc_nc=$rc_nc"
    rm -f "$WORK/ir_${n}"_*.txt
  done
  echo "FACE_DONE|$face|shapes=$cnt|noir=$noir|analyze_fail=$fail" | tee -a "$TSV"
}

for fc in $FACES; do
  case "$fc" in
    red)    run_face red "$rednames" ;;
    corpus) run_face corpus "$casenames" ;;
  esac
done

{
  echo "DROPPEDPHI_DONE faces=$(echo $FACES | wc -w | tr -d ' ') round=$IT"
  # 列契约（COUNT 行）：$1 face | $2 shape | $3 COUNT | $4 dropped | $5 label_only | $6 tramp | $7 phi_in_D
  #   | $8 refuse_all | $9 refuse_tramp | $10 causeless | $11 on_c1 | $12 funcs | $13 unmatched | $14 err | $15 rc
  for face in $FACES; do
    awk -F'|' -v F="$face" '$1==F && $3=="COUNT" {
        s+=$4; l+=$5; t+=$6; pd+=$7; ra+=$8; rt+=$9; c+=$10; o+=$11; shapes++;
        if ($9+0 > 0) { hit++ }
        if ($8+0 > 0 && $9+0 == 0) { allonly++ }
        if ($6+0 > 0) { tramp_hit++ }
        if ($4+0 > 0) { drop_hit++ }
        if ($13+0 != 0 || $14 != "OK") { bad++ }
      }
      END { printf "face %s: rows=%d align_or_parse_fail=%d | dropped>0 形=%d | tramp>0 形=%d | refuse_tramp>0 形=%d/%d | 仅 all 命中(tramp=0)形=%d | Σdropped=%d Σlabel_only=%d Σtramp=%d Σphi_in_D=%d Σrefuse_all=%d Σrefuse_tramp=%d Σcauseless=%d Σon_c1=%d\n",
        F, shapes, bad+0, drop_hit+0, tramp_hit+0, hit+0, shapes+0, allonly+0, s+0, l+0, t+0, pd+0, ra+0, rt+0, c+0, o+0 }' "$TSV"
    # 逐形极值（按 R2 严格准入命中枚数排序，取前 8）
    awk -F'|' -v F="$face" '$1==F && $3=="COUNT" { printf "%d %s %d %d %d %d\n", $9, $2, $6, $8, $7, $11 }' "$TSV" \
      | sort -k1,1nr -k2,2 | head -8 | awk '{printf "  top %-56s refuse_tramp=%s tramp=%s refuse_all=%s phi_in_D=%s on_c1=%s\n", $2, $1, $3, $4, $5, $6}'
    printf "  noir %s = %d\n" "$face" "$(awk -F'|' -v F="$face" '$1==F && $3=="NO_IR" {n++} END {print n+0}' "$TSV")"
  done
  # 红面对账：与 §5.10 的 17/19 签名面、§6 的 ≤10/19 上界同台比
  printf "RED_TRAMP_REFUSE_SHAPES = %s\n" "$(awk -F'|' '$1=="red" && $3=="COUNT" && $9+0>0 {printf "%s ", $2}' "$TSV")"
  printf "RED_TRAMP_BLIND_SHAPES  = %s\n" "$(awk -F'|' '$1=="red" && $3=="COUNT" && $9+0==0 {printf "%s ", $2}' "$TSV")"
  printf "RED_ALLONLY_SHAPES      = %s\n" "$(awk -F'|' '$1=="red" && $3=="COUNT" && $8+0>0 && $9+0==0 {printf "%s ", $2}' "$TSV")"
  printf "RED_C1ZERO_BUT_TRAMP_HIT = %s\n" "$(awk -F'|' '$1=="red" && $3=="COUNT" && $11+0==0 && $9+0>0 {printf "%s ", $2}' "$TSV")"
  printf "CORPUS_WITH_TRAMP_REFUSE = %s\n" "$(awk -F'|' '$1=="corpus" && $3=="COUNT" && $9+0>0 {printf "%s ", $2}' "$TSV")"
} | tee -a "$TSV"

echo "ELAPSED=$(( $(date +%s) - START_TS ))s" | tee -a "$TSV"
