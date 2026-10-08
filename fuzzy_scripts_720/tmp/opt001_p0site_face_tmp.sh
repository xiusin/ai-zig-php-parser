#!/bin/bash
# AOT-OPT-001 §5.13.4 遗留 #110：`rt>0 ∧ 非绿` 形逐枚归因（**只读、零插桩、零源码改动、非门控**）
#
# 本轮问题：#109 层 2 给出的是 P0 语义风险的**上界** 12/68（NC 关的是**整条** cfg_cleanup，比 P0 的
#   「只拦跳板形删块 + 异值入边」宽得多）⇒ 老铁裁决 §6.1 P0-b 之前，需要把上界**收窄成面值**。
#   判据（§5.13.4 原文）：对每枚形做「NC ⇄ ON 的 `main.zig` **按顶层 `fn` 区间**取 md5
#   ⇒ 漂移区间所属函数集合 ∩ P0 站点函数集合」：
#     不相交 ⇒ `NOT_P0_ATTRIBUTABLE`（漂移只来自其他清理规则 ⇒ 同 `f085` 口径，从 P0 风险面扣除）
#     相交   ⇒ `UNDETERMINED`（本层无法区分 ⇒ 升级为门控插桩议题）
#
# 名单来源 = **查表所得、禁硬编码**：#109 主表 TSV 的 `L1.refuse_tramp>0` ∩ `L2 非绿`（排除真值侧
#   `PHP_EXIT` 的 `f004`），再按 §5.13.4 排除已归因的 `f085` ⇒ 应得 11 枚。
#   ⚠ join 必须用**全名**（本语料 `f067_json_parser_schema_path_diff` 与 `f067_min_repro` 同前缀）。
#
# 臂 = 与 #109 层 1 / #107 默认档面**完全同档**：真默认档（无 `--optimize`、无 licm/迭代旗标
#   = `release_small` 的 1 轮 = 冻结基线档），唯一变量 `--aot-disable-pass=cfg-cleanup`。
#   ON 臂另用 `baseline_main_zig_md5.tsv` 逐字节自证（#109 已 68/68，此处逐形复检）。
#
# 已知坑（脚本内已防）：
#   · /bin/bash 3.2 禁 `declare -A` ⇒ 查表走 awk。
#   · #109/#107 主表为**竖线**分隔、基线表为 **TAB** 分隔 ⇒ 两套 `-F` 不得混用。
#   · `--aot-max-iterations` 坏值只打印 Error 却 rc=0 且不写产物 ⇒ 失败判据一律含「产物缺失」。
#   · **名字提取静默失败**（本轮实撞）：生成码函数头是 `pub fn @"Class::method"(`，正则若只锚 `^fn @"`
#     ⇒ 全部具名函数提取失败、回落整行 header ⇒ 与 IR 名域恒不相交 ⇒ 把 UNDETERMINED 洗成假否证。
#     分析器已加 `NAME_EXTRACT_FAIL` 阻断位；本脚本另在汇总里数 `err≠空` 的形，非 0 即本轮作废。
#   · f124/f085 类在 NC 臂**连生成码都没有**（`NOART`，#103 的发射侧硬依赖）⇒ 判 `NC_NO_EMISSION`，
#     不得读成「无漂移」。
# 铁律：禁止删除任何 `.php` 源；产物一律 `aot_compile_*`（禁与源同名）且**逐形即删**（`.zig` 单形约 1.4 MB）；
#   全部命令带 `timeout`；工作区收尾按显式路径删除。
cd /Users/wangjianjun/products/parser || exit 1

BIN="zig-out/bin/php-interpreter"
SRC_DIR="fuzzy_scripts_720/pass"
TMP_DIR="fuzzy_scripts_720/tmp"
TSV="$TMP_DIR/opt001_p0site_face_tmp.tsv"
PY="$TMP_DIR/opt001_p0site_intersect_tmp.py"
L109="$TMP_DIR/opt001_defaultlevel_emission_tmp.tsv"
BASELINE="fuzzy_scripts_720/baseline_main_zig_md5.tsv"
WORK="/tmp/opt001_p110"
EXCLUDE="${EXCLUDE:-f085_geo_rtree_knn_geocoder}"   # §5.13.4：已单独归因（NOART ∧ 其他清理规则）

[ -f "$PY" ]    || { echo "分析器缺失：$PY" >&2; exit 1; }
[ -f "$L109" ]  || { echo "#109 主表缺失：$L109" >&2; exit 1; }
[ -f "$BASELINE" ] || { echo "冻结基线表缺失：$BASELINE" >&2; exit 1; }

# 名单 = L1(rt>0) ∩ L2(非绿 ∧ 非 PHP_EXIT)，全名 join
names=$(awk -F'|' '$2=="L1" {sub(/^refuse_tramp=/,"",$9); if ($9+0>0) rt[$1]=$9}
                   $2=="L2" && $3!="PASS" && $3!="PHP_EXIT" { if ($1 in rt) printf "%s\n", $1 }' "$L109" \
        | grep -v -x "$EXCLUDE" | sort)
[ -n "$names" ] || { echo "名单为空（禁止把 0 枚读成全部可扣除）" >&2; exit 1; }
n_total=$(printf '%s\n' $names | wc -w | tr -d ' ')
if [ -n "${ONLY:-}" ]; then
  names=$(printf '%s\n' $names | grep -E "$ONLY")
  TSV="$TSV.rec"
  echo "[recovery run] ONLY=$ONLY -> $TSV（主表不动）"
fi

rt_get()  { awk -F'|' -v N="$1" '$2=="L1" && $1==N {sub(/^refuse_tramp=/,"",$9); print $9; exit}' "$L109"; }
l2_get()  { awk -F'|' -v N="$1" '$2=="L2" && $1==N {print $3; exit}' "$L109"; }
base_get() { awk -F'\t' -v N="$1" '!/^#/ && $1==N {print $2"/"$3; exit}' "$BASELINE"; }

rm -rf "$WORK"; mkdir -p "$WORK"
{
  echo "# opt001 §5.13.4 #110 rt>0∧非绿 逐枚归因 $(date '+%Y-%m-%d %H:%M:%S')"
  echo "bin_md5=$(md5 -q "$BIN")"
  echo "optimizer=$(md5 -q src/aot/optimizer.zig)/$(wc -l < src/aot/optimizer.zig | tr -d ' ')"
  echo "native_linker=$(md5 -q src/aot/native_linker.zig)/$(wc -l < src/aot/native_linker.zig | tr -d ' ')"
  echo "ir_generator=$(md5 -q src/aot/ir_generator.zig)"
  echo "analyzer=$(md5 -q "$PY") $(md5 -q "$TMP_DIR/opt001_droppedphi_tmp.py") $(md5 -q "$TMP_DIR/opt001_ir_stale_hoist_tmp.py")"
  echo "level=真默认档（release_small 1 轮 = 冻结基线档）  唯一变量=cfg_cleanup 开关  通道=--no-link + --emit-ir"
  echo "名单来源=#109 TSV 查表(L1.refuse_tramp>0 ∩ L2 非绿) 排除 $EXCLUDE  枚数=$n_total"
  echo "HEADER|tag|L2verdict|refuse_tramp|verdict|drift|p0_funcs|inter|drift_only|reg_on|reg_nc|unmatched|coverage|p0_tramp|p0_all|c2_on|c2_nc|c6_on|c6_nc|c9_on|c9_nc|on_vs_baseline|err|inter_names"
} > "$TSV"

START_TS=$(date +%s)
c_notattr=0; c_undet=0; c_noemi=0; c_err=0; c_nodrift=0; base_ok=0; base_miss=0
for n in $names; do
  src="$SRC_DIR/$n.php"
  [ -f "$src" ] || { echo "$n|P0SITE|-|-|SRC_MISSING" >> "$TSV"; c_err=$((c_err+1)); echo "  [$n] SRC_MISSING"; continue; }
  rt=$(rt_get "$n"); l2=$(l2_get "$n"); bo=$(base_get "$n")

  timeout 300 "$BIN" --compile --no-debug-info --no-link \
    --output="$WORK/aot_compile_${n}_on" --emit-ir="$WORK/ir_${n}_on.txt" "$src" >"$WORK/${n}_on.cerr" 2>&1
  rc_on=$?
  timeout 300 "$BIN" --compile --no-debug-info --no-link --aot-disable-pass=cfg-cleanup \
    --output="$WORK/aot_compile_${n}_nc" --emit-ir="$WORK/ir_${n}_nc.txt" "$src" >"$WORK/${n}_nc.cerr" 2>&1
  rc_nc=$?

  # ON 臂逐字节对账冻结基线（承 #109 自证 ①）
  bon="-"
  if [ -s "$WORK/aot_compile_${n}_on.zig" ]; then
    got=$(printf '%s/%s' "$(wc -l < "$WORK/aot_compile_${n}_on.zig" | tr -d ' ')" "$(md5 -q "$WORK/aot_compile_${n}_on.zig")")
    if [ "$got" = "$bo" ]; then bon="BASE_OK"; base_ok=$((base_ok+1)); else bon="BASE_MISS($got)"; base_miss=$((base_miss+1)); fi
  fi

  out=$(timeout 180 python3 "$PY" "$WORK/aot_compile_${n}_on.zig" "$WORK/aot_compile_${n}_nc.zig" \
              "$WORK/ir_${n}_on.txt" "$WORK/ir_${n}_nc.txt" --csv); rc=$?
  if [ $rc -ne 0 ] || [ -z "$out" ]; then
    verdict="ANALYZE_FAIL"; err="rc=$rc"
    drift=p; p0f=p; inter=p; donly=p; ro=p; rn=p; unm=p; cov=p; pt=p; pa=p
    c2o=-; c2n=-; c6o=-; c6n=-; c9o=-; c9n=-; iN="-"
  else
    # ⚠ 分析器在 err（末列）之后用 `|` 追加逐枚交集函数名 ⇒ 必须先切尾段再拆 18 列，
    #   否则 `|名字` 被最后一个变量吞进 err ⇒ 每条 UNDETERMINED 都被汇总误判成 ERR。
    case "$out" in
      *"|"*) iN=${out#*|}; head_part=${out%%|*} ;;
      *)     iN="-";      head_part="$out" ;;
    esac
    IFS=, read -r verdict drift p0f inter donly ro rn unm cov pt pa \
                    c2o c2n c6o c6n c9o c9n err <<<"$head_part"
    [ -n "$err" ] || err="OK"
    [ -n "$iN" ] || iN="-"
  fi
  case "$verdict" in
    NOT_P0_ATTRIBUTABLE) c_notattr=$((c_notattr+1)) ;;
    UNDETERMINED)        c_undet=$((c_undet+1)) ;;
    NC_NO_EMISSION)      c_noemi=$((c_noemi+1)) ;;
    NO_DRIFT)            c_nodrift=$((c_nodrift+1)) ;;
    *)                   c_err=$((c_err+1)) ;;
  esac
  echo "$n|P0SITE|$l2|rt=$rt|$verdict|drift=$drift|p0_funcs=$p0f|inter=$inter|drift_only=$donly|reg_on=$ro|reg_nc=$rn|unmatched=$unm|coverage=$cov|p0_tramp=$pt|p0_all=$pa|c2_on=$c2o|c2_nc=$c2n|c6_on=$c6o|c6_nc=$c6n|c9_on=$c9o|c9_nc=$c9n|$bon|${err:-OK}|$iN" >> "$TSV"
  printf '  [%s] %s drift=%s inter=%s p0f=%s (rt=%s L2=%s base=%s rc=%s/%s)\n' \
    "$n" "$verdict" "$drift" "$inter" "$p0f" "$rt" "$l2" "$bon" "$rc_on" "$rc_nc"

  rm -f "$WORK/aot_compile_${n}_on"* "$WORK/aot_compile_${n}_nc"* "$WORK/${n}_on.zig" "$WORK/${n}_nc.zig" \
        "$WORK/ir_${n}_on.txt" "$WORK/ir_${n}_nc.txt" "$WORK/${n}_on.cerr" "$WORK/${n}_nc.cerr"
done

{
  n_run=$(awk -F'|' '$2=="P0SITE" {n++} END {print n+0}' "$TSV")
  echo "P0SITE_DONE rows=$n_run 名单=$n_total not_attributable=$c_notattr undetermined=$c_undet nc_no_emission=$c_noemi no_drift=$c_nodrift analyze_or_other_err=$c_err base_ok=$base_ok base_miss=$base_miss"
  # 列契约：$1 shape | $2 tag(=P0SITE) | $3 L2 | $4 rt= | $5 verdict | $6 drift= | $7 p0_funcs= | $8 inter= |
  #   $9 drift_only= | $10 reg_on= | $11 reg_nc= | $12 unmatched= | $13 coverage= | $14 p0_tramp= | $15 p0_all= |
  #   $16 c2_on= | $17 c2_nc= | $18 c6_on= | $19 c6_nc= | $20 c9_on= | $21 c9_nc= |
  #   $22 base(无前缀) | $23 err(无前缀) | $24 inter_names
  # ⚠ $4..$21 带 `key=` 前缀 ⇒ 数值比较前必须 sub（承 #109 口径，否则交叉表静默出空面）；
  #   行过滤**只能**用 `$2=="P0SITE"` ⇒ 表头元信息行（`bin_md5=`/`level=`…）不含竖线分列，
  #   用宽松过滤（`$0!~/^#/ && $1!="HEADER"`）会把整段元信息当数据行打出来（本轮实撞）。
  printf "UNDETERMINED_SHAPES   = %s\n" "$(awk -F'|' '$2=="P0SITE" && $5=="UNDETERMINED" {printf "%s ", $1} END {print ""}' "$TSV")"
  printf "NOT_ATTRIBUTABLE      = %s\n" "$(awk -F'|' '$2=="P0SITE" && $5=="NOT_P0_ATTRIBUTABLE" {printf "%s ", $1} END {print ""}' "$TSV")"
  printf "NC_NO_EMISSION_SHAPES = %s\n" "$(awk -F'|' '$2=="P0SITE" && $5=="NC_NO_EMISSION" {printf "%s ", $1} END {print ""}' "$TSV")"
  printf "OTHER_VERDICTS        = %s\n" "$(awk -F'|' '$2=="P0SITE" && $5!="UNDETERMINED" && $5!="NOT_P0_ATTRIBUTABLE" && $5!="NC_NO_EMISSION" {printf "%s(%s) ", $1, $5} END {print ""}' "$TSV")"
  printf "INTER_SEVERITY        = %s\n" "$(awk -F'|' '$2=="P0SITE" && $5=="UNDETERMINED" {sub(/^inter=/,"",$8); s+=$8; n++; if ($8+0>mx) mx=$8+0} END {printf "shapes=%d Σinter_functions=%d max_per_shape=%d\n", n+0, s+0, mx+0}' "$TSV")"
  printf "DRIFT_ONLY_SEVERITY   = %s\n" "$(awk -F'|' '$2=="P0SITE" {sub(/^drift_only=/,"",$9); s+=$9; n++} END {printf "shapes=%d Σdrift_only_functions=%d\n", n+0, s+0}' "$TSV")"
  # P0 站点函数**整体**落在漂移集内的形数（inter == p0_funcs ⇒ 拦下删块必然改这些函数的生成码）
  printf "P0SITE_FULLY_DRIFTING = %s\n" "$(awk -F'|' '$2=="P0SITE" && $5!="NC_NO_EMISSION" {sub(/^p0_funcs=/,"",$7); sub(/^inter=/,"",$8); if ($7+0>0 && $7==$8) printf "%s ", $1} END {print ""}' "$TSV")"
  printf "P0SITE_PARTIAL        = %s\n" "$(awk -F'|' '$2=="P0SITE" && $5!="NC_NO_EMISSION" {sub(/^p0_funcs=/,"",$7); sub(/^inter=/,"",$8); if ($7+0>0 && $7!=$8) printf "%s(%s/%s) ", $1, $8, $7} END {print ""}' "$TSV")"
  # 侧探针：默认档两臂的发射链签名（C6/C9 = R1→R5 链的直接签名；C2 有基线底噪 ⇒ 只能取双臂 Δ）
  printf "CANARY_SUM            = %s\n" "$(awk -F'|' '$2=="P0SITE" {
      for (i=16;i<=21;i++) { split($i,kv,"="); v=(kv[2] ~ /^-?[0-9]+$/) ? kv[2]+0 : 0; s[i]+=v }
      n++ } END { printf "shapes=%d Σc2_on=%d Σc2_nc=%d Σc6_on=%d Σc6_nc=%d Σc9_on=%d Σc9_nc=%d\n", n+0, s[16], s[17], s[18], s[19], s[20], s[21] }' "$TSV")"
  printf "CANARY_NC_WORSE       = %s\n" "$(awk -F'|' '$2=="P0SITE" {
      split($16,a,"="); split($17,b,"="); split($18,c,"="); split($19,d,"="); split($20,e,"="); split($21,f,"=")
      if (b[2]+0>a[2]+0 || d[2]+0>c[2]+0 || f[2]+0>e[2]+0) printf "%s(c2 %s/%s c6 %s/%s c9 %s/%s) ", $1, a[2], b[2], c[2], d[2], e[2], f[2]
    } END {print ""}' "$TSV")"
  printf "ERR_SHAPES            = %s\n" "$(awk -F'|' '$2=="P0SITE" {if ($23!="" && $23!="OK") printf "%s(%s) ", $1, $23} END {print ""}' "$TSV")"
  printf "COVERAGE_NOT_OK       = %s\n" "$(awk -F'|' '$2=="P0SITE" {sub(/^coverage=/,"",$13); if ($13!="OK") printf "%s(%s) ", $1, $13} END {print ""}' "$TSV")"
  printf "BASELINE_NOT_OK       = %s\n" "$(awk -F'|' '$2=="P0SITE" && $5!="NC_NO_EMISSION" {if ($22!="BASE_OK") printf "%s(%s) ", $1, $22} END {print ""}' "$TSV")"
} | tee -a "$TSV"

echo "ELAPSED=$(( $(date +%s) - START_TS ))s" | tee -a "$TSV"
