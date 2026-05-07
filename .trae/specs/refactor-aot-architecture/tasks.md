# Tasks

- [x] Task 1: 现状诊断补全到 spec
  - [x] 将“多套 builtin/stdlib 机制并存、runtime_lib_template 过度聚合、AOT 代码生成特判膨胀、缺少性能门禁”等问题用条目化方式写入 spec

- [x] Task 2: 给出目标分层与关键抽象（Function Registry / 模块注册 / 调用点绑定）
  - [x] 在 spec 中明确 Frontend/Semantic/IR/Opt/Backend/Runtime 的职责与依赖方向
  - [x] 在 spec 中给出 FunctionId/FunctionMeta/FunctionImpl/ModuleRegistration 的建议接口
  - [x] 在 spec 中明确 ResolvedCall 与 DynamicCall 的区分与迁移策略

- [x] Task 3: 给出分阶段迁移路线与性能治理框架
  - [x] 在 spec 中给出 Phase 0~5 的迁移路线
  - [x] 在 spec 中明确基准集合（microbench/macrobench）与门禁思路

# Task Dependencies
- Task 2 depends on Task 1
- Task 3 depends on Task 2
