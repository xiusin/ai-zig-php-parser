# Multi-File Project AOT Test Report
Test time: 2026-07-20 22:30:11


## blog_system

- **Output Diff**
```diff
4,5d3
< PHP Deprecated:  BlogDB::select(): Implicitly marking parameter $orderBy as nullable is deprecated, the explicit nullable type must be used instead in /Users/tuoke/Desktop/ai-zig-php-parser/multi_file_projects/blog_system/Database.php on line 41
< Deprecated: BlogDB::select(): Implicitly marking parameter $orderBy as nullable is deprecated, the explicit nullable type must be used instead in /Users/tuoke/Desktop/ai-zig-php-parser/multi_file_projects/blog_system/Database.php on line 41
37c35,36
< <h1>Introduction</h1>
---
> <p># Introduction
> </p>
40,45c39,45
< <h2>Features</h2>
< <ul><li>Fast execution</li>
< <li>Type safety</li>
< <li>No interpreter overhead</li>
< </ul>
< ``<code>php
---
> <p>## Features
> </p>
> <p>- Fast execution
> - Type safety
> - No interpreter overhead
> </p>
> <p>``<code>php
49c49,50
< Visit <...
---
> </p>
> Visit [PHP.net](https:...
58c59
< Article 1 views: 0
```

## ecommerce

- **Output Diff**
```diff
32,33c32,33
< iPhone stock after order: 50 (was 50)
< AirPods stock after order: 100 (was 100)
---
> iPhone stock after order: 49 (was 50)
> AirPods stock after order: 98 (was 100)
66c66
< [16] $3477.75 - pending
---
> [16] $3477.75 - refunded
```

## web_framework

- **Compile Failed**: Detected require/include statements, using multi-file compiler...
Error: Multi-file compilation failed: OutOfMemory
error: CompilationFailed
```
Detected require/include statements, using multi-file compiler...
Error: Multi-file compilation failed: OutOfMemory
error: CompilationFailed
```

## Summary

| Metric | Value |
|--------|-------|
| Total | 3 |
| Passed | 0 |
| Compile Failed | 1 |
| Runtime Failed | 0 |
| Output Diff | 2 |
