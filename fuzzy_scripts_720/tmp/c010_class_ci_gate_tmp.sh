#!/usr/bin/env bash
# 永久侧门 M = AOT-CODEGEN-012 类名族 CI 门（2026-10-11 立单取证轮新立）
#   8 形：6 红（new/instanceof/静态调用/class_exists/::常量 跨大小写）+ 2 拼写保真守卫
#   （c6 ::class、c8 get_class 必须恒返回声明拼写；c7 extends 既有绿为第三守卫）。
#   判读：R-1/R-2 落地后 6 形转绿、c6/c8 拼写逐字节不变。
#   纪律：仓库根；全命令 timeout；产物 aot_compile_*；php -l 预检；PHP 输出非空预检（D8 教训⑨）。
set -u
cd "$(dirname "$0")/../.." || exit 1
BIN="zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
OUT="fuzzy_scripts_720/tmp/c010_class_ci_tmp.tsv"
T=$(mktemp -d /tmp/c010m.XXXXXX)
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
    c1) printf '<?php\nclass MyClass { public $v = 7; }\n$o = new myclass();\necho $o->v;\n' ;;
    c2) printf '<?php\nclass MyClass {}\n$o = new MyClass();\necho ($o instanceof myclass) ? "y" : "n";\n' ;;
    c3) printf '<?php\nclass MyClass { public static function SM(): int { return 5; } }\necho myclass::SM();\n' ;;
    c4) printf '<?php\nclass MyClass {}\necho class_exists("myclass") ? "y" : "n";\n' ;;
    c5) printf '<?php\nclass MyClass { const K = 3; }\necho myclass::K;\n' ;;
    c6) printf '<?php\nclass MyClass {}\necho myclass::class;\n' ;;
    c7) printf '<?php\nclass Base { public function f(): int { return 1; } }\nclass Child extends base { public function f(): int { return 2; } }\necho (new Child())->f();\n' ;;
    c8) printf '<?php\nclass MyClass { public $v = 7; }\necho get_class(new MyClass());\n' ;;
    # 重复声明族（R-129）：跨大小写/精确/接口/trait，PHP 均 Fatal redeclare
    c9) printf '<?php\nclass Foo {}\nclass foo {}\necho "both";\n' ;;
    c10) printf '<?php\nclass Dub { public $v = 1; }\nclass Dub { public $v = 2; }\necho "both";\n' ;;
    c11) printf '<?php\ninterface MyI2 {}\ninterface MyI2 {}\necho "i";\n' ;;
    c12) printf '<?php\ntrait T2 { public $p = 1; }\ntrait T2 { public $p = 2; }\necho "t";\n' ;;
    # 方法名族 + 别名/内省（R-131）
    c13) printf '<?php\nclass MC { public function Gm(): int { return 3; } }\necho (new MC())->Gm();\necho (new MC())->gm();\n' ;;
    c14) printf '<?php\nclass MyClass {}\n$o = new MyClass();\necho is_a($o, "myclass") ? "y" : "n";\necho is_a("MyClass", "myclass", true) ? "S" : "s";\n' ;;
    c15) printf '<?php\nclass Base { public function f(): int { return 1; } }\nclass Child extends Base {}\necho is_subclass_of("Child", "base") ? "y" : "n";\n' ;;
    c16) printf '<?php\nclass MyClass { public function gm(): int { return 3; } }\necho method_exists("MyClass", "gm") ? "y" : "n";\necho method_exists("myclass", "gm") ? "Y" : "N";\necho method_exists(new MyClass(), "gm") ? "o" : "x";\n' ;;
    c17) printf '<?php\nclass Orig { public $v = 7; }\nclass_alias("Orig", "Alias");\n$o = new Alias();\necho $o->v;\necho class_alias("Nope", "X2") ? "bad" : "ok";\n' ;;
    # 属性诊断族（R-132）
    p1) printf '<?php\nclass PC { public $Pr = 5; }\n$o = new PC();\necho $o->pr;\n' ;;
    p2) printf '<?php\nclass PC { public $Pr = 5; }\n$o = new PC();\n$o->pr = 9;\necho $o->Pr;\n' ;;
  esac
}

: > "$OUT"
red=0; green=0; compile_fail=0; bad_probe=0
for s in c1 c2 c3 c4 c5 c6 c7 c8 c9 c10 c11 c12 c13 c14 c15 c16 c17 p1 p2; do
  f="$T/${s}.php"
  body_for "$s" > "$f"
  if ! timeout 10 "$PHP" -l "$f" >/dev/null 2>&1; then
    printf '%s\tBAD_PROBE_PHP_LINT\n' "$s" >>"$OUT"; bad_probe=$((bad_probe+1)); continue
  fi
  ph=$(timeout 10 "$PHP" "$f" 2>&1 | norm)
  if [ -z "$ph" ]; then
    printf '%s\tBAD_PROBE_PHP_EMPTY\n' "$s" >>"$OUT"; bad_probe=$((bad_probe+1)); continue
  fi
  timeout 120 "$BIN" --compile --no-debug-info --output="$T/aot_compile_${s}_tmp" "$f" >"$T/${s}.clog" 2>&1
  if [ -x "$T/aot_compile_${s}_tmp" ]; then
    ao=$(timeout 10 "$T/aot_compile_${s}_tmp" 2>&1 | norm)
    if [ "$ph" = "$ao" ]; then cls="SAME"; else cls="DIFF"; fi
    printf '%s\t%s\tPHP[%s]\tAOT[%s]\n' "$s" "$cls" "$ph" "$ao" >>"$OUT"
    [ "$cls" = "SAME" ] && green=$((green+1)) || red=$((red+1))
  else
    printf '%s\tCOMPILE_FAIL\tPHP[%s]\tAOT[no product]\n' "$s" "$ph" >>"$OUT"
    compile_fail=$((compile_fail+1))
  fi
  rm -f "$T/aot_compile_${s}_tmp"
done
residue=$(ls -d .zigphp_aot_build_* aot_compile_* 2>/dev/null | wc -l | tr -d ' ')
END=$(date +%s)
echo "C010M_DONE shapes=19 red=$red green=$green compile_fail=$compile_fail bad_probe=$bad_probe repo_build_residue=$residue SMOKE_ONLY=0 ELAPSED=$((END-START))s" >>"$OUT"
tail -1 "$OUT"
