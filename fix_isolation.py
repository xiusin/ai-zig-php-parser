import re

with open('src/aot/native_linker.zig', 'r') as f:
    content = f.read()

# Pattern 1: Add save/clear before "Coalesce 模式检测" in loop handlers
# The pattern appears in foreach, for, and while handlers
# We need to insert before the Coalesce comment, after the PHI 消解 block

# Find all occurrences of the Coalesce pattern preceded by then block PHI
# The unique context is the PHI 消解 block ending + empty line + Coalesce comment
save_clear_pattern = r'''                    }

                    // Coalesce 模式检测：else 块就是 merge 块（then br → else）
                    // 此模式下 else 分支仅需 PHI，merge 块的指令和 cond_br 在 if/else 之后处理
                    var else_is_be = false;'''

save_clear_replacement = '''                    }

                    // 隔离 then/else 返回状态：保存 then 的返回/break 状态，清除后处理 else
                    const loop_cond_br_then_returned = self.return_generated;
                    const loop_cond_br_then_breaked = self.break_generated;
                    self.return_generated = false;
                    self.break_generated = false;

                    // Coalesce 模式检测：else 块就是 merge 块（then br → else）
                    // 此模式下 else 分支仅需 PHI，merge 块的指令和 cond_br 在 if/else 之后处理
                    var else_is_be = false;'''

count1 = content.count(save_clear_pattern)
content = content.replace(save_clear_pattern, save_clear_replacement)
print(f"Pattern 1 (save/clear before Coalesce): replaced {count1} occurrences")

# Pattern 2: Add AND combine after "self.pending_merge_non_phi = saved_pending_merge;"
# and before the restore comment in loop handlers
# The pattern appears in foreach, for, and while handlers

combine_pattern = '''                    self.pending_merge_non_phi = saved_pending_merge;

                    // 恢复 return_generated/break_generated
                    // 仅在 then/else 均未设置时恢复（至少一个分支可达）'''

combine_replacement = '''                    self.pending_merge_non_phi = saved_pending_merge;

                    // 合并 then/else 返回状态：仅当两个分支都返回/break 时才标记为已返回
                    self.return_generated = loop_cond_br_then_returned and self.return_generated;
                    self.break_generated = loop_cond_br_then_breaked and self.break_generated;

                    // 恢复 return_generated/break_generated
                    // 仅在 then/else 均未设置时恢复（至少一个分支可达）'''

count2 = content.count(combine_pattern)
content = content.replace(combine_pattern, combine_replacement)
print(f"Pattern 2 (AND combine after pending_merge): replaced {count2} occurrences")

with open('src/aot/native_linker.zig', 'w') as f:
    f.write(content)

print("Done!")
