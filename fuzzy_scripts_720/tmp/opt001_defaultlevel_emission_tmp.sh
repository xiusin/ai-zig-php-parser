#!/bin/bash
# AOT-OPT-001 §5.13 / 轮次 **#109**：真·默认档 ON ⇄ NC 的**生成码面 + 运行面**实测
#   ⇒ 给 §6 P0 的前提「**默认档本环从不触发（`optimizer.zig:4319` 已挡）⇒ 理论上发射中性、冻结基线不动**」定价。
#   **只读、零插桩、零源码改动、非门控**（唯一变量 = `--aot-disable-pass=cfg-cleanup`，全部走 CLI）。
#
# 为什么必须测：#107（严格 R2 准入口径）实测到「真默认档 68 语料中 25 枚形存在『入边来自 R2 跳板形删块、
#   且取值与其它入边不同』的 phi ⇒ P0 判据在默认档**会**拦下删块」⇒ §6 的「从不触发」措辞已被否证。
#   但「拦下删块」是否等于「改生成码」仍未实测 ⇒ 本层把两件事分开量：
#   · 层 1（秒级）：ON ⇄ NC 的 `.zig` 产物**行数 + md5** 逐形比对 ⇒ 得到「拒绝删块 ⇒ 发射改动」的**上界面**
#     （NC 关的是**整条 cfg_cleanup**，比 P0 的「只拦跳板形 + 异值入边」宽得多 ⇒ 只能给上界，不能给 P0 面值）。
#   · 层 2（约 11 秒／形）：NC 臂**全编译 + 链接 + 运行**，输出经官方 `normalize_output` 比对系统 PHP 真值
#     ⇒ 回答「拒绝全部删块是否语义安全」。若 NC 臂 68/68 绿 ⇒ P0 的残余风险只剩**基线冻结成本**，不是错值。
#
# 三条自证（缺一条则本层读数作废）：
#   ① ON 臂 `.zig` 必须逐字节 == `fuzzy_scripts_720/baseline_main_zig_md5.tsv` 的冻结值（`BASELINE_OK`）
#      ⇒ 同时证明「`--no-link` 的 `<output>.zig` ≡ KEEP_TEMP 的 `main.zig`」（f016 单点已自证 46782/`c8dc9660…`）。
#   ② 层 2 的 NC `.zig` md5 必须 == 层 1 的 NC `.zig` md5（`L1EQ_L2`）⇒ 证明「链接与否不改发射」。
#   ③ 逐形带 #107 默认档表的 `refuse_tramp`（P0 命中枚数）⇒ 出交叉表，把「其他清理规则的改动」与
#      「P0 可能改动的形」分开（`L1_DIFF ∧ refuse_tramp>0` = **P0 中性无法由本层否证**的形集）。
#
# 已知坑（脚本内已防）：/bin/bash 3.2 禁 `declare -A` ⇒ 查表走 awk；BWK awk 禁三参 `match`；
#   基线表为 **TAB** 分隔、#107 表为**竖线**分隔 ⇒ 两套 `-F` 不得混用；跨表 join 必须用**全名**
#   （本语料 `f067_json_parser_schema_path_diff` 与 `f067_min_repro` 同前缀 ⇒ 短名 join 会 fan-out）；
#   `--aot-max-iterations` 坏值只打印 Error 却 rc=0 且不写产物 ⇒ 失败判据一律含「产物缺失」。
# 铁律：禁止删除任何 `.php` 源；产物一律 `aot_compile_*`（禁与源同名）且**逐形即删**（`.zig` 单形 2.3 MB）；
#   全部命令带 `timeout`；工作区收尾按显式路径删除。
cd /Users/wangjianjun/products/parser || exit 1

BIN="zig-out/bin/php-interpreter"
PHP_BIN="/opt/homebrew/bin/php"
SRC_DIR="fuzzy_scripts_720/pass"
TMP_DIR="fuzzy_scripts_720/tmp"
TSV="$TMP_DIR/opt001_defaultlevel_emission_tmp.tsv"
BASELINE="fuzzy_scripts_720/baseline_main_zig_md5.tsv"
DPHI="$TMP_DIR/opt001_droppedphi_face_tmp.tsv.r3-defaultlevel-stricttramp"
RFACE="$TMP_DIR/c007_rf_face_tmp.tsv"
WORK="/tmp/opt001_deflem"
SKIP_LAYER2="${SKIP_LAYER2:-0}"   # 1 = 只跑层 1（秒级）

[ -f "$BASELINE" ] || { echo "冻结基线表缺失：$BASELINE" >&2; exit 1; }
[ -f "$DPHI" ] || { echo "#107 默认档表缺失：$DPHI（层 1 交叉表取不到数 ⇒ 先跑 opt001_droppedphi_face_tmp.sh LICM=0）" >&2; exit 1; }

if [ -n "${ONLY:-}" ]; then
  names=$(ls "$SRC_DIR" | sed -n 's/^\(.*\)\.php$/\1/p' | sort | grep -E "$ONLY")
  TSV="$TSV.rec"
  echo "[recovery run] ONLY=$ONLY -> $TSV（主表不动）"
else
  names=$(ls "$SRC_DIR" | sed -n 's/^\(.*\)\.php$/\1/p' | sort)
fi
[ -n "$names" ] || { echo "语料名单为空（禁止把 total=0 读成全绿）" >&2; exit 1; }
shape_total=$(printf '%s\n' $names | wc -w | tr -d ' ')

rm -rf "$WORK"; mkdir -p "$WORK"
{
  echo "# opt001 §5.13 轮次#109 默认档 ON<->NC 生成码+运行面 $(date '+%Y-%m-%d %H:%M:%S')"
  echo "bin_md5=$(md5 -q "$BIN")"
  echo "optimizer=$(md5 -q src/aot/optimizer.zig)/$(wc -l < src/aot/optimizer.zig | tr -d ' ')"
  echo "native_linker=$(md5 -q src/aot/native_linker.zig)/$(wc -l < src/aot/native_linker.zig | tr -d ' ')"
  echo "ir_generator=$(md5 -q src/aot/ir_generator.zig)"
  echo "level=真默认档（无 --optimize、无 licm/迭代旗标 = release_small 预设 1 轮）  唯一变量=cfg_cleanup 开关"
  echo "arm_on=--compile --no-debug-info [--no-link]   arm_nc=同前 + --aot-disable-pass=cfg-cleanup"
  echo "baseline=$BASELINE  dphi(#107 默认档)=${DPHI##*/}  red(#94)=${RFACE##*/}"
  echo "L1_HEADER|shape|L1|verdict|on=lines/md5|nc=lines/md5|dlines|frozen=lines/md5|base_ok|refuse_tramp|red"
  echo "L2_HEADER|shape|L2|verdict|nc_gen=lines/md5|l1eq_l2|rt=exit|php_rc|detail"
} > "$TSV"

START_TS=$(date +%s)

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

# 查表走 awk（bash 3.2 无关联数组）。基线表 TAB 分隔、#107 表竖线分隔。
base_get()  { awk -F'\t' -v N="$1" -v C="$2" '!/^#/ && $1==N {print $C; exit}' "$BASELINE"; }
dphi_get()  { awk -F'|' -v N="$1" '$1=="corpus" && $2==N && $3=="COUNT" {print $9; exit}' "$DPHI"; }
red_get()   { awk -F'|' -v N="$1" '$1==N && ($3=="DIFF" || $3=="RUNTIME_FAIL") {print "1"; exit}' "$RFACE"; }
gen_of()    { # $1=.zig 路径 ⇒ "lines/md5"，缺产物 NOART
  if [ -s "$1" ]; then printf '%s/%s' "$(wc -l < "$1" | tr -d ' ')" "$(md5 -q "$1")"; else printf 'NOART/NOART'; fi
}

compile_zig() { # $1=out前缀 $2..=旗标 ⇒ 打印 "lines/md5"；产物即删
  local out="$1"; shift
  local z="$out.zig" g
  timeout 300 "$BIN" --compile --no-debug-info "$@" --output="$out" "$src" >"$out.cerr" 2>&1
  local rc=$?
  g=$(gen_of "$z")
  rm -f "$z" "$out" "$out.cerr"
  printf '%s|%s' "$g" "$rc"
}

l1_same=0; l1_diff=0; l1_noart=0; base_ok=0; base_miss=0; base_absent=0
l2_pass=0; l2_diff=0; l2_rfail=0; l2_cfail=0; l2_timeout=0; l1eq_ok=0; l1eq_neq=0; php_exit=0; nosrc=0
for n in $names; do
  src="$SRC_DIR/$n.php"
  [ -f "$src" ] || { echo "$n|L1|SRC_MISSING|on=-|nc=-|dlines=-|frozen=-|base_ok=-|refuse_tramp=-|red=-" >> "$TSV"; nosrc=$((nosrc+1)); continue; }
  rt=$(dphi_get "$n"); [ -n "$rt" ] || rt="NOROW"
  rd=$(red_get "$n");  [ -n "$rd" ] || rd="0"
  fl=$(base_get "$n" 2); fm=$(base_get "$n" 3)
  if [ -z "$fl" ] || [ -z "$fm" ]; then bok="BASELINE_ABSENT"; base_absent=$((base_absent+1))
  else bok="pending"; fi

  onr=$(compile_zig "$WORK/aot_compile_${n}_on" --no-link);  on="${onr%|*}";  on_rc="${onr##*|}"
  ncr=$(compile_zig "$WORK/aot_compile_${n}_nc" --no-link --aot-disable-pass=cfg-cleanup); nc="${ncr%|*}"; nc_rc="${ncr##*|}"
  on_L=${on%%/*}; on_M=${on##*/}; nc_L=${nc%%/*}; nc_M=${nc##*/}

  if [ "$on_L" = NOART ] || [ "$nc_L" = NOART ]; then
    v="NOART"; l1_noart=$((l1_noart+1))
  elif [ "$on_M" = "$nc_M" ]; then v="SAME"; l1_same=$((l1_same+1))
  else v="DIFF"; l1_diff=$((l1_diff+1))
  fi
  if [ "$on_L" = NOART ]; then :
  elif [ "$bok" = "pending" ]; then
    if [ "$on_L" = "$fl" ] && [ "$on_M" = "$fm" ]; then bok="BASELINE_OK"; base_ok=$((base_ok+1))
    else bok="BASELINE_MISS"; base_miss=$((base_miss+1)); v="$v+BASEMISS"
    fi
  fi
  if [ "$on_L" != NOART ] && [ "$nc_L" != NOART ]; then dl=$((nc_L - on_L)); else dl="-"; fi
  echo "$n|L1|$v|on=$on|nc=$nc|dlines=$dl|frozen=${fl:-NA}/${fm:-NA}|base_ok=$bok|refuse_tramp=$rt|red=$rd" >> "$TSV"
  printf '  [L1 %s] %s on=%s nc=%s Δ=%s base=%s refuse_tramp=%s red=%s (rc %s/%s)\n' \
    "$n" "$v" "$on_L" "$nc_L" "$dl" "$bok" "$rt" "$rd" "$on_rc" "$nc_rc"

  [ "$SKIP_LAYER2" = "1" ] && continue

  # ---- 层 2：NC 臂全编译 + 链接 + 运行，输出对系统 PHP 真值 ----
  php_raw=$(timeout 10 "$PHP_BIN" "$src" 2>&1); php_rc=$?
  if [ $php_rc -ne 0 ]; then
    echo "$n|L2|PHP_EXIT|nc_gen=-|l1eq_l2=-|rt=-|php_rc=$php_rc" >> "$TSV"; php_exit=$((php_exit+1))
    echo "  [L2 $n] PHP_EXIT rc=$php_rc（真值侧非 0 ⇒ 本形臂作废）"; continue
  fi
  php_norm=$(printf '%s\n' "$php_raw" | normalize_output)
  rout="$WORK/aot_compile_${n}_run"
  rerr="$WORK/${n}_run.cerr"
  ZIGPHP_AOT_KEEP_TEMP=1 timeout 600 "$BIN" --compile --no-debug-info --aot-disable-pass=cfg-cleanup --output="$rout" "$src" >"$rerr" 2>&1
  c_rc=$?
  # ⚠ 全编译（带链接）**不**会在 `--output` 旁边留 `<output>.zig`（那是 `--no-link` 专属）⇒ 生成码只能取 KEEP_TEMP 的 main.zig
  #   （承 #106 口径：目录名取自 `.cerr` 的 `preserved` 行）。
  tdir=$(awk '/preserved/ {print $NF; exit}' "$rerr")
  if [ -n "$tdir" ] && [ -s "$tdir/main.zig" ]; then ngen=$(gen_of "$tdir/main.zig"); rm -rf "$tdir"; else ngen="NOART/NOART"; fi
  if [ "$ngen" = "NOART/NOART" ]; then eq="NO_ART"; elif [ "${ngen%%/*}" = "$nc_L" ] && [ "${ngen##*/}" = "$nc_M" ]; then eq="L1EQ_L2"; l1eq_ok=$((l1eq_ok+1)); else eq="L1NE"; l1eq_neq=$((l1eq_neq+1)); fi
  if [ $c_rc -ne 0 ] || [ ! -x "$rout" ]; then
    reason=$(grep -m1 "error:" "$rerr" | head -c 160 | tr '\n' ' ' | tr '|' '/')
    echo "$n|L2|COMPILE_FAIL|nc_gen=$ngen|l1eq_l2=$eq|rt=rc$c_rc|php_rc=$php_rc|$reason" >> "$TSV"
    echo "  [L2 $n] COMPILE_FAIL rc=$c_rc eq=$eq"; l2_cfail=$((l2_cfail+1))
    rm -f "$rout" "$rout.zig" "$rerr"; continue
  fi
  rm -f "$rerr"
  aot_raw=$(timeout 10 "$rout" 2>&1); a_rc=$?
  aerr1=$(printf '%s\n' "$aot_raw" | grep -m1 -iE 'error|panic|traceback|Segmentation' | head -c 140 | tr '\n' ' ' | tr '|' '/')
  rm -f "$rout" "$rout.zig"
  aot_norm=$(printf '%s\n' "$aot_raw" | normalize_output)
  if [ $a_rc -ne 0 ]; then
    if [ $a_rc -eq 124 ]; then v2="TIMEOUT_10S"; l2_timeout=$((l2_timeout+1)); else v2="RUNTIME_FAIL"; l2_rfail=$((l2_rfail+1)); fi
    echo "$n|L2|$v2|nc_gen=$ngen|l1eq_l2=$eq|rt=exit$a_rc|php_rc=$php_rc|msg=$aerr1" >> "$TSV"
    echo "  [L2 $n] $v2 exit=$a_rc eq=$eq $aerr1"
  elif [ "$aot_norm" = "$php_norm" ]; then
    echo "$n|L2|PASS|nc_gen=$ngen|l1eq_l2=$eq|rt=exit0|php_rc=$php_rc" >> "$TSV"
    echo "  [L2 $n] PASS eq=$eq"; l2_pass=$((l2_pass+1))
  else
    d=$(diff <(printf '%s\n' "$php_norm") <(printf '%s\n' "$aot_norm") | head -6 | tr '\n' '~' | tr '|' '/' | head -c 300)
    echo "$n|L2|DIFF|nc_gen=$ngen|l1eq_l2=$eq|rt=exit0|php_rc=$php_rc|d=$d" >> "$TSV"
    echo "  [L2 $n] DIFF eq=$eq"; l2_diff=$((l2_diff+1))
  fi
done

{
  echo "DEFLEM_DONE shapes=$shape_total l1_same=$l1_same l1_diff=$l1_diff l1_noart=$l1_noart base_ok=$base_ok base_miss=$base_miss base_absent=$base_absent src_missing=$nosrc php_exit=$php_exit"
  echo "LAYER2_DONE skip=$SKIP_LAYER2 pass=$l2_pass diff=$l2_diff runtime_fail=$l2_rfail compile_fail=$l2_cfail timeout=$l2_timeout l1eq_ok=$l1eq_ok l1eq_neq=$l1eq_neq"
  # 列契约（L1 行）：$1 shape | $2 L1 | $3 verdict | $4 on= | $5 nc= | $6 dlines | $7 frozen= | $8 base_ok | $9 refuse_tramp | $10 red
  # ⚠ $6/$8/$9/$10 带 `key=` 前缀 ⇒ 数值/字面比较前**必须**先 sub 掉前缀（否则 `$9+0` 恒为 0、`$8=="X"` 恒不命中，
  #   交叉表会静默出空面并被误读成「无相关形」）。下列每条 awk 均在首个规则里 sub。
  echo "--- 交叉表（P0 中性前提）---"
  printf "L1_DIFF_SHAPES        = %s\n" "$(awk -F'|' '$2=="L1" && $3 ~ /^DIFF/ {printf "%s ", $1} END {print ""}' "$TSV")"
  printf "L1_SAME_SHAPES_TOTAL  = %s\n" "$(awk -F'|' '$2=="L1" && $3=="SAME" {n++} END {print n+0}' "$TSV")"
  # P0 命中 ∧ 发射有差 ⇒ 本层**无法**否证 P0 中性（NC 关整 pass ⇒ 只能定上界，不能定 P0 面值）
  printf "P0_MAY_DRIFT (DIFF ∧ refuse_tramp>0) = %s\n" "$(awk -F'|' '$2=="L1" && $3 ~ /^DIFF/ {sub(/^refuse_tramp=/,"",$9); if ($9+0>0) printf "%s ", $1} END {print ""}' "$TSV")"
  printf "P0_MAY_DRIFT_COUNT = %s\n" "$(awk -F'|' '$2=="L1" && $3 ~ /^DIFF/ {sub(/^refuse_tramp=/,"",$9); if ($9+0>0) n++} END {print n+0}' "$TSV")"
  # DIFF ∧ refuse_tramp==0 ⇒ 该形的发射差**只**来自其他清理规则 ⇒ 与 P0 无关
  printf "DIFF_NOT_P0 (DIFF ∧ refuse_tramp==0) = %s\n" "$(awk -F'|' '$2=="L1" && $3 ~ /^DIFF/ {sub(/^refuse_tramp=/,"",$9); if ($9=="0") printf "%s ", $1} END {print ""}' "$TSV")"
  printf "DIFF_NOT_P0_COUNT = %s\n" "$(awk -F'|' '$2=="L1" && $3 ~ /^DIFF/ {sub(/^refuse_tramp=/,"",$9); if ($9=="0") n++} END {print n+0}' "$TSV")"
  # SAME ∧ refuse_tramp>0 ⇒ P0 会拦下删块但发射逐字节不变（NC 整体等价于 ON ⇒ 拦这块必然中性）
  printf "P0_FREE (SAME ∧ refuse_tramp>0)      = %s\n" "$(awk -F'|' '$2=="L1" && $3=="SAME" {sub(/^refuse_tramp=/,"",$9); if ($9+0>0) printf "%s ", $1} END {print ""}' "$TSV")"
  printf "P0_FREE_COUNT = %s\n" "$(awk -F'|' '$2=="L1" && $3=="SAME" {sub(/^refuse_tramp=/,"",$9); if ($9+0>0) n++} END {print n+0}' "$TSV")"
  printf "BASELINE_MISS_SHAPES = %s\n" "$(awk -F'|' '$2=="L1" {sub(/^base_ok=/,"",$8); if ($8=="BASELINE_MISS") printf "%s ", $1} END {print ""}' "$TSV")"
  printf "BASELINE_ABSENT_SHAPES = %s\n" "$(awk -F'|' '$2=="L1" {sub(/^base_ok=/,"",$8); if ($8=="BASELINE_ABSENT") printf "%s ", $1} END {print ""}' "$TSV")"
  printf "BASELINE_OK_COUNT = %s\n" "$(awk -F'|' '$2=="L1" {sub(/^base_ok=/,"",$8); if ($8=="BASELINE_OK") n++} END {print n+0}' "$TSV")"
  printf "REFUSE_TRAMP_NOROW = %s\n" "$(awk -F'|' '$2=="L1" {sub(/^refuse_tramp=/,"",$9); if ($9=="NOROW") printf "%s ", $1} END {print ""}' "$TSV")"
  # Δlines 幅值面（NC 相对 ON 的行数差；只统计 DIFF 形）
  printf "DLINES_SUM_over_DIFF = %s\n" "$(awk -F'|' '$2=="L1" && $3 ~ /^DIFF/ {sub(/^dlines=/,"",$6); if ($6 ~ /^-?[0-9]+$/) s+=$6} END {print s+0}' "$TSV")"
  printf "L2_FAIL_SHAPES = %s\n" "$(awk -F'|' '$2=="L2" && $3!="PASS" {printf "%s(%s) ", $1, $3} END {print ""}' "$TSV")"
  # 红形（#94 名单）在默认档 NC 臂的表现 ⇒ 与 §5.5/§5.10 的「关整 pass 上界 10/19」同台比
  printf "L2_RED_NC_PASS = %s\n" "$(awk -F'|' '$2=="L1" {sub(/^red=/,"",$10); if ($10=="1") red[$1]=1} $2=="L2" && red[$1] && $3=="PASS" {n++} END {print n+0}' "$TSV")"
  printf "L2_RED_TOTAL = %s\n" "$(awk -F'|' '$2=="L1" {sub(/^red=/,"",$10); if ($10=="1") n++} END {print n+0}' "$TSV")"
} | tee -a "$TSV"

echo "ELAPSED=$(( $(date +%s) - START_TS ))s" | tee -a "$TSV"
