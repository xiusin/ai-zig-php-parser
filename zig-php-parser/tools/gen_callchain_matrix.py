import argparse
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Tuple


@dataclass(frozen=True)
class Step:
    title: str
    file_rel: str
    needle: str
    io: str
    side_effects: str
    perf: str
    alloc: str
    errors: str


def read_lines(path: Path) -> List[str]:
    return path.read_text(encoding="utf-8", errors="replace").splitlines()


def find_line_range(lines: List[str], needle: str, context: int = 3) -> Optional[Tuple[int, int]]:
    for idx, line in enumerate(lines, start=1):
        if needle in line:
            start = max(1, idx - context)
            end = min(len(lines), idx + context)
            return start, end
    return None


def make_link(repo_root: Path, file_rel: str, line_range: Optional[Tuple[int, int]]) -> str:
    abs_path = (repo_root / file_rel).resolve()
    if not line_range:
        return f"[{Path(file_rel).name}](file://{abs_path})"
    s, e = line_range
    return f"[{Path(file_rel).name}:L{s}-L{e}](file://{abs_path}#L{s}-L{e})"


def render_markdown(repo_root: Path, steps: List[Step]) -> str:
    rows: List[str] = []
    rows.append("# Milestone 1：主链路调用链矩阵（自动生成）")
    rows.append("")
    rows.append("| 功能 | 实现位置 | 调用点 | 输入/输出契约 | 副作用 | 性能热点 | 分配次数 | 异常路径 |")
    rows.append("|---|---|---|---|---|---|---|---|")
    for s in steps:
        file_path = repo_root / s.file_rel
        lines = read_lines(file_path)
        lr = find_line_range(lines, s.needle)
        link = make_link(repo_root, s.file_rel, lr)
        rows.append(
            "| "
            + " | ".join(
                [
                    s.title.replace("|", "\\|"),
                    link,
                    s.needle.replace("|", "\\|"),
                    s.io.replace("|", "\\|"),
                    s.side_effects.replace("|", "\\|"),
                    s.perf.replace("|", "\\|"),
                    s.alloc.replace("|", "\\|"),
                    s.errors.replace("|", "\\|"),
                ]
            )
            + " |"
        )
    rows.append("")
    rows.append("## 说明")
    rows.append("- 本文档仅覆盖 Milestone1 需要的“端到端主链路 + 分发点”，不等价于全量业务逻辑矩阵。")
    rows.append("- Tree/Bytecode/Fast 的 AST tag 覆盖详见 artifacts/diff_matrix.xlsx。")
    return "\n".join(rows)


def main() -> int:
    repo_root = Path(__file__).resolve().parents[1]
    p = argparse.ArgumentParser()
    p.add_argument("--repo", default=str(repo_root))
    p.add_argument("--out", default=str(repo_root / "docs" / "milestone1" / "callchain_matrix.md"))
    args = p.parse_args()

    root = Path(args.repo)
    steps: List[Step] = [
        Step(
            title="CLI 入口与模式路由",
            file_rel="src/main.zig",
            needle="if (compile_mode) {",
            io="argv → (compile|run) 分支",
            side_effects="读取配置/文件；写 stdout/stderr",
            perf="I/O + 解析/编译为主",
            alloc="GPA+Arena（按源码读取大小分配）",
            errors="参数解析/文件读失败/parse 失败/compile 失败",
        ),
        Step(
            title="Parser：源码→AST 根节点",
            file_rel="src/compiler/parser.zig",
            needle="pub fn parse(self: *Parser) !ast.Node.Index {",
            io="php_code → ast.Node.Index(root)",
            side_effects="写入 PHPContext.nodes/string_pool/errors",
            perf="tokenize+parse（与源码长度相关）",
            alloc="Arena 分配 AST/字符串池",
            errors="语法错误/资源耗尽",
        ),
        Step(
            title="VM.run：执行模式分发",
            file_rel="src/runtime/vm.zig",
            needle="pub fn run(self: *VM, node: ast.Node.Index) !Value {",
            io="AST(root) → Value/错误",
            side_effects="可能输出；可能修改全局变量/对象堆；调度协程",
            perf="分发本身 O(1)，主体由模式决定",
            alloc="运行时对象/字符串/数组等按需分配",
            errors="异常抛出、Return 特例、运行期错误",
        ),
        Step(
            title="Tree：eval 主分发",
            file_rel="src/runtime/vm.zig",
            needle="fn eval(self: *VM, node: ast.Node.Index) anyerror!Value {",
            io="AST(node) → Value/错误",
            side_effects="echo 走 Value.print（debug.print）",
            perf="tag 分发 O(1)；递归深度敏感",
            alloc="表达式/容器构造按语义分配",
            errors="Unsupported tag/throwException/递归深度溢出",
        ),
        Step(
            title="Bytecode：AST→字节码→执行循环",
            file_rel="src/bytecode/generator.zig",
            needle="pub fn compile(self: *BytecodeGenerator, root_index: ast.Node.Index) !CompiledFunction {",
            io="AST(root) → CompiledFunction",
            side_effects="构建常量表/指令流/用户函数表",
            perf="遍历 AST O(n)+优化",
            alloc="指令/常量表/临时结构分配",
            errors="未覆盖 tag 可能静默跳过导致语义缺失",
        ),
        Step(
            title="BytecodeVM：dispatch-table 执行循环",
            file_rel="src/bytecode/vm.zig",
            needle="fn runOptimized(self: *BytecodeVM) !?Value {",
            io="bytecode → ?Value/错误",
            side_effects="写 output_buffer；修改堆/全局",
            perf="每条指令一次分发（热点：dispatch+内建调用）",
            alloc="按指令语义分配",
            errors="指令错误/异常抛出/栈帧错误",
        ),
        Step(
            title="FastVM：AST→FastCompiler→执行",
            file_rel="src/runtime/fast_compiler.zig",
            needle="fn compileNode(self: *FastCompiler, index: ast.Node.Index) anyerror!void {",
            io="AST(node) → fast bytecode",
            side_effects="生成 fast 指令流",
            perf="目标是减少分发与装箱",
            alloc="fast 指令/常量表",
            errors="未覆盖 tag 静默跳过风险高",
        ),
        Step(
            title="AOT：compile 总入口",
            file_rel="src/main.zig",
            needle="fn runAOTCompilation(allocator: std.mem.Allocator, options: aot.CompileOptions) !void {",
            io="php file → (ir/zig/exe)",
            side_effects="读取源码；生成/写出构建目录与产物；调用 zig 编译器",
            perf="parse+IR+优化+zig 编译",
            alloc="GPA 分配 AST/IR/字符串表等",
            errors="解析失败/IR 生成失败/链接失败",
        ),
        Step(
            title="AOT：IR 生成（语句分发）",
            file_rel="src/aot/ir_generator.zig",
            needle="fn generateStatement(self: *Self, index: Node.Index) anyerror!void {",
            io="AST stmt → IR",
            side_effects="写入 module/functions/blocks/symbol_table",
            perf="AST 遍历 O(n)",
            alloc="IR 指令/块/寄存器等分配",
            errors="anyerror 传播；部分 tag 回退表达式路径",
        ),
        Step(
            title="AOT：IR 生成（表达式分发）",
            file_rel="src/aot/ir_generator.zig",
            needle="pub fn generateExpression(self: *Self, index: Node.Index) anyerror!Register {",
            io="AST expr → Register",
            side_effects="追加 IR 指令",
            perf="表达式树遍历",
            alloc="IR 指令/常量池",
            errors="未覆盖 tag 回退 const_null（语义风险）",
        ),
        Step(
            title="AOT：NativeLinker（IR→Zig→zig build-exe）",
            file_rel="src/aot/native_linker.zig",
            needle="pub fn compileToExecutable(",
            io="IR module → 可执行文件",
            side_effects="写 zig 源码、拷贝 runtime、spawn zig 编译进程",
            perf="Zig 编译占主导",
            alloc="代码生成缓冲、临时字符串",
            errors="指令覆盖缺口/zig 编译失败/文件写入失败",
        ),
    ]

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(render_markdown(root, steps), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
