# Requirements Document

## Introduction

本规范定义了 zig-php 解释器的多语法模式支持和第三方扩展系统。多语法模式允许用户通过命令行参数（如 `--syntax=go`）选择不同的语法风格，使代码更接近其他编程语言的习惯。第三方扩展系统允许外部开发者在不修改核心源代码的情况下扩展解释器功能。

## Glossary

- **Syntax_Mode**: 语法模式，定义变量声明、属性访问等语法规则的配置
- **PHP_Mode**: PHP 风格语法，变量以 `$` 开头，属性访问使用 `->`
- **Go_Mode**: Go 风格语法，变量不需要 `$` 前缀，属性访问使用 `.`
- **Lexer**: 词法分析器，将源代码转换为 Token 流
- **Parser**: 语法分析器，将 Token 流转换为 AST
- **AST**: 抽象语法树，代码的结构化表示
- **VM**: 虚拟机，执行 AST 或字节码的运行时
- **Bytecode**: 字节码，中间表示形式
- **AOT_Compiler**: 预编译器，将代码编译为原生可执行文件
- **Extension**: 扩展，第三方提供的功能模块
- **Extension_Registry**: 扩展注册表，管理已加载扩展的系统
- **Extension_API**: 扩展接口，第三方扩展必须实现的接口规范
- **Hook_Point**: 钩子点，允许扩展介入执行流程的位置

## Requirements

### Requirement 1: 语法模式配置系统

**User Story:** As a developer, I want to select different syntax modes via command line, so that I can write code in my preferred style.

#### Acceptance Criteria

1. WHEN a user specifies `--syntax=php` THEN THE Lexer SHALL use PHP-style tokenization with `$` variable prefix and `->` property access
2. WHEN a user specifies `--syntax=go` THEN THE Lexer SHALL use Go-style tokenization without `$` variable prefix and `.` property access
3. WHEN no syntax mode is specified THEN THE System SHALL default to PHP mode
4. WHEN an invalid syntax mode is specified THEN THE System SHALL display an error message and list valid modes
5. THE Syntax_Mode SHALL be propagated from command line through Lexer, Parser, VM, Bytecode generator, and AOT compiler

### Requirement 2: Go 模式词法分析

**User Story:** As a developer using Go mode, I want the lexer to recognize Go-style syntax, so that I can write cleaner code without PHP-specific symbols.

#### Acceptance Criteria

1. WHEN in Go_Mode and an identifier is encountered THEN THE Lexer SHALL treat it as a variable without requiring `$` prefix
2. WHEN in Go_Mode and `.` followed by an identifier is encountered THEN THE Lexer SHALL emit an arrow token for property access
3. WHEN in Go_Mode and `$` is encountered THEN THE Lexer SHALL report a syntax error
4. WHEN in Go_Mode THEN THE Lexer SHALL still recognize PHP keywords (function, class, if, etc.)
5. WHEN in Go_Mode and a method call `a.method()` is parsed THEN THE Lexer SHALL emit tokens equivalent to PHP's `$a->method()`

### Requirement 3: Go 模式语法分析

**User Story:** As a developer using Go mode, I want the parser to correctly build AST from Go-style syntax, so that the code executes correctly.

#### Acceptance Criteria

1. WHEN in Go_Mode and parsing a variable THEN THE Parser SHALL create a variable node with `$` prefix added internally
2. WHEN in Go_Mode and parsing property access `a.b` THEN THE Parser SHALL create a property_access node
3. WHEN in Go_Mode and parsing method call `a.method()` THEN THE Parser SHALL create a method_call node
4. WHEN in Go_Mode and parsing class definition THEN THE Parser SHALL allow property declarations without `$` prefix
5. THE Parser SHALL produce semantically equivalent AST regardless of syntax mode
6. WHEN in Go_Mode and parsing string concatenation with `+` operator THEN THE Parser SHALL create a concat node (equivalent to PHP's `.` operator for strings)
7. WHEN in Go_Mode and parsing numeric addition with `+` operator THEN THE Parser SHALL create an addition node

### Requirement 4: 运行时语法模式支持

**User Story:** As a developer, I want the VM to execute code correctly regardless of syntax mode, so that both PHP and Go style code produce the same results.

#### Acceptance Criteria

1. THE VM SHALL execute AST nodes identically regardless of original syntax mode
2. WHEN executing variable access THEN THE VM SHALL resolve variables using internal `$`-prefixed names
3. WHEN executing property access THEN THE VM SHALL use the same property resolution logic for both modes
4. WHEN an error occurs THEN THE VM SHALL report errors using the original syntax style for clarity

### Requirement 5: 字节码语法模式支持

**User Story:** As a developer, I want bytecode generation to work correctly with Go-style syntax, so that I can use the bytecode VM for better performance.

#### Acceptance Criteria

1. THE Bytecode_Generator SHALL produce identical bytecode for semantically equivalent code in different syntax modes
2. WHEN generating bytecode for variable access THEN THE Generator SHALL use normalized variable names
3. THE Bytecode_VM SHALL execute bytecode without knowledge of original syntax mode

### Requirement 6: AOT 编译器语法模式支持

**User Story:** As a developer, I want to compile Go-style code to native executables, so that I can deploy high-performance applications.

#### Acceptance Criteria

1. THE AOT_Compiler SHALL accept source files in any supported syntax mode
2. WHEN compiling Go_Mode source THEN THE AOT_Compiler SHALL produce functionally equivalent native code
3. THE AOT_Compiler SHALL include syntax mode in debug information for error reporting

### Requirement 7: 扩展系统架构

**User Story:** As a third-party developer, I want a well-defined extension API, so that I can add new functionality without modifying core source code.

#### Acceptance Criteria

1. THE Extension_API SHALL define interfaces for registering new functions
2. THE Extension_API SHALL define interfaces for registering new classes
3. THE Extension_API SHALL define interfaces for registering new syntax transformations
4. THE Extension_API SHALL provide access to VM state for advanced extensions
5. THE Extension_Registry SHALL manage extension lifecycle (load, initialize, shutdown)

### Requirement 8: 扩展加载机制

**User Story:** As a user, I want to load extensions at runtime, so that I can customize the interpreter for my needs.

#### Acceptance Criteria

1. WHEN `--extension=path/to/ext.so` is specified THEN THE System SHALL load the dynamic library
2. WHEN an extension is loaded THEN THE Extension_Registry SHALL call the extension's init function
3. IF an extension fails to load THEN THE System SHALL report the error and continue without the extension
4. THE System SHALL support loading multiple extensions in specified order
5. WHEN the interpreter shuts down THEN THE Extension_Registry SHALL call each extension's cleanup function

### Requirement 9: 扩展函数注册

**User Story:** As an extension developer, I want to register custom functions, so that users can call them from PHP/Go code.

#### Acceptance Criteria

1. THE Extension_API SHALL provide a function registration interface with name, callback, and parameter info
2. WHEN a registered function is called THEN THE VM SHALL invoke the extension callback with proper arguments
3. THE Extension_API SHALL support both synchronous and asynchronous function callbacks
4. WHEN a function name conflicts with existing functions THEN THE System SHALL report an error during registration

### Requirement 10: 扩展类注册

**User Story:** As an extension developer, I want to register custom classes, so that users can instantiate and use them.

#### Acceptance Criteria

1. THE Extension_API SHALL provide a class registration interface with name, methods, and properties
2. WHEN a registered class is instantiated THEN THE VM SHALL create an object with extension-defined behavior
3. THE Extension_API SHALL support inheritance from built-in classes
4. THE Extension_API SHALL support implementing interfaces

### Requirement 11: 语法扩展钩子

**User Story:** As an extension developer, I want to hook into the parsing process, so that I can add custom syntax.

#### Acceptance Criteria

1. THE Extension_API SHALL provide hooks for custom statement parsing
2. THE Extension_API SHALL provide hooks for custom expression parsing
3. WHEN a syntax hook is triggered THEN THE Parser SHALL delegate to the extension's handler
4. THE Extension_API SHALL allow extensions to register custom keywords

### Requirement 12: 配置文件支持

**User Story:** As a user, I want to configure syntax mode and extensions via config file, so that I don't need to specify them on every command.

#### Acceptance Criteria

1. THE System SHALL read configuration from `.zigphp.json` or `zigphp.config.json`
2. THE Configuration SHALL support specifying default syntax mode
3. THE Configuration SHALL support listing extensions to auto-load
4. WHEN both config file and command line specify options THEN command line SHALL take precedence

### Requirement 13: 语法模式互操作性

**User Story:** As a developer, I want to use libraries written in different syntax modes, so that I can leverage existing code.

#### Acceptance Criteria

1. THE System SHALL allow including files with different syntax modes
2. WHEN including a file THEN THE System SHALL detect or use specified syntax mode for that file
3. THE System SHALL support `// @syntax: go` or `// @syntax: php` directives at file start
4. WHEN calling functions across syntax modes THEN THE System SHALL handle parameter passing correctly

### Requirement 14: 错误报告语法感知

**User Story:** As a developer, I want error messages to reflect my chosen syntax style, so that I can understand and fix issues quickly.

#### Acceptance Criteria

1. WHEN an error occurs in Go_Mode THEN THE System SHALL display variable names without `$` prefix
2. WHEN an error occurs in Go_Mode THEN THE System SHALL show `.` instead of `->` for property access
3. THE System SHALL include syntax mode information in stack traces
4. WHEN suggesting fixes THEN THE System SHALL use the appropriate syntax style

### Requirement 15: 扩展版本兼容性

**User Story:** As an extension developer, I want version compatibility checks, so that my extension works correctly with different interpreter versions.

#### Acceptance Criteria

1. THE Extension_API SHALL include version information
2. WHEN loading an extension THEN THE System SHALL verify API version compatibility
3. IF an extension requires a newer API version THEN THE System SHALL report incompatibility
4. THE Extension_API SHALL maintain backward compatibility within major versions
