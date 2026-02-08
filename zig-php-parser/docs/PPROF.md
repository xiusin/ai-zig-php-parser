# pprof 文档

## 目标

本仓库提供 pprof（google/pprof profile.proto）兼容的 **CPU profile 导出**，以便使用 `go tool pprof` 的 Top/Graph/Web UI 分析热点路径。

当前实现是“从火焰图树/折叠格式导出 pprof profile”，适合做 CPU 热点定位与调用路径分析。

## 输出格式

- 输出文件是 **未压缩的 protobuf（二进制）**，建议使用 `.pb` 扩展名。
- 默认 sample_type：`cpu / nanoseconds`

## 使用方式

### 0) AOT 运行时自动导出（推荐）

AOT 编译的可执行文件在设置环境变量后，会在进程退出前自动写出：

- `profile.pb`
- `flamegraph.txt`

```bash
ZIGPHP_PROFILE=1 ZIGPHP_PROFILE_INTERVAL_NS=1000000 ./your_aot_binary
go tool pprof -http=:0 profile.pb
```

### 1) 从 folded stacks 转成 pprof

```bash
./zig-out/bin/profile-cli folded_to_pprof flamegraph.txt profile.pb --unit us --period-ns 1000000
```

- `--unit us|ns`：folded 文件里 count 的单位（本仓库 `generateFoldedFormat` 默认是 `us`）
- `--period-ns`：采样周期（只用于 profile 的 `period` 字段，便于 UI 展示）

### 2) 用 go tool pprof 查看

```bash
go tool pprof -top profile.pb
go tool pprof -http=:0 profile.pb
```

## 编程接口

运行时导出入口：

- [pprof.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/runtime/pprof.zig)
  - `writeCpuProfileFromFlameGraph(allocator, writer, root, sampling_period_ns)`

典型流程：

1. 用 [flamegraph.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/runtime/flamegraph.zig) 构建火焰图树（采样/导入 folded）
2. 调用 `writeCpuProfileFromFlameGraph` 写入 `.pb`

## 限制与注意事项

- 当前 profile 的 Location/Function 信息只填充了函数名（没有真实文件名/行号/地址映射），因此图形视图是“按函数名聚合”的调用路径。
- 输出不包含 heap/mutex/block 等 profile 类型；只覆盖 CPU profile 这一路。
