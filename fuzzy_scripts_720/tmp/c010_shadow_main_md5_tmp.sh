#!/usr/bin/env bash
# R-2 影子实测（工单 AOT-CODEGEN-010 §5 R-2 / 交接 §9 P0：落地前影子，判定冻结基线是否漂移）
#   68 语料逐形用「旧二进制（修复前 1f15e4ce）」与「新二进制」各 AOT 编译一次，
#   从 ZIGPHP_AOT_KEEP_TEMP 目录取生成码 main.zig 逐形 md5 对照。
#   语料关键字位混合大小写命中 = 0（工单 §4 穷举实测）⇒ 预期 diff=0。
#   纪律：仓库根执行；全命令带 timeout；产物名 aot_compile_*；KEEP_TEMP 目录抽取后即删。
set -u
cd "$(dirname "$0")/../.." || exit 1
OLD=/tmp/c010_prefix_backup/php-interpreter.prefix
NEW=zig-out/bin/php-interpreter
OUT=fuzzy_scripts_720/tmp/c010_shadow_main_md5_tmp.tsv
: > "$OUT"
T=$(mktemp -d /tmp/c010shadow.XXXXXX)
START=$(date +%s)

for f in fuzzy_scripts_720/pass/*.php; do
  b=$(basename "$f" .php)
  for side in old new; do
    bin="$OLD"
    [ "$side" = "new" ] && bin="$NEW"
    log="$T/${b}_${side}.log"
    timeout 120 env ZIGPHP_AOT_KEEP_TEMP=1 "$bin" --compile --no-debug-info --output="$T/aot_compile_shadow_${b}_${side}" "$f" >"$log" 2>&1
    bin_path="$T/aot_compile_shadow_${b}_${side}"
    if [ -x "$bin_path" ]; then
      tdir=$(grep -o 'temp dir preserved: [^ ]*' "$log" | head -1 | sed 's/.*preserved: //')
      if [ -n "${tdir:-}" ] && [ -f "$tdir/main.zig" ]; then
        md5r=$(md5 -q "$tdir/main.zig")
      else
        md5r="NO_MAINDIR"
      fi
    else
      md5r="NOT_EXECUTABLE"
    fi
    printf '%s\t%s\t%s\n' "$b" "$side" "$md5r" >>"$OUT"
    [ -n "${tdir:-}" ] && rm -rf "$tdir"
    rm -f "$bin_path" "$log"
  done
done
rm -rf "$T"
END=$(date +%s)
awk -F'\t' '
  $2=="old" { old[$1]=$3 }
  $2=="new" { new[$1]=$3 }
  END {
    same=0; diff=0; miss=0; invalid=0
    for (b in old) {
      if (!(b in new)) { miss++; continue }
      # 假等值防护：任一侧为「无产物/无临时目录」哨兵值时不得计入 same
      # （磁盘满等环境故障会让两侧同时写不出产物 ⇒ NOT_EXECUTABLE==NOT_EXECUTABLE 曾被误记为 same）
      if (old[b]=="NOT_EXECUTABLE" || old[b]=="NO_MAINDIR" || new[b]=="NOT_EXECUTABLE" || new[b]=="NO_MAINDIR") { invalid++; continue }
      if (old[b]==new[b]) same++; else diff++
    }
    # 注意：ELAPSED 由外层 sed 回填（awk 内不可引用 END 关键字作变量）
    printf "C010_SHADOW_DONE total=%d same=%d diff=%d miss=%d invalid=%d ELAPSED=NA\n", (same+diff+miss+invalid), same, diff, miss, invalid
  }' "$OUT" | sed "s/ELAPSED=NA/ELAPSED=$((END-START))s/" >>"$OUT"
tail -1 "$OUT"
