#!/bin/bash
# AOT-OPT-001 §5.6 残红五形逐枚定机制（任务 #99，只读、零源码改动、零插桩、非门控）
#
# 背景：#97 金丝雀面扫给出 C1（phi 同源异值）签名面 9/19，#98 旗标因果面给出 10/19。
#       仍错值 5 枚 = f117 f161（组 I：仅 --aot-enable-pass=licm 即红，默认迭代 3 轮 optimizer.zig:103）
#                   + f051 f061 f135（组 II：licm 于 3 轮绿，须 licm×max_iterations=5 才红）。
#       其中 f117/f161 的 C1 delta>0 却在 #98 关掉 cfg_cleanup 后**仍红** ⇒ C1 只标「链在场」，不标「症状归属」。
#
# 本脚本用四臂 IR-only 通道（全部 --no-link，秒级；单臂实测 0.01–0.02 s）在 5 枚形上量化九枚签名 + 一枚自证分母：
#   C1   phi 同源异值枚数（OPT-001 §5.3 既有金丝雀的 IR 侧复算）
#   C4   pre-header 指令的操作数寄存器定义在**该循环内** ⇒ 提升后每轮取值冻结（陈旧提升）
#   C4h  C4 的提升限定版：只算本臂相对 base 臂**新落入** pre-header 的指令 ⇒ 排除基线固有噪声
#   C4b  pre-header 内有读指令，同循环内含 array.set/property.set/任意调用，但循环内**无 .store**
#        ⇒ hasStoreInLoop(optimizer.zig:1078-1088) 只认 .store/.call/.call_indirect 的盲区
#   C4bh C4b 的提升限定版，口径同 C4h
#   C7   新落入 pre-header 的指令中，其在 base 臂的定义块**属于同一循环体但不支配该循环全部 latch**
#        ⇒ 提升前只在部分迭代执行、提升后无条件执行（LICM 无控制流敏感度）。
#        落盘为 C7=命中/分母，分母自证 hm（id 在 base 可查）与 hl（base 同名循环头存在）：
#        hm、hl 若等于 H ⇒ 跨臂匹配有效，C7=0 才可解读为「无臂内提升」；否则该读数作废
#   H    相对 base 臂新落入 pre-header 的指令枚数（双臂按寄存器 id 联表）⇒ **不是金丝雀，是 C7 的自证分母**
#   C2   生成码侧「声明但无正常流赋值」寄存器枚数 ⇒ **严格版**：异常清理块的
#        `reg_N.release(…); reg_N = initNull();`（≥8 空格缩进）不算赋值 ⇒ 与 §5.3 归档的**第 1 代全文**宽松 C2
#        **数值不可直接比较**（宽松版会把每个停初值寄存器洗白；归档读数见 `opt001_canary_sweep_tmp.tsv.r1-global-c2`）
#        **口径归一（本轮更正）**：按**顶层功能区间**归一 —— `reg_N` 编号在每个 PHP 功能内独立复用，
#        全文口径会让「另一功能里有赋值」把本站点的零写入洗白
#        （实测 f117 licm 臂 `InvertedIndex::searchTFIDF`/`searchBM25` 的 coalesce 交汇寄存器
#         `reg_39` 两站点均无臂拷贝，旧全文口径 C6 仍报 0）
#        ⇒ #99 起 §5.3/§5.4 的面扫已改调**本分析器同一函数**，故刷新后的 §5.3/§5.4 读数与本表同源可比
#   C6   本功能区间内仍带 `// PHI: reg_N (handled in terminator)` 标记却无正常流赋值 ⇒ §5.2 R5 的直接落点
#   C9   `// PHI: reg_N` 标记紧邻包裹它的 `if (…) {…} else {…}` 里**一臂为空臂、另一臂有赋值**
#        ⇒ 该臂拷贝从未发射，交汇寄存器在该路径保持上一轮值／声明初值。
#        这是 R3 的「**异块改写支**」（记作 R3′：入边块被改写为不同名的前驱块）在发射侧的落点 ——
#        因入边块名不同，IR 侧不出现「同源异值 phi」⇒ **C1/C6 全盲**。
#        ⚠ **禁止取绝对值**：base（绿）臂实测已有底噪（f161 base C9=1，`reg_56`）⇒ 只能取双臂 delta；
#        旧「残红五形中唯一可判的区分签名」措辞已由本轮底噪实测作废。
# 四臂：base(默认，LICM 关) / licm(默认+LICM，max_iterations 默认 3) /
#       li5(默认+LICM+迭代 5) / li5nc(li5 再关 cfg_cleanup ⇒ 分离「删臂折条件」与「提升本身」)
# 控制组判据（本轮实测后修订，两处为**自我更正**）：
#   · IR 侧 C1/C4h/C7 在 base 臂必须为 0（该臂输出等值 PHP 真值）；否则金丝雀假阳性。
#     ⚠ **C4bh 不在此列（原写法为结构错判）**：base 臂调分析器时**不带 `--base`** ⇒ 无对照集，
#     落盘的 `C4b/C4bh` 两列必然同值（实测 6/6、5/5、1/1、11/11、19/19）⇒ base 臂的 C4bh
#     是「全量」而非「新落入」，**禁止**当假阳性判据；只有非 base 臂的 C4h/C4bh 才是限定版读数。
#   · 生成码侧严格 C2/C6 **不可取绝对值**：base 臂实测已有底噪（区间口径第 2 代读数
#     f117=23／f161=30／f051=5／f061=23／f135=40 枚「本功能内声明未赋值」寄存器；C6 底噪另有
#     f135 base=3）⇒ 只取双臂 delta，与 §5.3「C2 有底噪，禁止单用」同源。
#     ⚠ 本行原写「f117=3／f161=2／f051=2／f061=4／f135=20」是**第 1 代全文口径**的读数，已按实测替换。
# 铁律：禁止删除任何 .php 源；产物名一律 aot_compile_*；每臂 IR 用完即删。
cd /Users/wangjianjun/products/parser || exit 1

BIN="zig-out/bin/php-interpreter"
PASS_DIR="fuzzy_scripts_720/pass"
WORK="/tmp/opt001_resid_work"
TSV="fuzzy_scripts_720/tmp/opt001_resid_hoist_tmp.tsv"
PY="fuzzy_scripts_720/tmp/opt001_ir_stale_hoist_tmp.py"
EV="fuzzy_scripts_720/tmp/opt001_resid_evidence_tmp.txt"

SHAPES="f117_search_engine_inverted_tfidf_bm25 f161_json_xml_csv_parsing f051_validator_rule_chain_batch f061_graph_dijkstra_bellmanford_floyd f135_math_number_theory_crt_miller_rabin"

rm -rf "$WORK"; mkdir -p "$WORK"
> "$TSV"
> "$EV"
echo "# opt001 §5.6 residual-shape mechanism sweep $(date '+%Y-%m-%d %H:%M:%S') bin=$(md5 -q "$BIN") optimizer=$(md5 -q src/aot/optimizer.zig) flags=--compile --no-debug-info --no-link --emit-ir" >> "$TSV"

for n in $SHAPES; do
  src="$PASS_DIR/$n.php"
  case "$n" in
    f117*|f161*) red_arm="licm" ;;   # 组 I：默认档 + LICM（3 轮）即红
    *)           red_arm="li5" ;;    # 组 II：须 LICM×迭代 5 才红
  esac
  [ -f "$src" ] || { echo "$n|SKIP|NO_SRC" >> "$TSV"; continue; }
  for arm in base licm li5 li5nc; do
    case "$arm" in
      base)   fl="" ;;
      licm)   fl="--aot-enable-pass=licm" ;;
      li5)    fl="--aot-enable-pass=licm --aot-max-iterations=5" ;;
      li5nc)  fl="--aot-enable-pass=licm --aot-max-iterations=5 --aot-disable-pass=cfg-cleanup" ;;
    esac
    ZIGPHP_AOT_KEEP_TEMP=0 timeout 300 $BIN --compile --no-debug-info --no-link $fl \
      --output="$WORK/aot_compile_${n}_${arm}" \
      --emit-ir="$WORK/ir_${n}_${arm}.txt" \
      --dump-zig-path="$WORK/zig_${n}_${arm}.txt" \
      "$src" >"$WORK/${arm}.cerr" 2>&1
    rc=$?
    if [ $rc -ne 0 ] || [ ! -f "$WORK/ir_${n}_${arm}.txt" ] || [ ! -f "$WORK/zig_${n}_${arm}.txt" ]; then
      echo "$n|$arm|COMPILE_FAIL|rc=$rc" >> "$TSV"
      echo "[$n $arm] COMPILE_FAIL rc=$rc"
      continue
    fi
    ir_lines=$(wc -l < "$WORK/ir_${n}_${arm}.txt" | tr -d ' ')
    zig_lines=$(wc -l < "$WORK/zig_${n}_${arm}.txt" | tr -d ' ')
    if [ "$arm" = "base" ]; then
        IFS=, read -r c1 c4 c4h c4b c4bh c7 h hm hl c2 c6 c9 < <(python3 "$PY" "$WORK/ir_${n}_base.txt" --zig "$WORK/zig_${n}_base.txt" --csv)
        echo "$n|$arm|C1=$c1|C2=$c2|C6=$c6|C9=$c9|C4=$c4/$c4h|C4b=$c4b/$c4bh|C7=-/-|H=-|ir=$ir_lines|zig=$zig_lines" >> "$TSV"
    else
        IFS=, read -r c1 c4 c4h c4b c4bh c7 h hm hl c2 c6 c9 < <(python3 "$PY" "$WORK/ir_${n}_${arm}.txt" --base "$WORK/ir_${n}_base.txt" --zig "$WORK/zig_${n}_${arm}.txt" --csv)
        echo "$n|$arm|C1=$c1|C2=$c2|C6=$c6|C9=$c9|C4=$c4/$c4h|C4b=$c4b/$c4bh|C7=$c7/$h(hm=$hm,hl=$hl)|ir=$ir_lines|zig=$zig_lines" >> "$TSV"
    fi
    echo "[$n $arm] C1=$c1 C2=$c2 C6=$c6 C9=$c9 C4=$c4/$c4h C4b=$c4b/$c4bh C7=$c7/$h ir=$ir_lines zig=$zig_lines"
    if [ "$arm" = "$red_arm" ]; then
      {
        echo "===== $n arm=$arm（该形最小红配置） ====="
        python3 "$PY" "$WORK/ir_${n}_${arm}.txt" --base "$WORK/ir_${n}_base.txt" --zig "$WORK/zig_${n}_${arm}.txt" | head -40
      } >> "$EV"
    fi
    rm -f "$WORK/aot_compile_${n}_${arm}" "$WORK/aot_compile_${n}_${arm}.zig"
    [ "$arm" = "base" ] || rm -f "$WORK/ir_${n}_${arm}.txt" "$WORK/zig_${n}_${arm}.txt"
  done
  rm -f "$WORK/ir_${n}_base.txt" "$WORK/zig_${n}_base.txt"
done

echo "RESID_SWEEP_DONE shapes=$(echo $SHAPES | wc -w | tr -d ' ')" >> "$TSV"
echo "RESID_SWEEP_DONE"
