#!/bin/bash
# CodeGraph Zig 支持补丁 — 自动打补丁脚本
# 用法: ./scripts/patch-codegraph-zig.sh [版本号，默认自动检测最新版本]
# 说明: 修改 CodeGraph 安装目录文件以支持 .zig 文件索引
#       升级 CodeGraph 后需要重新执行此脚本

set -euo pipefail

CG_DIR="/Users/tuoke/.codegraph/versions"

# 确定版本：参数指定 or 自动检测最新
CG_VER="${1:-$(ls "$CG_DIR" | sort -V | tail -1)}"
CG="$CG_DIR/$CG_VER"

echo "🔧 开始为 CodeGraph $CG_VER 打 Zig 支持补丁..."
echo "  目标路径: $CG"

# 验证目录
if [ ! -f "$CG/lib/dist/extraction/grammars.js" ]; then
    echo "❌ 无效路径：未找到 $CG/lib/dist/extraction/grammars.js"
    echo "  请确认 CodeGraph 安装路径是否正确"
    exit 1
fi

# 检查是否已有补丁
if grep -q "'.zig'" "$CG/lib/dist/extraction/grammars.js"; then
    echo "✅ 检测到 Zig 扩展映射已存在，跳过 EXTENSION_MAP 补丁"
    HAS_EXT_MAP=true
else
    HAS_EXT_MAP=false
fi

if grep -q "zig:" "$CG/lib/dist/extraction/grammars.js"; then
    echo "✅ 检测到 Zig WASM 语法已注册，跳过 WASM_GRAMMAR_FILES 补丁"
    HAS_WASM=true
else
    HAS_WASM=false
fi

if [ -f "$CG/lib/dist/extraction/languages/zig.js" ]; then
    echo "✅ zig.js extractor 已存在，跳过"
    HAS_ZIG_JS=true
else
    HAS_ZIG_JS=false
fi

if grep -q "zig_1" "$CG/lib/dist/extraction/languages/index.js"; then
    echo "✅ EXTRACTORS 注册已存在，跳过"
    HAS_INDEX=true
else
    HAS_INDEX=false
fi

if $HAS_EXT_MAP && $HAS_WASM && $HAS_ZIG_JS && $HAS_INDEX; then
    echo "🎉 所有补丁已存在，无需修改！"
    exit 0
fi

echo ""
echo "📝 开始打补丁..."

# === 1. grammars.js ===
GRAMMARS="$CG/lib/dist/extraction/grammars.js"

# 1a. WASM_GRAMMAR_FILES — 在 luau 后面插入 zig
if ! $HAS_WASM; then
    echo "  [1a] 注册 WASM 语法文件..."
    # 使用 perl 进行多行处理（macOS sed 不方便）
    perl -i -pe 's/(luau: .*tree-sitter-luau\.wasm\b)/$1,\n    zig: .tree-sitter-zig.wasm/;' "$GRAMMARS"
fi

# 1b. EXTENSION_MAP — 在 .luau 后面插入 .zig
if ! $HAS_EXT_MAP; then
    echo "  [1b] 注册扩展名映射..."
    perl -i -pe "s/('.luau': 'luau')/\$1,\n    '.zig': 'zig'/;" "$GRAMMARS"
fi

# === 2. 创建 zig.js ===
if ! $HAS_ZIG_JS; then
    echo "  [2] 创建 zig.js extractor..."
    cat > "$CG/lib/dist/extraction/languages/zig.js" << 'ZIGEOF'
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.zigExtractor = void 0;
const tree_sitter_helpers_1 = require("../tree-sitter-helpers");
exports.zigExtractor = {
    functionTypes: ['function_declaration', 'test_declaration'],
    classTypes: [],
    methodTypes: ['function_declaration'],
    interfaceTypes: ['opaque_declaration', 'anyframe_type'],
    structTypes: ['struct_declaration'],
    enumTypes: ['enum_declaration', 'error_set_declaration'],
    enumMemberTypes: ['container_field'],
    typeAliasTypes: ['error_set_declaration'],
    importTypes: ['using_namespace_declaration'],
    callTypes: ['call_expression'],
    variableTypes: ['variable_declaration'],
    fieldTypes: ['container_field'],
    nameField: 'name',
    bodyField: 'body',
    paramsField: 'parameters',
    returnField: 'return_type',
    getSignature: (node, source) => {
        const params = (0, tree_sitter_helpers_1.getChildByField)(node, 'parameters');
        const returnType = (0, tree_sitter_helpers_1.getChildByField)(node, 'return_type');
        if (!params)
            return undefined;
        let sig = (0, tree_sitter_helpers_1.getNodeText)(params, source);
        if (returnType) {
            sig += ' -> ' + (0, tree_sitter_helpers_1.getNodeText)(returnType, source);
        }
        return sig;
    },
    getVisibility: (node) => {
        return 'public';
    },
    getReceiverType: (node, source) => {
        let parent = node.parent;
        while (parent) {
            if (parent.type === 'struct_declaration' ||
                parent.type === 'enum_declaration' ||
                parent.type === 'union_declaration' ||
                parent.type === 'opaque_declaration') {
                const nameNode = (0, tree_sitter_helpers_1.getChildByField)(parent, 'name');
                if (nameNode) {
                    return source.substring(nameNode.startIndex, nameNode.endIndex);
                }
                return undefined;
            }
            parent = parent.parent;
        }
        return undefined;
    },
    extractImport: (node, source) => {
        const importText = source.substring(node.startIndex, node.endIndex).trim();
        return { moduleName: importText, signature: importText };
    },
    isAsync: () => false,
};
ZIGEOF
fi

# === 3. index.js ===
INDEX="$CG/lib/dist/extraction/languages/index.js"
if ! $HAS_INDEX; then
    echo "  [3] 注册 zig extractor 到索引..."
    # 插入 require
    perl -i -pe 's/(const luau_1 = require\("\.\/luau"\))/$1;\nconst zig_1 = require(".\/zig");/' "$INDEX"
    # 插入 EXTRACTORS 条目
    perl -i -pe 's/(luau: luau_1\.luauExtractor,)/$1\n    zig: zig_1.zigExtractor,/' "$INDEX"
fi

echo ""
echo "✅ 补丁完成！"
echo ""
echo "下一步: 重新索引项目"
echo "  codegraph uninit -f && codegraph init -i -v"
echo ""
echo "验证:"
echo "  codegraph status | grep zig"
echo "  codegraph query \"main\" --kind function --limit 3"