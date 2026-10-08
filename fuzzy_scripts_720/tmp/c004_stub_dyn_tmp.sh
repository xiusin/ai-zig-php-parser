#!/bin/bash
# AOT-REF-004 §7.5：动态入口 → 含引用形参的类方法（方法表桩路径）触发面实测。零源码改动、只读生成码。
# 五形 × {PHP 真值, AOT ReleaseSmall 默认档, AOT -ODebug 崩点}，一次编译 + 5×2 运行 + 1 次 Debug 重建。
cd /Users/wangjianjun/products/parser || exit 1
BIN="zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
PROBE="fuzzy_scripts_720/tmp/t004_stub_dynentry_tmp.php"
OUT="fuzzy_scripts_720/tmp/c004_stub_dyn_tmp.tsv"
ERR="/tmp/c004_stub_dyn.err"
DBGD="/tmp/c004_stub_dbg"
PRODUCT="/tmp/aot_compile_t004_stub_dynentry_tmp"
SHAPES="ctrl_static cuf_string cuf_array varfunc_str inst_dyn"
start=$(date +%s)

{ md5 -q "$BIN" | sed 's/^/# php_interpreter_md5=/'
  md5 -q src/aot/native_linker.zig | sed 's/^/# native_linker_md5=/'
  md5 -q src/aot/runtime_lib_template.zig | sed 's/^/# runtime_lib_template_md5=/'
  md5 -q "$PROBE" | sed 's/^/# probe_md5=/'
  echo "# columns: shape|php|aot_rc|aot_stdout|debug_frame"
} > "$OUT"

t0=$(date +%s)
ZIGPHP_AOT_KEEP_TEMP=1 timeout 600 "$BIN" --compile --no-debug-info --output="$PRODUCT" "$PROBE" 2>"$ERR" >/dev/null
crc=$?
tmpd=$(awk '/preserved/ {print $NF; exit}' "$ERR")
echo "COMPILE rc=$crc elapsed=$(( $(date +%s) - t0 ))s tmpdir=$(basename "${tmpd:-none}")" >> "$OUT"
if [ $crc -ne 0 ] || [ ! -d "$tmpd" ] || [ ! -f "$tmpd/main.zig" ]; then
  echo "FATAL no preserved dir" >> "$OUT"
  echo "STUB_DONE" >> "$OUT"
  exit 1
fi

# 静态面：回落句与装填句在生成码里的位置（分类器读数的等价锚）
{ echo "# generated_face"
  grep -c 'else &null_val' "$tmpd/main.zig" | sed 's/^/# fallback_lines=/'
  grep -c 'make_ref(' "$tmpd/main.zig" | sed 's/^/# make_ref_lines=/'
  grep -c 'initRef(' "$tmpd/main.zig" | sed 's/^/# initRef_lines=/'
  grep -n 'else &null_val' "$tmpd/main.zig" | sed 's/^/# FB /'
} >> "$OUT"

for s in $SHAPES; do
  php_out=$(timeout 10 "$PHP" "$PROBE" "$s" 2>/dev/null | tr '\n' '|')
  aot_out=$(timeout 10 "$PRODUCT" "$s" 2>&1); rc=$?
  echo "$s|php=${php_out}|aot_rc=$rc|aot=$(echo "$aot_out" | head -1)" >> "$OUT"
done

# Debug 重建：拿 Zig 自带段错误处理器的带行号栈（ReleaseFast 只有裸 rc=139）
rm -rf "$DBGD"
cp -r "$tmpd" "$DBGD"
t1=$(date +%s)
(cd "$DBGD" && timeout 300 zig build-exe main.zig -femit-bin="$DBGD/aot_dbg" -ODebug -target aarch64-macos \
  -L/opt/homebrew/lib -L/usr/local/lib -lpcre2-8 -lc 2>/dev/null >/dev/null)
drc=$?
echo "DEBUG_BUILD rc=$drc elapsed=$(( $(date +%s) - t1 ))s" >> "$OUT"
if [ $drc -eq 0 ]; then
  for s in $SHAPES; do
    frames=$(cd "$DBGD" && timeout 20 ./aot_dbg "$s" 2>&1 | grep -E '\.zig:[0-9]+:[0-9]+' | head -3 | sed 's|/private/tmp/c004_stub_dbg/||' | tr '\n' ';')
    echo "$s|debug_frames=${frames}" >> "$OUT"
  done
fi

# 清理：保留目录、两份产物、Debug 副本、临时 stderr（禁止删 .php 源）
rm -rf "$tmpd" "$DBGD" "$PRODUCT" "$ERR"
echo "ELAPSED=$(( $(date +%s) - start ))s" >> "$OUT"
echo "STUB_DONE" >> "$OUT"
