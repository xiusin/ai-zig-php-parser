# AOT 性能基准与回归检测 — 开发进度总结报告

## 模块范围
- 微基准套件：数组操作、字符串拼接、可调用调用、对象操作（生命周期/属性访问）、异常处理、排序
- 回归检测：时间与内存分配多维指标（avg_time_ns、alloc_bytes、peak_live_bytes、object_allocs 等）
- 报告与CI：命令行工具、CI 集成、Markdown 报告输出
- AOT Runtime：分配统计 API（reset/get/peak监控）

## 当前进度快照
- 微基准产出统一结构 BenchmarkResult，并已包含内存分配指标
  - 参考：[microbench_suite.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/benchmark/microbench_suite.zig#L69-L157)
- 回归检测器支持时间与内存变化百分比比较，并生成 Markdown 报告
  - 参考：检测与报告生成 [regression_detector.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/benchmark/regression_detector.zig#L236-L452)
- CLI 集成到 build.zig，可一键“检测回归/更新基线/列出基线”
  - 参考：构建入口 [build.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/build.zig#L402-L439)
  - 参考：命令行工具 [perf_cli.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/benchmark/perf_cli.zig)
- CI Runner 自动生成报告至 .perf_reports 并可在主分支更新基线
  - 参考：[ci_integration.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/benchmark/ci_integration.zig#L132-L207)
- AOT Runtime 提供分配统计 API，微基准已对接
  - 参考：[runtime_lib_template.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/aot/runtime_lib_template.zig#L149-L153)

## 已完成事项
- 微基准套件基础三项实现并稳定运行
- RegressionDetector 扩展为时间/内存双阈值检测，报告包含 alloc 指标
- perf-cli 集成 check/update/list/reset；在 CI 中调用并落地报告
- build.zig 链接依赖模块与 perf-cli，保证工具可执行
- 属性测试与单元测试覆盖批量/无基线/百分比计算正确性
- **[NEW] 微基准覆盖扩大**：新增大数组、字符串搜索、对象生命周期、异常、闭包、排序等场景
- **[NEW] 内存指标细化**：AOT Runtime 支持对象计数、峰值内存统计；回归报告新增 Obj Allocs/Peak Live 指标
- **[NEW] 报告易读性增强**：新增 Top 回归摘要、区分时间/内存回归状态（❌ TIME / ❌ MEM）
- **[NEW] 阈值策略优化**：支持分别设置时间阈值（默认 5.0%）和内存阈值（默认 1.0%）

## 待完成事项（优先级/影响面/落地成本）

| 优先级 | 事项 | 影响面 | 落地成本 |
| --- | --- | --- | --- |
| P1 | CI 注释完善（超限原因标注） | 中 | 低 |
| P2 | 形成 AOT 优化设计+测试报告+对比分析交付稿 | 中 | 中 |

## 验证与使用
- 检测回归：`zig build perf-check`（生成 .perf_reports/perf_report_时间戳.md）
- 更新基线：`zig build perf-update`
- 列出基线：`zig build perf-list`
- 结果来源：
  - 微基准产出： [microbench_suite.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/benchmark/microbench_suite.zig)
  - 基线目录： `.perf_baselines/`
  - 报告目录： `.perf_reports/`

## 规范遵循检查
- SOLID/KISS/DRY/YAGNI：回归检测器职责单一；无冗余抽象；指标采集与比较解耦；不引入无需求字段
- 安全检查：未引入敏感信息；未动态拼接不可信输入；allocator 显式传递与释放
- 测试要求：关键模块含单测与属性测试，构建命令已联通

## 风险与建议
- 指标多样性与真实场景覆盖仍需加强，建议优先落地 P0 两项
- 报告解释性与 CI 反馈需更明确，减少“仅数值”导致的研判成本

