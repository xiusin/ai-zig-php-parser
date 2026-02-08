# AOT 后续优化开发草案（基于 2026-02-01 后续优化建议）

本文档目标：把 [2026-02-01后续优化建议.md](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/2026-02-01%E5%90%8E%E7%BB%AD%E4%BC%98%E5%8C%96%E5%BB%BA%E8%AE%AE.md) 的“后续建议”落为可执行的迭代草案（按优先级、可验收、可回滚）。

## 范围与原则

- 范围：AOT 编译链路（入口/IR/优化/后端/Runtime/Diagnostics/测试体系），重点解决正确性、可定位性与覆盖率差异。
- 原则：正确性优先于性能；所有语义对齐以解释器输出为 oracle；高风险改动分批合入并保留降级开关。

## 架构视图（六边形）

```mermaid
flowchart LR
  subgraph Hex[Hexagonal Architecture - AOT Pipeline]
    direction LR

    CLI[CLI/入口 main.zig]
    Parser[Parser/AST]
    IRGen[IRGenerator (SSA+CFG)]
    Opt[Optimizer]
    Ports[Ports: IR / Runtime API / Diagnostics]
    Native[Adapter: NativeLinker]
    LLVM[Adapter: LLVM Codegen]
    RT[Adapter: Runtime Lib]
    Tests[Adapter: Diff Tests]

    CLI --> Parser --> IRGen --> Opt --> Ports
    Ports --> Native --> RT
    Ports --> LLVM --> RT
    Ports --> Tests
  end
```

## 交付物（按优先级）

| 优先级 | 任务 | 影响面 | 落地成本 | 主要产出 |
| --- | --- | --- | --- | --- |
| P0 | PHI/控制流回归测试补齐（覆盖所有前驱+合流先执行） | 正确性（分支/循环/异常路径） | 中 | 新增脚本集 + 差分测试门禁 |
| P0 | SourceLocation 统一/补齐 + Diagnostics 路径归一化 | 可定位性（__LINE__/报错路径） | 中-高 | 统一定位策略 + golden 输出测试 |
| P0 | IR op 覆盖矩阵“可执行化”（检测 IR 出现但后端不支持的 op） | 工程质量（阻断 silent failure） | 低-中 | 自动报告/CI gate（先 warn 后 error） |
| P1 | 并发/异步 op 端到端落地（go_spawn/await/channel/select） | 覆盖率（语言特性） | 高 | op 全链路支持 + 资源释放保证 |
| P1 | 比较语义系统对齐（先 ===/!==，再 ==/!=/<=>） | 正确性（类型组合复杂） | 高 | 表格驱动用例 + 分阶段语义对齐 |
| P1 | 对象/属性/魔术方法行为对齐 | 正确性+覆盖率（OOP） | 中-高 | class meta 最小字段规范 + 脚本回归集 |
| P2 | 生成期分配收敛（编译期 arena 托管稳定 slice） | 性能+稳定性 | 中 | alloc 次数/峰值可度量下降 |
| P2 | 调试能力增强（AOT stack trace + source mapping） | 可维护性 | 中 | 崩溃信息字段完整、可定位 |
| P2 | 差分测试框架规模化（脚本集自动对齐） | 工程效率 | 中 | 可配置脚本白名单、差异报告标准化 |

## 里程碑切分（按可回滚粒度）

### Milestone 1：正确性与可定位性闭环（P0）

- M1-1：PHI/控制流差分测试集
  - 覆盖：嵌套 if、短路逻辑、循环回边 PHI、switch/match 合流、try/catch/finally 合流
  - 入口：新增“解释器 vs AOT 输出差分”测试驱动（最小可用版本）
- M1-2：Diagnostics 路径归一化
  - 去掉硬编码前缀；相对化基准：默认 input_file 所在目录，可配置切换为工程根探测
- M1-3：SourceLocation 统一方案落地（分两步）
  - 第一步：AOT 内部位置来源稳定化（保持当前 token->line/column 的正确性）
  - 第二步：推动与前端 token/Node 的结构对齐（减少“双套 token”）
- M1-4：IR op 覆盖检查
  - 测试期：warn；CI 稳定后升为 error

### Milestone 2：覆盖率推进（P1）

- M2-1：并发/异步最小可用集
  - 推荐顺序：go_spawn + await_ → channel_send/recv/close → select_
- M2-2：严格比较（===/!==）全类型组合覆盖
- M2-3：对象/属性/魔术方法对齐（以解释器为 oracle）

### Milestone 3：性能与体验（P2）

- M3-1：编译期 arena 分配策略与指标采集
- M3-2：AOT 栈追踪与 source mapping（崩溃可定位）
- M3-3：差分测试框架扩容（快集/全量集分层）

## 验收标准（Definition of Done）

- 正确性：同一脚本在解释器与 AOT 输出逐字一致（除非标注为“允许非确定性集合”）。
- 可定位性：AOT 报错/诊断信息包含文件路径（归一化后）、行列号；`__LINE__/__FILE__/__DIR__` 与解释器一致。
- 稳定性：关键脚本多次运行输出一致；并发相关无死锁、无资源泄漏。
- 内存安全：测试启用 leak-check（阈值=0）；新增/修改的编译期分配路径有明确所有权与释放时机。
- 工程门禁：新增 op 必须同时补齐（IRGen/Optimizer/后端/Runtime/用例/覆盖检查）中的缺口，且通过 CI。

## 测试门禁（建议作为 CI 规则）

- Gate A：差分测试（解释器 vs AOT）快集（P0 关键脚本）
- Gate B：AOT 单元测试 + leak-check（含 OOP/Runtime/并发）
- Gate C：IR op 覆盖检查（先 warn；稳定后 error）
- Gate D（P2）：性能基线对比（仅对标注脚本/基准项）

## 风险与降级（回滚点）

- 控制流/PHI：高风险，按“语法点/用例集”分批合入；任何回归按提交粒度回退。
- SourceLocation/token 对齐：改动面大，拆为“先 Diagnostics 再统一 token”；必要时保留 AOT 专用 token 结构作为过渡。
- 并发/异步：非确定性与死锁风险高；每个 op 独立合入并保留 AOT 路径开关，便于临时禁用。
- 比较/对象语义：细节密集，必须以解释器为 oracle；按运算符/能力点分阶段推进，避免“一次性大改”。

## 附录：新增/修复 IR op 的最小路径检查单

1) IR 是否定义（src/aot/ir.zig）  
2) IRGenerator 是否生成（src/aot/ir_generator.zig）  
3) Optimizer 是否标记寄存器使用/副作用（src/aot/optimizer.zig）  
4) 后端 lowering：native（src/aot/native_linker.zig）/llvm（src/aot/codegen.zig）  
5) Runtime API 是否齐备（src/aot/runtime_lib*.zig / src/runtime/*）  
6) 增加对齐测试：解释器 vs AOT 输出一致（或定义允许集合）  
7) 更新覆盖检查与文档矩阵（作为长期维护项）  
