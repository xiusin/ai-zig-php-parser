# 完善Zig-PHP LSP实现计划

## 项目现状分析
- **LSP基础结构**：已创建`tool/lsp`目录和`main.zig`文件，`build.zig`中已配置LSP构建目标
- **编译器集成**：`build.zig`已将`compiler`模块导入LSP项目
- **核心数据结构**：`PHPContext`已实现，包含解析所需的核心功能
- **当前状态**：`main.zig`仅包含空的main函数，未实现任何LSP功能

## 完善计划

### 阶段1：基础设施 & 构建系统（已部分完成）
- [x] **1.1 Project Structure**：已创建`tool/lsp`目录和`main.zig`
- [x] **1.2 Build Configuration**：`build.zig`已配置LSP构建目标和编译器模块导入
- [ ] **1.3 JSON-RPC Core**：实现LSP协议的核心通信机制
  - 实现Content-Length头解析
  - 实现JSON序列化/反序列化
  - 实现消息路由和处理
- [ ] **1.4 Handshake**：实现LSP握手协议
  - 处理`initialize`请求
  - 发送`initialized`通知
  - 实现基本的错误处理

### 阶段2：诊断（Linting）
- [ ] **2.1 Document Synchronization**：
  - 处理`textDocument/didOpen`请求
  - 处理`textDocument/didChange`请求
  - 管理内存中的文档状态
- [ ] **2.2 Compiler Integration**：
  - 将`PHPContext`和`Parser`集成到LSP循环
  - 实现文档到解析器的转换
  - 管理解析上下文的生命周期
- [ ] **2.3 Error Reporting**：
  - 将`PHPContext.errors`转换为LSP `Diagnostic`对象
  - 实现`textDocument/publishDiagnostics`通知
  - 支持增量诊断更新

### 阶段3：基本语言特性
- [ ] **3.1 Go to Definition**：
  - 实现`textDocument/definition`请求
  - 实现AST遍历查找符号定义
  - 支持命名空间和导入解析
- [ ] **3.2 Hover Information**：
  - 实现`textDocument/hover`请求
  - 收集符号的类型信息和注释
  - 格式化hover响应内容

### 阶段4：内存管理与性能优化
- [ ] **4.1 Memory Safety**：
  - 实现每个请求或文档修订的`ArenaAllocator`管理
  - 确保所有内存都能正确释放
  - 避免内存泄漏
- [ ] **4.2 Performance Optimization**：
  - 实现增量解析
  - 优化文档更新处理
  - 实现请求批处理

### 阶段5：测试与验证
- [ ] **5.1 Unit Tests**：
  - 为JSON-RPC核心添加单元测试
  - 为LSP请求处理添加单元测试
- [ ] **5.2 Integration Tests**：
  - 测试LSP与编辑器的集成
  - 验证诊断、跳转定义和悬停功能
- [ ] **5.3 Memory Leak Testing**：
  - 运行内存泄漏测试
  - 确保Zig层面无内存泄漏

## 技术实现要点

### JSON-RPC实现
- 使用Zig标准库的`std.json`进行JSON处理
- 实现基于stdin/stdout的通信
- 支持批量请求和部分结果

### 文档管理
- 使用哈希表存储已打开的文档
- 为每个文档维护独立的解析上下文
- 实现高效的文档更新机制

### 编译器集成
- 复用现有的`PHPContext`和`Parser`
- 实现文档到解析器的桥接
- 处理解析错误并转换为LSP诊断

### 内存管理
- 每个文档使用独立的`ArenaAllocator`
- 请求处理完成后释放相关内存
- 实现资源的自动管理

## 开发规范
- **无侵入性**：LSP代码不修改主程序代码
- **内存安全**：确保所有内存操作都符合Zig的安全标准
- **无DEBUG日志**：生产环境不输出DEBUG级别的日志
- **符合LSP规范**：严格按照LSP 3.17规范实现

## 实现顺序
1. 实现JSON-RPC核心（阶段1.3）
2. 实现LSP握手（阶段1.4）
3. 实现文档同步（阶段2.1）
4. 实现编译器集成和诊断（阶段2.2-2.3）
5. 实现基本语言特性（阶段3.1-3.2）
6. 优化内存管理和性能（阶段4）
7. 进行测试和验证（阶段5）

## 预期成果
- 功能完整的Zig-PHP LSP服务器
- 支持诊断、跳转定义和悬停功能
- 内存安全，无内存泄漏
- 与主流编辑器（VS Code、Cursor）兼容
- 符合LSP规范