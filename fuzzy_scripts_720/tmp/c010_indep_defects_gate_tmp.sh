#!/usr/bin/env bash
# 永久侧门 D8 = AOT-CODEGEN-010 §8 家族门（2026-10-07，任务 #122 归因轮新立；修门 ① = 补 <?php 开标签
#   + 新增 BAD_PROBE_PHP_EMPTY 预检：纯 HTML 文件 php -l 照样通过 ⇒ lint 抓不到漏开标签，必须比对执行输出非空。
#   首跑（ELAPSED=138s）因此全表作废禁止引用。）
#   用途：登记 7 枚「与关键字大小写无关」的默认档独立缺陷的当前红面，作为未来各修复批的验收面
#   （修复哪枚，哪枚转绿；未修复的必须保持红 ⇒ 防静默回归 + 防修复批互相遮蔽）。
#   逐枚到行归因（2026-10-07 实测，详见工单 §8）：
#     d1  and/or/xor 低优先级逻辑符被赋值 RHS 吞掉   = parser.zig:1994(parseAssignment RHS parseExpression(0))
#                                                      + :2680/:2683(循环内赋值臂用 precedence 而非 next_p-1)
#     d2  var 属性声明编译失败                        = parser.zig 成员修饰符循环(~:905-911/:486-494)缺 .k_var 臂
#     d3  反向 goto 环状块图发射丢失                  = ir_generator.zig:737-738/:3879-3938 IR 支持且前向 goto 实证有效，
#                                                      反向(d3a)生成码丢标签块体+echo 落入 else ⇒ 发射/线性化侧(待子轮到行)
#     d5  __NAMESPACE__ 硬编码空串                    = ir_generator.zig:5482-5484 internString("")，解析器 current_namespace 未入 IR
#     d6  函数名大小写不敏感解析缺失                  = ir_generator.zig:6262 用户函数 eql 精确匹配 + native_linker 内建表精确键
#     d7  内建 go 条目遮蔽用户函数                    = native_linker.zig:4273("go"→php_go_builtin) + :1676(@"go" 符号)，
#                                                      用户 registerUserFunctionWithLocation("go",…) 后调用仍被解析为 php_go_builtin
# 判读口径：等值 = 归一化 stdout+stderr 逐字节（剥 PHP 前缀/in file:line 尾/栈跟踪）；
#   编译失败判据取「产物不可执行」（规则 21）；每臂 php -l 预检 + PHP 输出非空预检（门 H 坏探针教训⑨强化版）；
#   全命令带 timeout；产物名 aot_compile_*。
set -u
cd "$(dirname "$0")/../.." || exit 1
BIN="zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
OUT="fuzzy_scripts_720/tmp/c010_indep_defects_tmp.tsv"
T=$(mktemp -d /tmp/c010d8.XXXXXX)
trap 'rm -rf "$T"' EXIT
START=$(date +%s)

norm() {
  sed -E -e 's/[[:space:]]*$//' \
         -e 's|/[^[:space:]:]*\.php:[0-9]+|FILE:LINE|g' \
         -e 's| in [^ ]*\.php on line [0-9]+| in FILE:LINE|g' \
         -e '/^Stack trace:/,$d' \
         -e '/^$/d'
}

body_for() {
  case "$1" in
    # d1 and/or/xor 赋值 RHS 优先级（d1c/d1d 为括号强制分组控制臂，两侧应同值）
    d1a) printf '<?php\n$r = (1 < 2) and (3 < 2); echo $r ? "y" : "n";\n' ;;
    d1b) printf '<?php\n$r = 1 and 0; echo $r ? "y" : "n";\n' ;;
    d1c) printf '<?php\necho ((1 < 2) and (3 < 2)) ? "y" : "n";\n' ;;
    d1d) printf '<?php\n$r = ((1 < 2) and (3 < 2)); echo $r ? "y" : "n";\n' ;;
    # d2 var 属性声明
    d2a) printf '<?php\nclass KwhV2 { var $p = 3; }\necho (new KwhV2())->p;\n' ;;
    # d3 goto（d3a 反向循环 = 红；d3b/d3h 标签健康控制臂）
    d3a) printf '<?php\n$i = 0; KWH_L3: $i++; if ($i < 2) { goto KWH_L3; }\necho $i;\n' ;;
    d3b) printf '<?php\nKWH_L3b: echo 1;\n' ;;
    d3h) printf '<?php\necho 1; KWH_L3h: echo 2; echo 3;\n' ;;
    # d5 __NAMESPACE__（d5b 无命名空间控制臂，两侧 0）
    d5a) printf '<?php\nnamespace KwhNsD5;\necho strlen(__NAMESPACE__);\n' ;;
    d5b) printf '<?php\necho strlen(__NAMESPACE__);\n' ;;
    # d6 函数名大小写（d6a 内建 Unset；d6b 跨大小写用户函数；d7b 外族词 from 控制臂）
    d6a) printf '<?php\n$a = [1, 2]; Unset($a[0]); echo count($a);\n' ;;
    d6b) printf '<?php\nfunction Get(){ return 11; }\necho get();\n' ;;
    d7a) printf '<?php\nfunction go(){ return 101; }\necho go();\n' ;;
    d7b) printf '<?php\nfunction from(){ return 102; }\necho from();\n' ;;
  esac
}

classify() { # $1=php_norm $2=aot_norm
  if [ "$1" = "$2" ]; then echo "GUARD_SAME"; else echo "DEFECT_RED"; fi
}

: > "$OUT"
defect_red=0; guard_same=0; compile_fail=0; bad_probe=0
for s in d1a d1b d1c d1d d2a d3a d3b d3h d5a d5b d6a d6b d7a d7b; do
  f="$T/${s}.php"
  body_for "$s" > "$f"
  if ! timeout 10 "$PHP" -l "$f" >/dev/null 2>&1; then
    printf '%s\tBAD_PROBE_PHP_LINT\n' "$s" >> "$OUT"; bad_probe=$((bad_probe+1)); continue
  fi
  ph=$(timeout 10 "$PHP" "$f" 2>&1 | norm)
  # 门 H 教训⑨强化：php -l 对「漏 <?php 的纯 HTML 文件」照样通过 ⇒ 必须再验执行输出非空
  if [ -z "$ph" ]; then
    printf '%s\tBAD_PROBE_PHP_EMPTY\n' "$s" >> "$OUT"; bad_probe=$((bad_probe+1)); continue
  fi
  timeout 120 "$BIN" --compile --no-debug-info --output="$T/aot_compile_${s}_tmp" "$f" >"$T/${s}.clog" 2>&1
  if [ -x "$T/aot_compile_${s}_tmp" ]; then
    ao=$(timeout 10 "$T/aot_compile_${s}_tmp" 2>&1 | norm)
    cls=$(classify "$ph" "$ao")
    printf '%s\t%s\tPHP[%s]\tAOT[%s]\n' "$s" "$cls" "$ph" "$ao" >> "$OUT"
    [ "$cls" = "DEFECT_RED" ] && defect_red=$((defect_red+1)) || guard_same=$((guard_same+1))
  else
    printf '%s\tCOMPILE_FAIL\tPHP[%s]\tAOT[no product]\n' "$s" "$ph" >> "$OUT"
    compile_fail=$((compile_fail+1))
  fi
  rm -f "$T/aot_compile_${s}_tmp"
done
residue=$(ls -d .zigphp_aot_build_* aot_compile_* 2>/dev/null | wc -l | tr -d ' ')
END=$(date +%s)
echo "C010D8_DONE shapes=14 defect_red=$defect_red guard_same=$guard_same compile_fail=$compile_fail bad_probe=$bad_probe repo_build_residue=$residue SMOKE_ONLY=0 ELAPSED=$((END-START))s" >> "$OUT"
tail -1 "$OUT"
