import argparse
import csv
import os
import re
import sys
import zipfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Set, Tuple


@dataclass(frozen=True)
class SourceRef:
    file_path: str
    anchor: str


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def find_block(text: str, start_idx: int, open_ch: str, close_ch: str) -> Tuple[int, int]:
    depth = 0
    i = start_idx
    while i < len(text) and text[i] != open_ch:
        i += 1
    if i >= len(text):
        raise ValueError("未找到块起始符号")
    start = i
    depth = 1
    i += 1
    while i < len(text) and depth > 0:
        ch = text[i]
        if ch == open_ch:
            depth += 1
        elif ch == close_ch:
            depth -= 1
        i += 1
    if depth != 0:
        raise ValueError("块括号不匹配")
    end = i
    return start, end


def extract_node_tags(ast_path: Path) -> List[str]:
    text = read_text(ast_path)
    m = re.search(r"pub\s+const\s+Tag\s*=\s*enum\s*\{", text)
    if not m:
        raise ValueError("未找到 Node.Tag 枚举")
    start, end = find_block(text, m.end() - 1, "{", "}")
    body = text[start + 1 : end - 1]
    tags: List[str] = []
    for raw in body.splitlines():
        line = raw.split("//", 1)[0].strip()
        if not line:
            continue
        if line.startswith("}"):
            break
        if line.startswith("pub "):
            continue
        if line.startswith("comptime"):
            continue
        if line.startswith("const "):
            continue
        if "=" in line:
            left = line.split("=", 1)[0].strip()
        else:
            left = line
        left = left.rstrip(",")
        if not left:
            continue
        if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", left):
            tags.append(left)
    if not tags:
        raise ValueError("未解析出任何 AST tag")
    return tags


def extract_union_enum_fields(text: str, union_decl_regex: str) -> List[str]:
    m = re.search(union_decl_regex, text)
    if not m:
        raise ValueError("未找到 union(enum) 定义")
    start, end = find_block(text, m.end() - 1, "{", "}")
    body = text[start + 1 : end - 1]
    fields: List[str] = []
    for raw in body.splitlines():
        line = raw.split("//", 1)[0].strip()
        if not line:
            continue
        if line.startswith("}"):
            break
        if ":" not in line:
            continue
        name = line.split(":", 1)[0].strip().rstrip(",")
        if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name):
            fields.append(name)
    if not fields:
        raise ValueError("未解析出任何 union(enum) 字段")
    return fields


def find_function_region(text: str, fn_name: str) -> Tuple[int, int]:
    m = re.search(rf"(pub\s+)?fn\s+{re.escape(fn_name)}\s*\(", text)
    if not m:
        raise ValueError(f"未找到函数: {fn_name}")
    start = m.start()
    brace_idx = text.find("{", m.end())
    if brace_idx == -1:
        raise ValueError(f"未找到函数体起始: {fn_name}")
    b0, b1 = find_block(text, brace_idx, "{", "}")
    return start, b1


def extract_switch_block(text: str, region: Tuple[int, int], switch_hint: str) -> str:
    r0, r1 = region
    sub = text[r0:r1]
    hint_idx = sub.find(switch_hint)
    if hint_idx == -1:
        raise ValueError(f"未在函数区域中找到 switch hint: {switch_hint}")
    switch_idx = sub.find("switch", hint_idx - 200 if hint_idx > 200 else 0)
    if switch_idx == -1:
        raise ValueError("未找到 switch 关键字")
    brace_idx = sub.find("{", switch_idx)
    if brace_idx == -1:
        raise ValueError("未找到 switch 块起始")
    b0, b1 = find_block(sub, brace_idx, "{", "}")
    return sub[b0 + 1 : b1 - 1]


def parse_switch_case_symbols(switch_body: str) -> Set[str]:
    symbols: Set[str] = set()
    buf = ""
    for raw in switch_body.splitlines():
        line = raw.rstrip()
        if not line.strip():
            continue
        buf += line + "\n"
        if "=>" not in buf:
            continue
        head = buf.split("=>", 1)[0]
        buf = ""
        for sym in re.findall(r"\.([A-Za-z_][A-Za-z0-9_]*)", head):
            symbols.add(sym)
    return symbols


def status_from_sets(tag: str, supported: Set[str]) -> str:
    return "已实现" if tag in supported else "未实现"


def write_csv(path: Path, rows: List[Dict[str, str]], headers: List[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=headers)
        w.writeheader()
        w.writerows(rows)


def xlsx_escape(s: str) -> str:
    return (
        s.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
        .replace("'", "&apos;")
    )


def col_to_name(col: int) -> str:
    name = ""
    c = col
    while c > 0:
        c, rem = divmod(c - 1, 26)
        name = chr(ord("A") + rem) + name
    return name


def make_sheet_xml(values: List[List[str]], shared: Dict[str, int]) -> str:
    rows_xml: List[str] = []
    for r_idx, row in enumerate(values, start=1):
        cells: List[str] = []
        for c_idx, val in enumerate(row, start=1):
            cell_ref = f"{col_to_name(c_idx)}{r_idx}"
            sst_id = shared.setdefault(val, len(shared))
            cells.append(f'<c r="{cell_ref}" t="s"><v>{sst_id}</v></c>')
        rows_xml.append(f'<row r="{r_idx}">{"".join(cells)}</row>')
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        "<sheetData>"
        + "".join(rows_xml)
        + "</sheetData></worksheet>"
    )


def make_shared_strings_xml(shared: Dict[str, int]) -> str:
    inv = [""] * len(shared)
    for s, idx in shared.items():
        inv[idx] = s
    items = "".join(f"<si><t>{xlsx_escape(s)}</t></si>" for s in inv)
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        f'count="{len(inv)}" uniqueCount="{len(inv)}">{items}</sst>'
    )


def write_xlsx(path: Path, sheets: List[Tuple[str, List[List[str]]]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    shared: Dict[str, int] = {}
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as z:
        z.writestr(
            "[Content_Types].xml",
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
            '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
            '<Default Extension="xml" ContentType="application/xml"/>'
            '<Override PartName="/xl/workbook.xml" '
            'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
            '<Override PartName="/xl/sharedStrings.xml" '
            'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>'
            + "".join(
                f'<Override PartName="/xl/worksheets/sheet{i}.xml" '
                'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
                for i in range(1, len(sheets) + 1)
            )
            + "</Types>",
        )
        z.writestr(
            "_rels/.rels",
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" '
            'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
            'Target="xl/workbook.xml"/>'
            "</Relationships>",
        )
        sheets_xml = []
        for i, (name, _) in enumerate(sheets, start=1):
            sheets_xml.append(f'<sheet name="{xlsx_escape(name)}" sheetId="{i}" r:id="rId{i}"/>')
        z.writestr(
            "xl/workbook.xml",
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
            'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
            "<sheets>"
            + "".join(sheets_xml)
            + "</sheets></workbook>",
        )
        rels = []
        for i in range(1, len(sheets) + 1):
            rels.append(
                f'<Relationship Id="rId{i}" '
                'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
                f'Target="worksheets/sheet{i}.xml"/>'
            )
        rels.append(
            f'<Relationship Id="rId{len(sheets)+1}" '
            'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" '
            'Target="sharedStrings.xml"/>'
        )
        z.writestr(
            "xl/_rels/workbook.xml.rels",
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            + "".join(rels)
            + "</Relationships>",
        )
        for i, (_, values) in enumerate(sheets, start=1):
            z.writestr(f"xl/worksheets/sheet{i}.xml", make_sheet_xml(values, shared))
        z.writestr("xl/sharedStrings.xml", make_shared_strings_xml(shared))


def build_rows(
    tags: List[str],
    tree_tags: Set[str],
    bc_tags: Set[str],
    fast_tags: Set[str],
    aot_stmt_tags: Set[str],
    aot_expr_tags: Set[str],
    refs: Dict[str, Dict[str, SourceRef]],
) -> List[Dict[str, str]]:
    rows: List[Dict[str, str]] = []
    for tag in tags:
        aot_ir_supported = tag in aot_stmt_tags or tag in aot_expr_tags
        aot_status = "已实现" if aot_ir_supported else "未实现"
        row = {
            "功能点(tag)": tag,
            "Tree": status_from_sets(tag, tree_tags),
            "Bytecode": status_from_sets(tag, bc_tags),
            "Fast": status_from_sets(tag, fast_tags),
            "AOT(IR)": aot_status,
            "Tree位置": refs.get("tree", {}).get(tag, SourceRef("", "")).anchor,
            "Bytecode位置": refs.get("bytecode", {}).get(tag, SourceRef("", "")).anchor,
            "Fast位置": refs.get("fast", {}).get(tag, SourceRef("", "")).anchor,
            "AOT位置": refs.get("aot", {}).get(tag, SourceRef("", "")).anchor,
            "缺失原因": "",
            "备注": "",
        }
        if tag not in bc_tags:
            row["备注"] = "bytecode 未覆盖（visitNode else 静默跳过）"
        if tag not in fast_tags:
            row["备注"] = (row["备注"] + "; " if row["备注"] else "") + "fast 未覆盖（compileNode else 静默跳过）"
        if not aot_ir_supported:
            row["缺失原因"] = "AOT IR 生成未覆盖或回退为 const_null"
        rows.append(row)
    return rows


def main() -> int:
    repo_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", default=str(repo_root))
    parser.add_argument("--out-dir", default=str(repo_root / "artifacts"))
    parser.add_argument("--xlsx", default="diff_matrix.xlsx")
    parser.add_argument("--csv", default="diff_matrix.csv")
    args = parser.parse_args()

    root = Path(args.repo)
    out_dir = Path(args.out_dir)

    tags = extract_node_tags(root / "src" / "compiler" / "ast.zig")

    vm_text = read_text(root / "src" / "runtime" / "vm.zig")
    gen_text = read_text(root / "src" / "bytecode" / "generator.zig")
    fast_text = read_text(root / "src" / "runtime" / "fast_compiler.zig")

    tree_switch = extract_switch_block(vm_text, find_function_region(vm_text, "eval"), "switch (ast_node.tag)")
    bc_switch = extract_switch_block(gen_text, find_function_region(gen_text, "visitNode"), "switch (node.tag)")
    fast_switch = extract_switch_block(
        fast_text,
        find_function_region(fast_text, "compileNode"),
        "switch (node.tag)",
    )

    tree_tags = parse_switch_case_symbols(tree_switch)
    bc_tags = parse_switch_case_symbols(bc_switch)
    fast_tags = parse_switch_case_symbols(fast_switch)

    irg_text = read_text(root / "src" / "aot" / "ir_generator.zig")
    stmt_switch = extract_switch_block(irg_text, find_function_region(irg_text, "generateStatement"), "switch (node.tag)")
    expr_switch = extract_switch_block(irg_text, find_function_region(irg_text, "generateExpression"), "return switch (node.tag)")
    aot_stmt_tags = parse_switch_case_symbols(stmt_switch)
    aot_expr_tags = parse_switch_case_symbols(expr_switch)

    ir_text = read_text(root / "src" / "aot" / "ir.zig")
    ir_ops = extract_union_enum_fields(ir_text, r"pub\s+const\s+Op\s*=\s*union\s*\(\s*enum\s*\)\s*\{")

    nl_text = read_text(root / "src" / "aot" / "native_linker.zig")
    gen_inst_switch = extract_switch_block(nl_text, find_function_region(nl_text, "generateInstruction"), "switch (inst.op)")
    nl_ops = parse_switch_case_symbols(gen_inst_switch)

    rows = build_rows(
        tags=tags,
        tree_tags=tree_tags,
        bc_tags=bc_tags,
        fast_tags=fast_tags,
        aot_stmt_tags=aot_stmt_tags,
        aot_expr_tags=aot_expr_tags,
        refs={},
    )

    headers = [
        "功能点(tag)",
        "Tree",
        "Bytecode",
        "Fast",
        "AOT(IR)",
        "Tree位置",
        "Bytecode位置",
        "Fast位置",
        "AOT位置",
        "缺失原因",
        "备注",
    ]
    write_csv(out_dir / args.csv, rows, headers)

    sheet1: List[List[str]] = [headers]
    for row in rows:
        sheet1.append([row[h] for h in headers])

    sheet2_headers = ["IR.Op", "NativeLinker", "备注"]
    sheet2: List[List[str]] = [sheet2_headers]
    for op in ir_ops:
        sheet2.append([op, "已实现" if op in nl_ops else "未实现", ""])

    meta_headers = ["生成时间", "仓库", "说明"]
    meta_sheet: List[List[str]] = [
        meta_headers,
        [datetime.now(timezone.utc).isoformat(), str(root), "本文件由 tools/gen_diff_matrix.py 自动生成"],
    ]

    write_xlsx(out_dir / args.xlsx, [("功能点", sheet1), ("AOT_OP", sheet2), ("Meta", meta_sheet)])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
