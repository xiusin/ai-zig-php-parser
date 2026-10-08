#!/bin/bash
# AOT-OPT-001 §5.10 未闭合的半边：轮 2/3 的**输出侧** nc 面（任务 #106，只读、零插桩、**零源码改动**、非门控）
#
# 本轮问题（承 §5.10「未闭合的半边」/§5.8.6 遗留 6）：#98/#100 只在**轮 5**（`li5nc`）量到一次
#   「关 cfg_cleanup ⇒ 签名全体熄灭，但输出面仍红」。#103 已在**签名侧**证明该熄灭轮数无关
#   （r2nc/r3nc = 17/17 BLIND）。但「签名熄灭 ≠ 与 cfg_cleanup 无关」这条禁令（#100 立）在**输出侧**
#   只有轮 5 一个读数 ⇒ 若轮 2/3 的 nc 臂仍红，则该禁令在任意 ≥2 轮档位三面同立；
#   若轮 2/3 的 nc 臂全绿，则 #100 的轮 5 残红另有轮数依赖成因 ⇒ P0 验收档（`--aot-max-iterations=2`）
#   的「残留 ≤ 8」预期需按轮数改写。**两个方向都有信息量 ⇒ 必测。**
#
# 臂集（唯一变量 = 轮数 × cfg_cleanup 开关，均相对默认档，无 --optimize）：
#   r2nc = --aot-enable-pass=licm --aot-max-iterations=2 --aot-disable-pass=cfg-cleanup
#   r3nc = 同上、轮 3
#   （r5nc = #100 的 li5nc，同代次已落盘 ⇒ 禁止重跑；r2/r3 控制面 = #101 曲线层 B，本脚本只读比对）
# 控制面取数（不重跑）：fuzzy_scripts_720/tmp/opt001_round_curve_tmp.tsv
#   · 判定行 = `# FIXED CURVE <形>|sig_r1..r5|sig_first|out_r1..r5|out_first`
#     （⚠ 必须用 FIXED 块：块前的同名 CURVE 行是 #101 已作废的取数缺陷产物）
#   · 生成码 = 同文件 `curve_eff` 行的 `gens= r1={L/H} r2={L/H} r3={L/H} r4={L/H}`
# 真值 = /opt/homebrew/bin/php（官方 normalize_output 归一）；产物命名 aot_compile_* 且逐臂即删。
# 列契约（汇总一律按列精确取数，禁 grep 子串）：
#   $1 shape | $2 arm | $3 verdict | $4 gen=<L/H> | $5 ctrl=<verdict>/<L/H> | $6 eff=<…> | $7+ 附加
# 已知坑（脚本内已防）：/bin/bash 3.2 禁 declare -A；BWK awk 禁三参 match；控制组 TSV 为**竖线**分隔；
#   `--aot-max-iterations` 坏值只打印 Error 却 rc=0 ⇒ 判据含「产物缺失」；KEEP_TEMP 目录名取自 .cerr 的 preserved 行。
# 铁律：禁止删除任何 .php 源；全部命令带 timeout；产物与 /tmp 工作区收尾按显式路径删除。
cd /Users/wangjianjun/products/parser || exit 1

BIN="zig-out/bin/php-interpreter"
PHP_BIN="/opt/homebrew/bin/php"
SRC_DIR="fuzzy_scripts_720/pass"
TMP_DIR="fuzzy_scripts_720/tmp"
TSV="$TMP_DIR/opt001_roundcfg_out_tmp.tsv"
CURVE="$TMP_DIR/opt001_round_curve_tmp.tsv"
RFACE="$TMP_DIR/c007_rf_face_tmp.tsv"
WORK="/tmp/opt001_roundcfg_out"

# 名单 = #94 release-fast 语料红面（DIFF ∪ RUNTIME_FAIL），与 #97/#98/#100/#101/#103 同代次
names=$(awk -F'|' '$3=="DIFF" || $3=="RUNTIME_FAIL" {print $1}' "$RFACE")
[ -n "$names" ] || { echo "红形名单为空：$RFACE 取数失败（禁止把 total=0 读成全绿）" >&2; exit 1; }

if [ -n "${ONLY:-}" ]; then
  names=$(printf '%s\n' $names | grep -E "$ONLY")
  TSV="$TSV.rec"
  echo "[recovery run] ONLY=$ONLY -> $TSV（主表不动）"
fi

[ -f "$CURVE" ] || { echo "控制面缺失：$CURVE" >&2; exit 1; }
rm -rf "$WORK"; mkdir -p "$WORK"
{
  echo "# opt001 §5.10 输出侧 nc 面（轮 2/3）$(date '+%Y-%m-%d %H:%M:%S')"
  echo "bin_md5=$(md5 -q "$BIN")"
  echo "optimizer=$(md5 -q src/aot/optimizer.zig)/$(wc -l < src/aot/optimizer.zig | tr -d ' ')"
  echo "native_linker=$(md5 -q src/aot/native_linker.zig)/$(wc -l < src/aot/native_linker.zig | tr -d ' ')"
  echo "ir_generator=$(md5 -q src/aot/ir_generator.zig)"
  echo "level=default(无 --optimize)  唯一变量=轮数 × cfg_cleanup 开关"
  echo "控制面=$CURVE（#101 层 B FIXED 块 + curve_eff 行，只读不重跑）"
  echo "OUT_HEADER|shape|arm|verdict|gen=|ctrl=|eff=|extra"
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

# 控制面判定行：split 后 p[1]="# FIXED CURVE <形>"，p[2..6]=sig_r1..r5，p[7]=sig_first，p[8..12]=out_r1..r5
ctrl_verdict() { # $1=shape $2=out 下标（9=r2, 10=r3）
  awk -v S="$1" -v C="$2" 'index($0, "# FIXED CURVE " S "|") == 1 {
      n = split($0, p, "|"); if (n >= C) print p[C]; else print "NOROW"
    }' "$CURVE"
}
ctrl_gen() { # $1=shape $2=轮标签（r2/r3）⇒ curve_eff 的 gens= 里该轮的 L/H
  awk -F'|' -v S="$1" -v K="$2" '$1 == S && $2 == "curve_eff" {
      pat = K "={"
      i = index($0, pat)
      if (i == 0) { print "NOGEN"; exit }
      rest = substr($0, i + length(pat))
      j = index(rest, "}")
      if (j == 0) { print "NOGEN"; exit }
      print substr(rest, 1, j - 1)
    }' "$CURVE"
}

total=0; cfail=0; phpexit=0; nosrc=0
for n in $names; do
  f="$SRC_DIR/$n.php"
  [ -f "$f" ] || { echo "$n|-|SRC_MISSING|gen=-|ctrl=-|eff=-" >> "$TSV"; nosrc=$((nosrc+1)); continue; }
  total=$((total+1))
  php_raw=$(timeout 10 "$PHP_BIN" "$f" 2>&1); php_rc=$?
  if [ $php_rc -ne 0 ]; then
    echo "$n|-|PHP_EXIT|gen=-|ctrl=-|eff=-|exit=$php_rc" >> "$TSV"; phpexit=$((phpexit+1))
    echo "  [$n] PHP_EXIT rc=$php_rc（真值侧非 0 ⇒ 本形作废，不计入臂面）"; continue
  fi
  php_norm=$(printf '%s\n' "$php_raw" | normalize_output)
  for arm in r2nc r3nc; do
    case "$arm" in
      r2nc) it=2; ctl=r2; cidx=9 ;;
      r3nc) it=3; ctl=r3; cidx=10 ;;
    esac
    cg=$(ctrl_gen "$n" "$ctl")
    cv=$(ctrl_verdict "$n" "$cidx")
    out="$WORK/aot_compile_${n}_${arm}"; cerr="$WORK/${n}_${arm}.cerr"
    ZIGPHP_AOT_KEEP_TEMP=1 timeout 600 "$BIN" --compile --no-debug-info \
      --aot-enable-pass=licm --aot-max-iterations=$it --aot-disable-pass=cfg-cleanup \
      --output="$out" "$f" >"$cerr" 2>&1
    c_rc=$?
    tdir=$(awk '/preserved/ {print $NF; exit}' "$cerr")
    gen="NOTEMP"
    if [ -n "$tdir" ] && [ -f "$tdir/main.zig" ]; then
      gen="$(wc -l < "$tdir/main.zig" | tr -d ' ')/$(md5 -q "$tdir/main.zig")"
      rm -rf "$tdir"
    fi
    # 生效性自证（先算，编译失败臂也要留痕）：nc 臂生成码必须 ≠ 同轮非 nc 臂生成码
    if [ "$gen" = "NOTEMP" ] || [ "$cg" = "NOGEN" ] || [ -z "$cg" ]; then
      eff="NO_TEMP"
    elif [ "$gen" = "$cg" ]; then
      eff="NO_EFFECT"
    else
      eff="EFFECTIVE"
    fi
    # 口径更正（#106 冒烟轮）：编译失败臂的 gen=NOTEMP 是「链接前即失败 ⇒ 无 main.zig」，
    # 与「preserved 行缺失」同标签会把两种成因混进一个分母 ⇒ 单列 CFAIL_NO_TEMP。
    if [ $c_rc -ne 0 ] && [ "$gen" = "NOTEMP" ]; then
      eff="CFAIL_NO_TEMP"
    fi
    if [ $c_rc -ne 0 ] || [ ! -x "$out" ]; then
      reason=$(grep -m1 "error:" "$cerr" | head -c 160 | tr '\n' ' ' | tr '|' '/')
      echo "$n|$arm|COMPILE_FAIL|gen=$gen|ctrl=$cv/$cg|eff=$eff|rc=$c_rc|$reason" >> "$TSV"
      echo "  [$n $arm] COMPILE_FAIL rc=$c_rc eff=$eff $reason"; cfail=$((cfail+1))
      rm -f "$out" "$out.zig" "$cerr"; continue
    fi
    aot_raw=$(timeout 10 "$out" 2>&1); a_rc=$?
    rm -f "$out" "$out.zig" "$cerr"
    aot_norm=$(printf '%s\n' "$aot_raw" | normalize_output)
    if [ $a_rc -ne 0 ]; then
      v="RUNTIME_FAIL"; [ $a_rc -eq 124 ] && v="TIMEOUT_10S"
      echo "$n|$arm|$v|gen=$gen|ctrl=$cv/$cg|eff=$eff|exit=$a_rc" >> "$TSV"
      echo "  [$n $arm] $v exit=$a_rc eff=$eff"
      continue
    fi
    if [ "$aot_norm" = "$php_norm" ]; then
      echo "$n|$arm|PASS|gen=$gen|ctrl=$cv/$cg|eff=$eff" >> "$TSV"
      echo "  [$n $arm] PASS gen=$gen ctrl=$cv eff=$eff"
    else
      d=$(diff <(printf '%s\n' "$php_norm") <(printf '%s\n' "$aot_norm") | head -6 | tr '\n' '~' | tr '|' '/' | head -c 300)
      echo "$n|$arm|DIFF|gen=$gen|ctrl=$cv/$cg|eff=$eff|d=$d" >> "$TSV"
      echo "  [$n $arm] DIFF gen=$gen ctrl=$cv eff=$eff"
      echo "      d=$d"
    fi
  done
done

{
  echo "ROUND_OUT_DONE total=$total compile_fail=$cfail php_exit=$phpexit src_missing=$nosrc rows=$(awk -F'|' '$2=="r2nc" || $2=="r3nc" {n++} END {print n+0}' "$TSV")"
  for arm in r2nc r3nc; do
    cnt() { awk -F'|' -v A="$arm" -v V="$1" '$2==A && $3==V {n++} END {print n+0}' "$TSV"; }
    printf "arm %s: PASS=%d DIFF=%d RUNTIME_FAIL=%d TIMEOUT_10S=%d COMPILE_FAIL=%d\n" "$arm" \
      "$(cnt PASS)" "$(cnt DIFF)" "$(cnt RUNTIME_FAIL)" "$(cnt TIMEOUT_10S)" "$(cnt COMPILE_FAIL)"
    printf "  eff %s: EFFECTIVE=%d NO_EFFECT=%d NO_TEMP=%d CFAIL_NO_TEMP=%d\n" "$arm" \
      "$(awk -F'|' -v A="$arm" '$2==A && $6=="eff=EFFECTIVE" {n++} END {print n+0}' "$TSV")" \
      "$(awk -F'|' -v A="$arm" '$2==A && $6=="eff=NO_EFFECT" {n++} END {print n+0}' "$TSV")" \
      "$(awk -F'|' -v A="$arm" '$2==A && $6=="eff=NO_TEMP" {n++} END {print n+0}' "$TSV")" \
      "$(awk -F'|' -v A="$arm" '$2==A && $6=="eff=CFAIL_NO_TEMP" {n++} END {print n+0}' "$TSV")"
    # 控制面（#101 同轮非 nc 臂）判定分布，逐臂自证分母
    printf "  ctrl %s: %s\n" "$arm" "$(awk -F'|' -v A="$arm" '$2==A && $5 ~ /^ctrl=/ {sub(/^ctrl=/,"",$5); split($5,a,"/"); c[a[1]]++} END {for (k in c) printf "%s=%d ", k, c[k]; print ""}' "$TSV")"
    # 「控制面非绿 ⇒ 本臂 PASS」= 关 cfg_cleanup 新转绿（#100 的 LAYER2_GREEN_BY_CLOSING_CFG 轮 2/3 版）
    printf "  GREEN_BY_CLOSING_CFG %s = %s\n" "$arm" "$(awk -F'|' -v A="$arm" '
      $2==A && $5 ~ /^ctrl=/ { sub(/^ctrl=/,"",$5); split($5,a,"/"); if (a[1]!="PASS" && a[1]!="" && a[1]!="NOROW") red[$1]=1 }
      $2==A && $3=="PASS" && red[$1] { n++ }
      END { print n+0 }' "$TSV")"
    printf "  STILL_RED_AFTER_CLOSING %s = %s\n" "$arm" "$(awk -F'|' -v A="$arm" '$2==A && ($3=="DIFF" || $3=="RUNTIME_FAIL" || $3=="TIMEOUT_10S") {printf "%s ", $1} END {print ""}' "$TSV")"
    printf "  NEWLY_RED_vs_CTRL %s = %s\n" "$arm" "$(awk -F'|' -v A="$arm" '
      $2==A && $5 ~ /^ctrl=/ {
        sub(/^ctrl=/, "", $5); split($5, a, "/"); c = a[1]
        if (c == "PASS" && $3 != "PASS") printf "%s(%s) ", $1, $3
      }
      END { print "" }' "$TSV")"
    printf "  COMPILE_FAIL_NAMES %s = %s\n" "$arm" "$(awk -F'|' -v A="$arm" '$2==A && $3=="COMPILE_FAIL" {printf "%s ", $1} END {print ""}' "$TSV")"
  done
} | tee -a "$TSV"

echo "ELAPSED=$(( $(date +%s) - START_TS ))s" | tee -a "$TSV"
