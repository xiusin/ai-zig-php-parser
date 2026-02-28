# AOT 模糊测试报告
生成时间: 2026年 2月27日 星期五 22时39分23秒 CST

| # | 脚本路径 | 类别 | PHP结果 | 解释器结果 | AOT结果 | 状态 | 错误信息 |
|---|-----------|------|---------|-----------|---------|------|----------|
| 1 | test_1.php | 循环 | 750 | 750
=== PHP Interpreter Performance Statistics === | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=br setTerminator: block=1, term=br setTerminator: b |
| 2 | test_2.php | 表达式 | 55 | 55
=== PHP Interpreter Performance Statistics ===
 | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=cond_br setTerminator: block=1, term=br setTerminat |
| 3 | test_3.php | 数组 | 45 | 45
=== PHP Interpreter Performance Statistics ===
 | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=br setTerminator: block=1, term=br setTerminator: b |
| 4 | test_4.php | 递归 | 88 | -493
=== PHP Interpreter Performance Statistics == | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=cond_br setTerminator: block=1, term=ret setTermina |
| 5 | test_5.php | 全局变量 | 12345 | 11111
=== PHP Interpreter Performance Statistics = | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret setTerminator: block=0, term=br setTerminator:  |
| 6 | test_6.php | 字符串 | Hello World | Hello World
=== PHP Interpreter Performance Statis | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimization (mem2reg=true, |
| 7 | test_7.php | 数组 | 6 | InvalidOpcode: func='main' ip=14 opcode=0x7e(forea | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=br setTerminator: block=1, term=cond_br setTerminat |
| 8 | test_8.php | 表达式 | y>=x | y>=x
=== PHP Interpreter Performance Statistics == | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=cond_br setTerminator: block=1, term=cond_br setTer |
| 9 | test_9.php | 控制流 | two | 
=== PHP Interpreter Performance Statistics ===
Fu | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=switch_ setTerminator: block=3, term=br setTerminat |
| 10 | test_10.php | 循环 | 01234 | 
=== PHP Interpreter Performance Statistics ===
Fu | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=br setTerminator: block=1, term=br setTerminator: b |
| 11 | test_11.php | 表达式 | true | true
=== PHP Interpreter Performance Statistics == | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=cond_br setTerminator: block=1, term=br setTerminat |
| 12 | test_12.php | 运算符 | 176 | 53
=== PHP Interpreter Performance Statistics ===
 | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimization (mem2reg=true, |
| 13 | test_13.php | 数值 | 7.85 | 7.85
=== PHP Interpreter Performance Statistics == | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimization (mem2reg=true, |
| 14 | test_14.php | 数值 | 5-815 | 5-815
=== PHP Interpreter Performance Statistics = | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimization (mem2reg=true, |
| 15 | test_15.php | 数组 | 50,2,4,6,8 |  | [编译失败] | INTERP_ERROR | setTerminator: block=0, term=br setTerminator: block=1, term=br setTerminator: b |
| 16 | test_16.php | 函数 | 15 | 15
=== PHP Interpreter Performance Statistics ===
 | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret setTerminator: block=0, term=ret setTerminator: |
| 17 | test_17.php | 全局变量 | 6 | 0
=== PHP Interpreter Performance Statistics ===
F | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret setTerminator: block=0, term=ret Optimizer: Sta |
| 18 | test_18.php | 数组 | 6 | 6
=== PHP Interpreter Performance Statistics ===
F | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimization (mem2reg=true, |
| 19 | test_19.php | 字符串 | ace | 
=== PHP Interpreter Performance Statistics ===
Fu | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimization (mem2reg=true, |
| 20 | test_20.php | 类型 | 18 | 18.5
=== PHP Interpreter Performance Statistics == | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimization (mem2reg=true, |
| 21 | test_21.php | 运算符 | 20 | 20
=== PHP Interpreter Performance Statistics ===
 | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimization (mem2reg=true, |
| 22 | test_22.php | 运算符 | 757 | 656
=== PHP Interpreter Performance Statistics === | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimization (mem2reg=true, |
| 23 | test_23.php | 控制流 | two | 
=== PHP Interpreter Performance Statistics ===
Fu | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=br setTerminator: block=2, term=cond_br setTerminat |
| 24 | test_24.php | 数组 | 0 | 0
=== PHP Interpreter Performance Statistics ===
F | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimization (mem2reg=true, |
| 25 | test_25.php | 字符串 | 0empty | 0empty
=== PHP Interpreter Performance Statistics  | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=cond_br setTerminator: block=1, term=br setTerminat |
| 26 | test_26.php | 控制流 | 0-0 1-0 2-0  | 0-0 0-2 1-0 1-2 2-0 2-2 
=== PHP Interpreter Perfo | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=br setTerminator: block=1, term=cond_br setTerminat |
| 27 | test_27.php | 数组 | 10,7,3 | 1,7,3
=== PHP Interpreter Performance Statistics = | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimization (mem2reg=true, |
| 28 | test_28.php | 循环 | 012 | 012
=== PHP Interpreter Performance Statistics === | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=br setTerminator: block=1, term=cond_br setTerminat |
| 29 | test_29.php | 循环 | 0-10 1-9 2-8 3-7 4-6  | 
=== PHP Interpreter Performance Statistics ===
Fu | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=cond_br setTerminator: block=1, term=br setTerminat |
| 30 | test_30.php | 数组 | a1 b2 c3  | InvalidOpcode: func='main' ip=12 opcode=0x7e(forea | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=br setTerminator: block=1, term=cond_br setTerminat |
| 31 | test_31.php | 函数 | 15125 | 025
=== PHP Interpreter Performance Statistics === | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=6, term=ret setTerminator: block=0, term=ret Optimizer: Sta |
| 32 | test_32.php | 函数 | 6 | 6
=== PHP Interpreter Performance Statistics ===
F | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret setTerminator: block=0, term=ret Optimizer: Sta |
| 33 | test_33.php | 数组 | 6 | 6
=== PHP Interpreter Performance Statistics ===
F | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimization (mem2reg=true, |
| 34 | test_34.php | 数组 | yes | yes
=== PHP Interpreter Performance Statistics === | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=cond_br setTerminator: block=1, term=br setTerminat |
| 35 | test_35.php | 数组 | 2,4,6,8,10 | 2,4,6,8,10
=== PHP Interpreter Performance Statist | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=br setTerminator: block=1, term=br setTerminator: b |
| 36 | test_36.php | 表达式 | 1 | 1
=== PHP Interpreter Performance Statistics ===
F | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=cond_br setTerminator: block=1, term=br setTerminat |
| 37 | test_37.php | 数组 | 1two3.5 | 1two3.5
=== PHP Interpreter Performance Statistics | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimization (mem2reg=true, |
| 38 | test_38.php | 数组 | equal | not equal
=== PHP Interpreter Performance Statisti | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=cond_br setTerminator: block=1, term=br setTerminat |
| 39 | test_39.php | 数组 | 1234 | InvalidOpcode: func='main' ip=15 opcode=0x7e(forea | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=br setTerminator: block=1, term=cond_br setTerminat |
| 40 | test_40.php | 全局变量 | 100 | 1
=== PHP Interpreter Performance Statistics ===
F | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret setTerminator: block=0, term=ret Optimizer: Sta |
| 41 | test_41.php | 递归 | 120 | 120
=== PHP Interpreter Performance Statistics === | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=cond_br setTerminator: block=1, term=ret setTermina |
| 42 | test_42.php | 字符串 | Hello World, you are 25 years old. | Hello World, you are 25 years old.
=== PHP Interpr | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimization (mem2reg=true, |
| 43 | test_43.php | 数组 | tentwenty | tentwenty
=== PHP Interpreter Performance Statisti | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimization (mem2reg=true, |
| 44 | test_44.php | 运算符 | eqeqsneq | Bytecode execution failed: StackUnderflow, falling | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=cond_br setTerminator: block=1, term=br setTerminat |
| 45 | test_45.php | 运算符 | falsetrue | Bytecode execution failed: StackUnderflow, falling | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret setTerminator: block=0, term=cond_br setTermina |
| 46 | test_46.php | 数组 | 6 | 0
=== PHP Interpreter Performance Statistics ===
F | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimization (mem2reg=true, |
| 47 | test_47.php | 运算符 | defaultvalue | defaultvalue
=== PHP Interpreter Performance Stati | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimization (mem2reg=true, |
| 48 | test_48.php | 运算符 | 10-1 | InvalidOpcode: func='main' ip=2 opcode=0x48(spaces | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimization (mem2reg=true, |
| 49 | test_49.php | 变量 | world | 
=== PHP Interpreter Performance Statistics ===
Fu | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimization (mem2reg=true, |
| 50 | test_50.php | 函数 | 20 | 
=== PHP Interpreter Performance Statistics ===
Fu | [编译错误] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimization (mem2reg=true, |
| 51 | test_51.php | OOP | [PHP错误: 255] | 
=== PHP Interpreter Performance Statist | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 52 | test_52.php | OOP | [PHP错误: 255] | 
=== PHP Interpreter Performance Statist | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 53 | test_53.php | OOP | [PHP错误: 255] | 
=== PHP Interpreter Performance Statist | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 54 | test_54.php | OOP | [PHP错误: 255] | 
=== PHP Interpreter Performance Statist | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 55 | test_55.php | OOP | [PHP错误: 255] | 
=== PHP Interpreter Performance Statist | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 56 | test_56.php | OOP | [PHP错误: 255] | 
=== PHP Interpreter Performance Statist | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 57 | test_57.php | 数组 | [PHP错误: 255] | 
=== PHP Interpreter Performance Statist | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 58 | test_58.php | 数组 | [PHP错误: 255] | 
=== PHP Interpreter Performance Statist | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 59 | test_59.php | 数组 | [PHP错误: 255] | 
=== PHP Interpreter Performance Statist | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 60 | test_60.php | 数组 | [PHP错误: 255] | 
=== PHP Interpreter Performance Statist | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 61 | test_61.php | 函数 | [PHP错误: 255] | 
=== PHP Interpreter Performance Statist | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 62 | test_62.php | 函数 | [PHP错误: 255] | 
=== PHP Interpreter Performance Statist | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 63 | test_63.php | 函数 | [PHP错误: 255] | 
=== PHP Interpreter Performance Statist | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 64 | test_64.php | 函数 | [PHP错误: 255] | 
=== PHP Interpreter Performance Statist | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 65 | test_65.php | 函数 | [PHP错误: 255] | 
=== PHP Interpreter Performance Statist | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 66 | test_66.php | 函数 | [PHP错误: 255] | 
=== PHP Interpreter Performance Statist | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 67 | test_67.php | 函数 | [PHP错误: 255] | 
=== PHP Interpreter Performance Statist | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 68 | test_68.php | 函数 | [PHP错误: 255] | 
=== PHP Interpreter Performance Statist | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 69 | test_69.php | 函数 | [PHP错误: 255] | 
=== PHP Interpreter Performance Statist | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 70 | test_70.php | 函数 | [PHP错误: 255] | 
=== PHP Interpreter Performance Statist | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 71 | test_71.php | 函数 | [PHP错误: 255] | 
=== PHP Interpreter Performance Statist | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 72 | test_72.php | 函数 | Value: 42 | Value: 42
=== PHP Interpreter Performanc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 73 | test_73.php | 函数 | Num: 42, Str: test | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 74 | test_74.php | 函数 | [PHP错误: 255] | 
=== PHP Interpreter Performance Statist | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 75 | test_75.php | 函数 | [PHP错误: 255] | 
=== PHP Interpreter Performance Statist | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 76 | test_76.php | 函数 | [PHP错误: 255] | 
=== PHP Interpreter Performance Statist | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 77 | test_77.php | 函数 | [PHP错误: 255] | 
=== PHP Interpreter Performance Statist | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 78 | test_78.php | 常量 | 42 | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 79 | test_79.php | 常量 | 3.14 | 
=== PHP Interpreter Performance Statist | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 80 | test_80.php | 函数 | [PHP错误: 255] | 
=== PHP Interpreter Performance Statist | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 81 | test_81.php | 函数 | [PHP错误: 255] | 
=== PHP Interpreter Performance Statist | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 82 | test_82.php | 函数 | [PHP错误: 255] | 
=== PHP Interpreter Performance Statist | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 83 | test_83.php | 函数 | [PHP错误: 255] | 
=== PHP Interpreter Performance Statist | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 84 | test_84.php | 函数 | [PHP错误: 255] | 
=== PHP Interpreter Performance Statist | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 85 | test_85.php | 函数 | [PHP错误: 255] | 
=== PHP Interpreter Performance Statist | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 86 | test_86.php | 函数 | [PHP错误: 255] | 
=== PHP Interpreter Performance Statist | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 87 | test_87.php | 函数 | [PHP错误: 255] | 
=== PHP Interpreter Performance Statist | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 88 | test_88.php | 函数 | [PHP错误: 255] | 
=== PHP Interpreter Performance Statist | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 89 | test_89.php | 函数 | 51 | 51
=== PHP Interpreter Performance Stati | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 90 | test_90.php | 函数 | 53.14 | 53.14
=== PHP Interpreter Performance St | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 91 | test_91.php | 函数 | 43.14 | 43.14
=== PHP Interpreter Performance St | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 92 | test_92.php | 函数 | 34 | 34
=== PHP Interpreter Performance Stati | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 93 | test_93.php | 函数 | 1024 | 1024
=== PHP Interpreter Performance Sta | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 94 | test_94.php | 函数 | 4 | 4
=== PHP Interpreter Performance Statis | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 95 | test_95.php | 函数 | 70 | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 96 | test_96.php | 函数 | 69 | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 97 | test_97.php | 函数 | 1772203341 | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 98 | test_98.php | 函数 | 0.48549900 1772203341 | 0.+492986 1772203341
=== PHP Interpreter | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 99 | test_99.php | 函数 | 2026-02-27 | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 100 | test_100.php | 函数 | 1772289741 | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 101 | test_101.php | OOP | 10 | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 102 | test_102.php | OOP | Hi | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 103 | test_103.php | OOP | 7 | thread 7268429 panic: integer overflow
? | [编译失败] | INTERP_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 104 | test_104.php | OOP | John | Bytecode execution failed: TypeMismatch, | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 105 | test_105.php | OOP | 15 | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 106 | test_106.php | 数组 | 1,1,3,4,5 | 1,1,3,4,5
=== PHP Interpreter Performanc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 107 | test_107.php | 数组 | 5,4,3,2,1 | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 108 | test_108.php | 数组 | 1,2,3,4 | 1,2,3,4
=== PHP Interpreter Performance  | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 109 | test_109.php | 数组 | 1,1,2,3,4,5,6,98 | 1,1,2,3,4,5,6,98
=== PHP Interpreter Per | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 110 | test_110.php | 函数 | yesno | Bytecode execution failed: StackUnderflo | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 111 | test_111.php | 函数 | 11 | 11
=== PHP Interpreter Performance Stati | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 112 | test_112.php | 函数 | HELLO | HELLO
=== PHP Interpreter Performance St | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 113 | test_113.php | 函数 | hello | hello
=== PHP Interpreter Performance St | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 114 | test_114.php | 函数 | Hello PHP | Hello PHP
=== PHP Interpreter Performanc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 115 | test_115.php | 函数 | World | World
=== PHP Interpreter Performance St | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 116 | test_116.php | 函数 | 6 | 6
=== PHP Interpreter Performance Statis | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 117 | test_117.php | 函数 | a-b-c | a-b-c
=== PHP Interpreter Performance St | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 118 | test_118.php | 函数 | hello | hello
=== PHP Interpreter Performance St | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 119 | test_119.php | 函数 | Num: 42, Str: test | Num: 42, Str: test
=== PHP Interpreter P | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 120 | test_120.php | 函数 | yesno | Bytecode execution failed: StackUnderflo | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 121 | test_121.php | 函数 | intstr | Bytecode execution failed: StackUnderflo | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 122 | test_122.php | 函数 | emptynot empty | emptynot empty
=== PHP Interpreter Perfo | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 123 | test_123.php | 函数 | not setset | not setset
=== PHP Interpreter Performan | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 124 | test_124.php | 运算符 | 01 | 01
=== PHP Interpreter Performance Stati | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 125 | test_125.php | 运算符 | 11 | 00
=== PHP Interpreter Performance Stati | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 126 | test_126.php | 运算符 | 176 | 173
=== PHP Interpreter Performance Stat | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 127 | test_127.php | 运算符 | 205 | 
=== PHP Interpreter Performance Statist | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 128 | test_128.php | 运算符 | defaultvalue | defaultvalue
=== PHP Interpreter Perform | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 129 | test_129.php | 运算符 | 10-1 | InvalidOpcode: func='main' ip=2 opcode=0 | [编译错误] | AOT_COMPILE_ERROR |     |            [31m^[0m [1mtest_129.php[0m: [31merror |
| 130 | test_130.php | 运算符 | 1defaultdefault | Bytecode execution failed: StackUnderflo | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 131 | test_131.php | 运算符 | 1default | 1default
=== PHP Interpreter Performance | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 132 | test_132.php | 函数 | 102445434 | 102445434
=== PHP Interpreter Performanc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 133 | test_133.php | 函数 | 5166 | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 134 | test_134.php | 函数 | 1772203540 | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 135 | test_135.php | 函数 | 2026-02-27 14:45:40 | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 136 | test_136.php | 常量 | 42 | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 137 | test_137.php | 常量 | 3.14159 | 
=== PHP Interpreter Performance Statist | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 138 | test_138.php | 循环 | 30 | 30
=== PHP Interpreter Performance Stati | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 139 | test_139.php | 循环 | 0,2,4,6,8 |  | [编译失败] | INTERP_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 140 | test_140.php | 函数 | 16136 | 136
=== PHP Interpreter Performance Stat | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 141 | test_141.php | 全局变量 | 100 | 1
=== PHP Interpreter Performance Statis | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 142 | test_142.php | 变量 | 1020 | 1020
=== PHP Interpreter Performance Sta | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 143 | test_143.php | 数组 | 1100 | 11
=== PHP Interpreter Performance Stati | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 144 | test_144.php | 字符串 | originalmodified | originalmodified
=== PHP Interpreter Per | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 145 | test_145.php | 数组 | 15 | InvalidOpcode: func='main' ip=15 opcode= | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 146 | test_146.php | 数组 | 6 | InvalidOpcode: func='main' ip=14 opcode= | [编译错误] | AOT_COMPILE_ERROR |     |          [33m^[0m [1mtest_146.php[0m: [31merror[ |
| 147 | test_147.php | 循环 | 00 01 02 10 11 12 20 21 22  | 00 01 02 10 11 12 20 21 22 
=== PHP Inte | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 148 | test_148.php | 循环 | 01234 | 01234
=== PHP Interpreter Performance St | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 149 | test_149.php | 循环 | 01234 | 
=== PHP Interpreter Performance Statist | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 150 | test_150.php | 控制流 | positive | positive
=== PHP Interpreter Performance | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 151 | test_151.php | 控制流 | two | 
=== PHP Interpreter Performance Statist | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 152 | test_152.php | 控制流 | one | 
=== PHP Interpreter Performance Statist | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 153 | test_153.php | 表达式 | true | true
=== PHP Interpreter Performance Sta | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 154 | test_154.php | 字符串 | Result: 8 | Result: 8
=== PHP Interpreter Performanc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 155 | test_155.php | 数组 | 7 | 3
=== PHP Interpreter Performance Statis | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 156 | test_156.php | 递归 | 5050 | 5050
=== PHP Interpreter Performance Sta | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 157 | test_157.php | 表达式 | all ordered | all ordered
=== PHP Interpreter Performa | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 158 | test_158.php | 数组 | 77 | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 159 | test_159.php | 字符串 | hello php | hello php
=== PHP Interpreter Performanc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 160 | test_160.php | 控制流 | condition1 | condition1
=== PHP Interpreter Performan | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 161 | test_161.php | 数组 | 10 | 00
=== PHP Interpreter Performance Stati | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 162 | test_162.php | 函数 | 15 | 15
=== PHP Interpreter Performance Stati | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 163 | test_163.php | 数组 | Alice | Alice
=== PHP Interpreter Performance St | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 164 | test_164.php | 数组 | 54 | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 165 | test_165.php | 数组 | 123 | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 166 | test_166.php | 表达式 | 703 | 703
=== PHP Interpreter Performance Stat | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 167 | test_167.php | 字符串 | Hello World! | Hello World!
=== PHP Interpreter Perform | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 168 | test_168.php | 表达式 | [PHP错误: 255] | Bytecode execution failed: StackUnderflo | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 169 | test_169.php | 数组 | 2,4,6,8,10 | InvalidOpcode: func='main' ip=13 opcode= | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 170 | test_170.php | 控制流 | 0-0  | 0-0 1-0 2-0 
=== PHP Interpreter Perform | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 171 | test_171.php | 循环 | 621 | 621
=== PHP Interpreter Performance Stat | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 172 | test_172.php | 函数 | yesno | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 173 | test_173.php | 函数 | ababababab | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 174 | test_174.php | 函数 | *******abcabc**********abc**** | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 175 | test_175.php | 函数 | h,e,l,l,o | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 176 | test_176.php | 函数 | HellohELLO | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 177 | test_177.php | 函数 | 5d41402abc4b2a76b9719d911017c592aaf4c61d | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 178 | test_178.php | 函数 | 65A | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 179 | test_179.php | 函数 | 1,234,567.89 | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 180 | test_180.php | 函数 | This is a<br>long<br>string<br>that need | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 181 | test_181.php | 函数 | 2,3,4 | 2,3,4
=== PHP Interpreter Performance St | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 182 | test_182.php | 函数 | 1,10,20,4,5 | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 183 | test_183.php | 函数 | value,value,value,value,value | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 184 | test_184.php | 函数 | a,b,c1,2,3 | a,b,c1,2,3
=== PHP Interpreter Performan | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 185 | test_185.php | 函数 | 23 | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 186 | test_186.php | 函数 | ab | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 187 | test_187.php | 函数 | 1,3 | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 188 | test_188.php | 函数 | 2,4 | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 189 | test_189.php | 函数 | 1,2,3,4 | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 190 | test_190.php | 函数 | c | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 191 | test_191.php | 函数 | 1,5,3,2,4 | 2,5,3,4,1
=== PHP Interpreter Performanc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 192 | test_192.php | 函数 | 1,2,3,44,3,2,1 | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 193 | test_193.php | 函数 | 1,2,3,44,3,2,1 | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 194 | test_194.php | 函数 | img1.png,img10.png,img2.pngimg1.png,img2 | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 195 | test_195.php | 函数 | 1,2,3 | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 196 | test_196.php | 函数 | 6 | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 197 | test_197.php | 函数 | 1,2,3,0,0,0 | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 198 | test_198.php | 函数 | value,value,value | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 199 | test_199.php | 函数 | 6 | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 200 | test_200.php | 函数 | 32 | 32
=== PHP Interpreter Performance Stati | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 201 | test_201.php | 函数 | 5 | 5
=== PHP Interpreter Performance Statis | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 202 | test_202.php | 函数 | 7 | 7
=== PHP Interpreter Performance Statis | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 203 | test_203.php | 函数 | 15 | 0
=== PHP Interpreter Performance Statis | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 204 | test_204.php | 递归 | 21 | InvalidOpcode: func='sumArray' ip=3 opco | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 205 | test_205.php | OOP | John | Bytecode execution failed: UndefinedFunc | [编译错误] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warnings [1mtest |
| 206 | test_206.php | 基础 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 207 | test_207.php | 基础 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 208 | test_208.php | 基础 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 209 | test_209.php | 基础 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 210 | test_210.php | 基础 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 211 | test_211.php | 运算 | 15 | 15 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 212 | test_212.php | 运算 | 5 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 213 | test_213.php | 运算 | 50 | 50 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 214 | test_214.php | 运算 | 2 | 2 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 215 | test_215.php | 运算 | 1 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 216 | test_216.php | 运算 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 217 | test_217.php | 运算 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 218 | test_218.php | 运算 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 219 | test_219.php | 运算 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 220 | test_220.php | 比较 | yes | Bytecode execution failed: Sta | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 221 | test_221.php | 比较 | no | Bytecode execution failed: Sta | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 222 | test_222.php | 比较 | yes | Bytecode execution failed: Sta | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 223 | test_223.php | 比较 | yes | Bytecode execution failed: Sta | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 224 | test_224.php | 比较 | yes | Bytecode execution failed: Sta | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 225 | test_225.php | 比较 | yes | Bytecode execution failed: Sta | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 226 | test_226.php | 逻辑 | yes | Bytecode execution failed: Sta | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 227 | test_227.php | 逻辑 | yes | Bytecode execution failed: Sta | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 228 | test_228.php | 逻辑 | yes | Bytecode execution failed: Sta | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 229 | test_229.php | 位运算 | 1 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 230 | test_230.php | 位运算 | 7 | 7 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 231 | test_231.php | 位运算 | 6 | 3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 232 | test_232.php | 位运算 | -6 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 233 | test_233.php | 位运算 | 20 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 234 | test_234.php | 位运算 | 5 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 235 | test_235.php | 运算 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 236 | test_236.php | 运算 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 237 | test_237.php | 运算 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 238 | test_238.php | 运算 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 239 | test_239.php | 数组 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 240 | test_240.php | 数组 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 241 | test_241.php | 数组 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 242 | test_242.php | 数组 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 243 | test_243.php | 数组 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 244 | test_244.php | 数组 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 245 | test_245.php | 循环 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 246 | test_246.php | 循环 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 247 | test_247.php | 循环 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 248 | test_248.php | 循环 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 249 | test_249.php | 控制流 | yes | yes | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 250 | test_250.php | 控制流 | no | no | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 251 | test_251.php | 控制流 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 252 | test_252.php | 控制流 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 253 | test_253.php | 控制流 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 254 | test_254.php | 表达式 | yes | Bytecode execution failed: Sta | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 255 | test_255.php | 表达式 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 256 | test_256.php | 函数 | 42 | 42 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 257 | test_257.php | 函数 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 258 | test_258.php | 函数 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 259 | test_259.php | 函数 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 260 | test_260.php | 字符串 | hello world | hello world | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 261 | test_261.php | 字符串 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 262 | test_262.php | 字符串 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 263 | test_263.php | 类型 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 264 | test_264.php | 类型 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 265 | test_265.php | 类型 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 266 | test_266.php | 运算符 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 267 | test_267.php | 运算符 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 268 | test_268.php | 控制流 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 269 | test_269.php | 控制流 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 270 | test_270.php | 全局 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 271 | test_271.php | 全局 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 272 | test_272.php | 函数 | PHP Parse error:  syntax error | Bytecode execution failed: Und | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 273 | test_273.php | 表达式 | 7 | 7 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 274 | test_274.php | 表达式 | 1 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 275 | test_275.php | 表达式 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 276 | test_276.php | 循环 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 277 | test_277.php | 数组 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 278 | test_278.php | 递归 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 279 | test_279.php | 函数 | 5 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 280 | test_280.php | 函数 | 4 | 4 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 281 | test_281.php | 函数 | 3 | 3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 282 | test_282.php | 函数 | 4 | 4 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 283 | test_283.php | 函数 | 5 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 284 | test_284.php | 函数 | 1 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 285 | test_285.php | 边界 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 286 | test_286.php | 边界 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 287 | test_287.php | 边界 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 288 | test_288.php | 边界 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 289 | test_289.php | 函数 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 290 | test_290.php | 函数 | PHP Parse error:  syntax error |  | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 291 | test_291.php | 基础 | 123 | 123 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 292 | test_292.php | 基础 | 3.14 | 3.14 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 293 | test_293.php | 基础 | hello | hello | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 294 | test_294.php | 基础 | 1 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 295 | test_295.php | 基础 |  |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 296 | test_296.php | 运算 | 15 | 15 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 297 | test_297.php | 运算 | 5 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 298 | test_298.php | 运算 | 50 | 50 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 299 | test_299.php | 运算 | 2 | 2 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 300 | test_300.php | 运算 | 1 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 301 | test_301.php | 赋值 | 15 | 15 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 302 | test_302.php | 赋值 | 5 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 303 | test_303.php | 赋值 | 50 | 50 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 304 | test_304.php | 赋值 | hello world | hello world | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 305 | test_305.php | 比较 | yes | Bytecode execution failed: Sta | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 306 | test_306.php | 比较 | no | Bytecode execution failed: Sta | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 307 | test_307.php | 比较 | eq | Bytecode execution failed: Sta | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 308 | test_308.php | 比较 | yes | Bytecode execution failed: Sta | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 309 | test_309.php | 逻辑 | yes | Bytecode execution failed: Sta | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 310 | test_310.php | 逻辑 | yes | Bytecode execution failed: Sta | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 311 | test_311.php | 逻辑 | yes | Bytecode execution failed: Sta | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 312 | test_312.php | 位运算 | 1 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 313 | test_313.php | 位运算 | 7 | 7 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 314 | test_314.php | 位运算 | 6 | 3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 315 | test_315.php | 位运算 | -6 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 316 | test_316.php | 运算 | 6 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 317 | test_317.php | 运算 | 5 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 318 | test_318.php | 运算 | 4 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 319 | test_319.php | 运算 | 5 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 320 | test_320.php | 数组 | 1 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 321 | test_321.php | 数组 | 10 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 322 | test_322.php | 数组 | 2 | 3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 323 | test_323.php | 数组 | 1 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 324 | test_324.php | 循环 | 01234 | 01234 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 325 | test_325.php | 循环 | 01234 | 01234 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 326 | test_326.php | 循环 | 123 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 327 | test_327.php | 控制流 | yes | yes | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 328 | test_328.php | 控制流 | no | no | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 329 | test_329.php | 表达式 | yes | Bytecode execution failed: Sta | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 330 | test_330.php | 表达式 | pos | pos | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 331 | test_331.php | 函数 | 42 | 42 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 332 | test_332.php | 函数 | 7 | 7 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 333 | test_333.php | 函数 | 5 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 334 | test_334.php | 字符串 | hello world | hello world | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 335 | test_335.php | 字符串 | h |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 336 | test_336.php | 类型 | 8 | 8 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 337 | test_337.php | 类型 | 5 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 338 | test_338.php | 运算符 | default | default | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 339 | test_339.php | 控制流 | 0134 | 0134 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 340 | test_340.php | 控制流 | 01 | 01 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 341 | test_341.php | 全局 | 1 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 342 | test_342.php | 函数 | 12 | 11 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 343 | test_343.php | 函数 | 5 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 344 | test_344.php | 函数 | 4 | 4 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 345 | test_345.php | 函数 | 3 | 3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 346 | test_346.php | 函数 | 4 | 4 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 347 | test_347.php | 函数 | 5 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 348 | test_348.php | 函数 | 1 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 349 | test_349.php | 边界 | 0 | 0 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 350 | test_350.php | 边界 | -1 | -1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 351 | test_351.php | 边界 | 0 | 0 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 352 | test_352.php | 边界 | 0 | 0 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 353 | test_353.php | 函数 | 1,2,3,4 | 1,2,3,4 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 354 | test_354.php | 表达式 | 5 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 355 | test_355.php | 数组 | 15 | 15 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 356 | test_356.php | 字符串 | hello |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 357 | test_357.php | 数组 | 0,1,4,9,16,25,36,49,64,81 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 358 | test_358.php | 递归 | 120 | 120 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 359 | test_359.php | 循环 | 55 | 55 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 360 | test_360.php | 数组 | 1,1,2,3,4,5,6,9 | 1,1,2,3,4,5,6,9 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 361 | test_361.php | 函数 | HELLO WORLD | HELLO WORLD | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 362 | test_362.php | 函数 | hello world | hello world | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 363 | test_363.php | 函数 | 5 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 364 | test_364.php | 函数 | hello | hello | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 365 | test_365.php | 函数 | 2 | 2 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 366 | test_366.php | 函数 | hello php | hello php | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 367 | test_367.php | 函数 | a-b-c | a-b-c | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 368 | test_368.php | 函数 | Array
(
    [0] => a
    [1] = | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 369 | test_369.php | 函数 | 5 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 370 | test_370.php | 函数 | integer | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 371 | test_371.php | 函数 | 123 | 123 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 372 | test_372.php | 函数 | 123 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 373 | test_373.php | 函数 | 123 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 374 | test_374.php | 函数 | array | array | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 375 | test_375.php | 函数 | int | int | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 376 | test_376.php | 函数 | string | string | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 377 | test_377.php | 函数 | empty | empty | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 378 | test_378.php | 函数 | set | set | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 379 | test_379.php | 常量 | yes | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 380 | test_380.php | 常量 | 8.4.8 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 381 | test_381.php | 函数 | 1,2,3,4,5 | 1,2,3,4,5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 382 | test_382.php | 函数 | 6 | 6 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 383 | test_383.php | 函数 | 6 | 6 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 384 | test_384.php | 表达式 | 10 | 10 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 385 | test_385.php | 函数 | 1 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 386 | test_386.php | 函数 | 5 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 387 | test_387.php | 函数 | 2 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 388 | test_388.php | 函数 | 2 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 389 | test_389.php | 函数 | 2 | 2 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 390 | test_390.php | 函数 | yes | yes | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 391 | test_391.php | 函数 | yes | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 392 | test_392.php | 函数 | 15 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 393 | test_393.php | 函数 | 30 | 30 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 394 | test_394.php | 函数 | 9 | Array | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 395 | test_395.php | 函数 | 1 | Array | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 396 | test_396.php | 函数 | 1024 | 1024 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 397 | test_397.php | 函数 | 4 | 4 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 398 | test_398.php | 函数 | 99 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 399 | test_399.php | 函数 | 1 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 400 | test_400.php | 函数 | 1772204298 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 401 | test_401.php | 数组 | 3 | 3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 402 | test_402.php | 数组 | 3 | 3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 403 | test_403.php | 字符串 | 01 | 01 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 404 | test_404.php | 边界 | 9.2233720368548E+18 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 405 | test_405.php | 边界 | -9223372036854775808 | -1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 406 | test_406.php | 函数 | 3 | 3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 407 | test_407.php | 函数 | 2,4,6,8,10 | 1,2,3,4,5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 408 | test_408.php | 函数 | 15 | 15 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 409 | test_409.php | 函数 | 120 | 16 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 410 | test_410.php | 函数 | 385 | 55 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 411 | test_411.php | 函数 | 123 | 0 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 412 | test_412.php | 函数 | 3.14 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 413 | test_413.php | 比较 | empty | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 414 | test_414.php | 比较 | null | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 415 | test_415.php | 比较 | eq | neq | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 416 | test_416.php | 比较 | same | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 417 | test_417.php | 字符串 | HEllo | hello | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 418 | test_418.php | 表达式 | 4 | 3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 419 | test_419.php | 表达式 | 8 | 9 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 420 | test_420.php | 表达式 | 7 | 7 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 421 | test_421.php | 表达式 | 9 | 9 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 422 | test_422.php | 表达式 | 1 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 423 | test_423.php | 表达式 | 512 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 424 | test_424.php | 表达式 | 5 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 425 | test_425.php | 循环 | 0=1 1=2 2=3  | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 426 | test_426.php | 循环 | a=1 b=2  | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 427 | test_427.php | 控制流 | 013 | 013 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 428 | test_428.php | 控制流 | one |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 429 | test_429.php | 循环 | 1 2 3  | 1 2 3  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 430 | test_430.php | 循环 | 012 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 431 | test_431.php | 函数 | 16136 | 136 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 432 | test_432.php | 函数 | 200 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 433 | test_433.php | 函数 | PHP Warning:  Undefined variab | 1 | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 434 | test_434.php | 函数 | 1 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 435 | test_435.php | 函数 | 3 | 3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 436 | test_436.php | 数组 | 10 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 437 | test_437.php | 数组 | 1 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 438 | test_438.php | OOP | 123 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 439 | test_439.php | 函数 | value | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 440 | test_440.php | 函数 | 3 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 441 | test_441.php | 函数 | xxxxx | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 442 | test_442.php | 函数 | 3 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 443 | test_443.php | 函数 | 3 | 3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 444 | test_444.php | 函数 | Array
(
    [1] => 1
    [2] = | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 445 | test_445.php | 字符串 | hello world! | hello world! | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 446 | test_446.php | 函数 | 3,2,1 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 447 | test_447.php | 函数 | 0 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 448 | test_448.php | 函数 | 43 | 43 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 449 | test_449.php | 函数 | 12 | 12 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 450 | test_450.php | 函数 | 0,1,2 | 0,1,2 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 451 | test_451.php | 函数 | 1,2,3 | 1,2,3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 452 | test_452.php | 运算符 | default | default | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 453 | test_453.php | 函数 | PHP Fatal error:  Uncaught Err | Bytecode execution failed: Und | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 454 | test_454.php | 函数 | Hello | Hello | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 455 | test_455.php | 函数 | HELLO | HELLO | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 456 | test_456.php | 函数 | hello | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 457 | test_457.php | 函数 | hellohellohello | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 458 | test_458.php | 函数 | *****hello | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 459 | test_459.php | 函数 | hello***** | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 460 | test_460.php | 函数 | **hello*** | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 461 | test_461.php | 函数 | Array
(
    [0] => h
    [1] = | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 462 | test_462.php | 函数 | bca | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 463 | test_463.php | 函数 | olleh | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 464 | test_464.php | 函数 | helloHELLO | helloHELLO | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 465 | test_465.php | 函数 | a,;b,;c,;d,;e | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 466 | test_466.php | 函数 | 3 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 467 | test_467.php | 函数 | heLLo | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 468 | test_468.php | 函数 | 2 | 2 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 469 | test_469.php | 函数 | 10 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 470 | test_470.php | 函数 | 0 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 471 | test_471.php | 函数 | bca | bac | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 472 | test_472.php | 函数 | 3,2,1 | 3,2,1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 473 | test_473.php | 函数 | a,b | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 474 | test_474.php | 函数 | 1,2 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 475 | test_475.php | 函数 | 2,1 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 476 | test_476.php | 函数 | b,a | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 477 | test_477.php | 函数 | PHP Warning:  Array to string  | Array | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 478 | test_478.php | 函数 | 5 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 479 | test_479.php | 函数 | 1,4,5 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 480 | test_480.php | 函数 | 12 | 12 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 481 | test_481.php | 函数 | 6 | 2 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 482 | test_482.php | 函数 | 30 | 55 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 483 | test_483.php | 函数 | Number: 123, String: hello | Number: 123, String: hello | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 484 | test_484.php | 函数 | Num: 42, Str: test | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 485 | test_485.php | 函数 | 255 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 486 | test_486.php | 函数 | ff | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 487 | test_487.php | 函数 | 10 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 488 | test_488.php | 函数 | 63 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 489 | test_489.php | 函数 | 255 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 490 | test_490.php | 函数 | ABC | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 491 | test_491.php | 函数 | 131 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 492 | test_492.php | 函数 | 1,234,567.89 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 493 | test_493.php | 函数 | This<br>is a<br>test | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 494 | test_494.php | 递归 | 55 | -510 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 495 | test_495.php | 函数 | 15 | InvalidOpcode: func='sum' ip=3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 496 | test_496.php | 函数 | 5 | InvalidOpcode: func='maxArr' i | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 497 | test_497.php | 函数 | prime | Bytecode execution failed: Sta | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 498 | test_498.php | 函数 | olleh |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 499 | test_499.php | 函数 | Array
(
    [h] => 1
    [e] = | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 500 | test_500.php | 循环 | 5050 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 501 | test_501.php | 循环 | 385 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 502 | test_502.php | 循环 | 3628800 | 3628800 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 503 | test_503.php | 表达式 | 21 | 21 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 504 | test_504.php | 循环 | 6 | 6 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 505 | test_505.php | 循环 | *
**
***
****
***** | * | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 506 | test_506.php | 数组 | 1 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 507 | test_507.php | 数组 | 9 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 508 | test_508.php | 字符串 | 4 | 4 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 509 | test_509.php | 字符串 | palindrome | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 510 | test_510.php | 函数 | 246 | 123 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 511 | test_511.php | 函数 | 15 | 15 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 512 | test_512.php | 函数 | 2,4 | 1,2,3,4,5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 513 | test_513.php | 函数 | 1,2,3,4,5,6 | 1,2,3,4,5,6 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 514 | test_514.php | 数组 | 10 | 10 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 515 | test_515.php | 函数 | 3 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 516 | test_516.php | 数组 | 3 | 3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 517 | test_517.php | 函数 | 7.4161984870957 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 518 | test_518.php | 函数 | 6 | 6 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 519 | test_519.php | 函数 | 12 | 12 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 520 | test_520.php | 函数 | 110 | 210 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 521 | test_521.php | 字符串 | abc | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 522 | test_522.php | 数组 | 7 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 523 | test_523.php | 函数 | not | not | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 524 | test_524.php | 函数 | a | a | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 525 | test_525.php | 函数 | 1 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 526 | test_526.php | 函数 | 2 | 2 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 527 | test_527.php | 函数 | 12 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 528 | test_528.php | 函数 | 120 | 120 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 529 | test_529.php | 表达式 | yes | yes | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 530 | test_530.php | 函数 | not empty | not empty | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 531 | test_531.php | 函数 | not set | not set | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 532 | test_532.php | 函数 | 12 | 15 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 533 | test_533.php | 函数 | ********** | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 534 | test_534.php | 函数 | llo | llo | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 535 | test_535.php | 函数 | 9 | 9 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 536 | test_536.php | 函数 | 1 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 537 | test_537.php | 函数 | 2 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 538 | test_538.php | 循环 | 499500 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 539 | test_539.php | 循环 | 5050 | 5050 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 540 | test_540.php | 循环 | 1048576 | 1048576 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 541 | test_541.php | 循环 | 408 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 542 | test_542.php | 递归 | 40320 | 40320 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 543 | test_543.php | 递归 | 144 | -2046 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 544 | test_544.php | 表达式 | small | small | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 545 | test_545.php | 循环 | 15 | 15 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 546 | test_546.php | 循环 | 45 | 0 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 547 | test_547.php | 函数 | 1,2,3,4,5 | 1,2,3,4,5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 548 | test_548.php | 函数 | 5,4,3,2,1 | 5,4,3,2,1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 549 | test_549.php | 函数 | a,b,c | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 550 | test_550.php | 函数 | 2,3,4 | 2,3,4 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 551 | test_551.php | 函数 | 1,2,3 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 552 | test_552.php | 函数 | 120 | 16 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 553 | test_553.php | 函数 | HELLOhello | HELLOhello | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 554 | test_554.php | 函数 | 1 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 555 | test_555.php | 函数 | 2 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 556 | test_556.php | 函数 | ***abc**** | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 557 | test_557.php | 函数 | 55 | 15 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 558 | test_558.php | 函数 | 8 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 559 | test_559.php | 函数 | 3,2 | 3,2 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 560 | test_560.php | 函数 | 1,2,3,4,5 | 1,2,3,4,5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 561 | test_561.php | 函数 | 1,2 | 1,2 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 562 | test_562.php | 函数 | 0,1,2,3 | 0,1,2,3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 563 | test_563.php | 函数 | 3 | 3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 564 | test_564.php | 函数 | 25 | 55 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 565 | test_565.php | 函数 | 123456 | 123456 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 566 | test_566.php | 函数 | 34 | 34 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 567 | test_567.php | 函数 | 43 | 43 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 568 | test_568.php | 函数 | 51 | 51 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 569 | test_569.php | 函数 | 1,1,2,3,4,5,6,9 | 1,1,2,3,4,5,6,9 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 570 | test_570.php | 函数 | 1,2,3 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 571 | test_571.php | 函数 | 2,4,6,8,10 | 1,2,3,4,5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 572 | test_572.php | 函数 | 120 | 120 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 573 | test_573.php | 函数 | 5 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 574 | test_574.php | 函数 | 2 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 575 | test_575.php | 函数 | hello | hello | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 576 | test_576.php | 函数 | HELLO | HELLO | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 577 | test_577.php | 函数 | Hello | Hello | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 578 | test_578.php | 函数 | Hello World | Hello World | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 579 | test_579.php | 函数 | 1-2-3 | 1-2-3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 580 | test_580.php | 函数 | 3 | 3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 581 | test_581.php | 函数 | 2 | 2 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 582 | test_582.php | 函数 | hexxo | hexxo | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 583 | test_583.php | 函数 | 5 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 584 | test_584.php | 函数 | 5d41402abc4b2a76b9719d911017c5 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 585 | test_585.php | 函数 | aaf4c61ddcc5e8a2dabede0f3b482c | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 586 | test_586.php | 函数 | 907060870 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 587 | test_587.php | 函数 | 65A | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 588 | test_588.php | 函数 | 616263abc | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 589 | test_589.php | 函数 | 3 | 3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 590 | test_590.php | 函数 | ell | ell | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 591 | test_591.php | 函数 | ll | ll | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 592 | test_592.php | 函数 | found | found | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 593 | test_593.php | 函数 | yes | yes | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 594 | test_594.php | 函数 | yes | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 595 | test_595.php | 表达式 | 7 | 7 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 596 | test_596.php | 数组 | 3,4 | 5,5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 597 | test_597.php | 函数 | 3 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 598 | test_598.php | 表达式 | 1 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 599 | test_599.php | 函数 | 52.2360679774998 | 52.23606797749979 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 600 | test_600.php | 函数 | 25681 | 25681 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 601 | test_601.php | 函数 | 2PHP Fatal error:  Uncaught Er | Bytecode execution failed: Und | [编译失败] | PHP_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 602 | test_602.php | 函数 | 2.7182818284593.1415926535898 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 603 | test_603.php | 函数 | 3.14 | 3.14 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 604 | test_604.php | 循环 | 15 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 1 warning |
| 605 | test_605.php | 数组 | a=1,b=2,c=3, | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 606 | test_606.php | 循环 | 0,1,3,4, | 0,1,3,4, | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 607 | test_607.php | 循环 | 0,1,2, | 0,1,2, | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 608 | test_608.php | 循环 | 0,1,2,3,4, | 0,1,2,3,4, | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 609 | test_609.php | 循环 | 0,1,2, |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 610 | test_610.php | 函数 | 10,9,8,7,6,5,4,3,2,1 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 611 | test_611.php | 函数 | 66 | 66 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 612 | test_612.php | 函数 | abcabcabc | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 613 | test_613.php | 函数 | 2 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 614 | test_614.php | 函数 | llo | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 615 | test_615.php | 函数 | 32 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 616 | test_616.php | 循环 | 15 | 15 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 617 | test_617.php | 函数 | 15 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 618 | test_618.php | 函数 | 55 | 15 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 619 | test_619.php | 函数 | hello worldhello world    hell | hello worldhello world    hell | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 620 | test_620.php | 函数 | hello | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 621 | test_621.php | 函数 | olleh | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 622 | test_622.php | 函数 | Array
(
    [0] => 1
    [1] = | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 623 | test_623.php | 函数 | 9,8,5,3,1 | 9,8,5,3,1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 624 | test_624.php | 函数 | a,b,c | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 625 | test_625.php | 函数 | 1,2,3 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 626 | test_626.php | 函数 | no | no | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 627 | test_627.php | 函数 | no | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 628 | test_628.php | 表达式 | 0,1,2 | 0,1,2 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 629 | test_629.php | 表达式 | 1,2,2 | 0,0,0 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 630 | test_630.php | 表达式 | 6,6 | 5,5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 631 | test_631.php | 表达式 | 6,5 | 6,5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 632 | test_632.php | 数组 | 4 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 633 | test_633.php | 数组 | 1,3 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 634 | test_634.php | 函数 | 1,4,5 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 635 | test_635.php | 函数 | 6 | 6 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 636 | test_636.php | 函数 | 1,2,3,4,5,6 | 1,2,3,4,5,6 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 637 | test_637.php | 函数 | 5,1 | Array,Array | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 638 | test_638.php | 函数 | 1,2,3,4,5 | 1,2,3,4,5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 639 | test_639.php | 函数 | a,m,z | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 640 | test_640.php | 函数 | hello----- | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 641 | test_641.php | 函数 | -----hello | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 642 | test_642.php | 函数 | abcabc | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 643 | test_643.php | 函数 | hello-world | hello-world | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 644 | test_644.php | 函数 | 3,4,5 | 1,2,3,4,5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 645 | test_645.php | 函数 | 10,20,30,40,50 | 1,2,3,4,5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 646 | test_646.php | 函数 | 6 | 6 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 647 | test_647.php | 循环 | 6 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 648 | test_648.php | 表达式 | yes | yes | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 649 | test_649.php | 数组 | 21 | 21 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 650 | test_650.php | 数组 | 21 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 651 | test_651.php | 数组 | 31,32,33 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 652 | test_652.php | 数组 | Alice | Alice | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 653 | test_653.php | 函数 | 40 | 55 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 654 | test_654.php | 函数 | 30 | 15 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 655 | test_655.php | 递归 | 15 | Bytecode execution failed: Sta | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 656 | test_656.php | 递归 | 3628800 | 3628800 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 657 | test_657.php | 函数 | 2,4,6,8,10 | 1,2,3,4,5,6,7,8,9,10 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 658 | test_658.php | 表达式 | 8.5 | 8.5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 659 | test_659.php | 循环 | 1*1=1 1*2=2 1*3=3 
2*1=2 2*2=4 | 1*1=1 1*2=2 1*3=3  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 660 | test_660.php | 函数 | 3 | 3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 661 | test_661.php | 字符串 | x=10, y=20 | x=10, y=20 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 662 | test_662.php | 字符串 | Hello, World! | Hello, World! | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 663 | test_663.php | 表达式 | 35 | 35 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 664 | test_664.php | 表达式 | -3 | -3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 665 | test_665.php | 循环 | 735 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 666 | test_666.php | 函数 | 34 | 34 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 667 | test_667.php | 函数 | 32 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 668 | test_668.php | 函数 | e-d-c-b-a | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 669 | test_669.php | 函数 | 1,2,3,5,8,9 | 1,2,3,5,8,9 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 670 | test_670.php | 函数 | 1,2,3,4,5,6,9 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 671 | test_671.php | 函数 | 51 | ArrayArray | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 672 | test_672.php | 函数 | 55 | 55 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 673 | test_673.php | 函数 | 104111 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 674 | test_674.php | 函数 | D | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 675 | test_675.php | 函数 | 9 | 15 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 676 | test_676.php | 函数 | 29160 | 1307674368000 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 677 | test_677.php | 函数 | 55 | 15 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 678 | test_678.php | 函数 | 43 | 43 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 679 | test_679.php | 函数 | abcABC | abcABC | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 680 | test_680.php | 函数 | yes | yes | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 681 | test_681.php | 函数 | 10 | 10 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 682 | test_682.php | 函数 | 12 | 12 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 683 | test_683.php | 表达式 | 8 | 8 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 684 | test_684.php | 表达式 | 7 | 7 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 685 | test_685.php | 表达式 | 10 | 10 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 686 | test_686.php | 表达式 | 25 | 25 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 687 | test_687.php | 表达式 | 2 | 2 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 688 | test_688.php | 表达式 | 10,5 | 10,5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 689 | test_689.php | 数组 | 1 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 690 | test_690.php | 函数 | 130 | 130 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 691 | test_691.php | 函数 | 456789 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 692 | test_692.php | 表达式 | 15 | 15 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 693 | test_693.php | 数组 | 4 | 4 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 694 | test_694.php | 条件 | small | small | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 695 | test_695.php | 条件 | lt | lt | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 696 | test_696.php | 控制流 | other |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 697 | test_697.php | 控制流 | B |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 698 | test_698.php | 循环 | 1,2,4,5, | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 699 | test_699.php | 循环 | 1,2,3, | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 700 | test_700.php | 循环 | 55 | 55 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 701 | test_701.php | 循环 | 120 | 120 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 702 | test_702.php | 函数 | 1,2,3,4,5 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 703 | test_703.php | 函数 | -----hello----- | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 704 | test_704.php | 表达式 | default | default | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 705 | test_705.php | 表达式 | 5 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 706 | test_706.php | 表达式 | 1 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 707 | test_707.php | 表达式 | default | default | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 708 | test_708.php | 表达式 | 0 | 0 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 709 | test_709.php | 表达式 | -1 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 2 errors, 0 warning |
| 710 | test_710.php | 表达式 | 0 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 2 errors, 0 warning |
| 711 | test_711.php | 表达式 | 1 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 2 errors, 0 warning |
| 712 | test_712.php | 函数 | 12 | 15 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 713 | test_713.php | 函数 | 55 | 15 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 714 | test_714.php | 函数 | has digits | has digits | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 715 | test_715.php | 函数 | h*ll* | h*ll* | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 716 | test_716.php | 函数 | 5 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 717 | test_717.php | 函数 | 5 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 718 | test_718.php | 循环 | 6 | 7 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 719 | test_719.php | 循环 | 12 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 720 | test_720.php | 循环 | 128 | 128 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 721 | test_721.php | 循环 | 0.78125 | 0.78125 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 722 | test_722.php | 函数 | 1 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 723 | test_723.php | 函数 | 9 | 9 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 724 | test_724.php | 函数 | 7 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 725 | test_725.php | 函数 | 120 | 120 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 726 | test_726.php | 函数 | HEL | HEL | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 727 | test_727.php | 函数 | 2 | 0 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 728 | test_728.php | 循环 | 55 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 729 | test_729.php | 函数 | 5 | 15 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 730 | test_730.php | 函数 | 1 | 1014 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 731 | test_731.php | 函数 | 3 | 3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 732 | test_732.php | 循环 | 25 | 25 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 1 warning |
| 733 | test_733.php | 函数 | h,e,l,l,o | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 734 | test_734.php | 函数 | hellohellohellohellohello | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 735 | test_735.php | 函数 | 225 | 15 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 736 | test_736.php | 表达式 | true |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 737 | test_737.php | 表达式 | true |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 738 | test_738.php | 表达式 | true | true | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 739 | test_739.php | 表达式 | 1 7 | 1 7 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 740 | test_740.php | 表达式 | 40 5 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 741 | test_741.php | 表达式 | 6 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 742 | test_742.php | 函数 | 2,4,6 | 1,2,3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 743 | test_743.php | 函数 | 1,2,4,5 | 1,2,3,4,5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 744 | test_744.php | 函数 | 00000abc | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 745 | test_745.php | 函数 | 00abc000 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 746 | test_746.php | 函数 | 1,2,3,1,2,3 | 1,2,3,1,2,3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 747 | test_747.php | 函数 | 7 | 7 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 748 | test_748.php | 函数 | 5 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 749 | test_749.php | 函数 | 13 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 750 | test_750.php | 循环 | 10 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 751 | test_751.php | 循环 | 12 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 752 | test_752.php | 函数 | 3 | 3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 753 | test_753.php | 函数 | PHP Warning:  array_sum(): Add | 0 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 754 | test_754.php | 函数 | 12345 | 15 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 755 | test_755.php | 函数 | 2,2 | 2,2 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 756 | test_756.php | 函数 | 1,2,4,5 | 1,2,4,5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 757 | test_757.php | 函数 | 24 | 55 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 758 | test_758.php | 函数 | 311 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 759 | test_759.php | 函数 | 15 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 760 | test_760.php | 表达式 | 2 | 2 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 761 | test_761.php | 函数 | found | found | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 762 | test_762.php | 函数 | 1 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 763 | test_763.php | 表达式 | big | big | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 764 | test_764.php | 控制流 | two |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 765 | test_765.php | 控制流 | B |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 766 | test_766.php | 控制流 | PHP Warning:  Undefined variab | Bytecode execution failed: Sta | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 767 | test_767.php | 循环 | 15 | 15 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 768 | test_768.php | 函数 | 6 | 6 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 769 | test_769.php | 函数 | 1,3,5 | 1,2,3,4,5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 770 | test_770.php | 函数 | 1,4,9,16,25 | 1,2,3,4,5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 771 | test_771.php | 函数 | 6 | 6 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 772 | test_772.php | 函数 | 6 | 6 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 773 | test_773.php | 函数 | 5 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 774 | test_774.php | 函数 | HELLO | HELLO | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 775 | test_775.php | 函数 | hello | hello | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 776 | test_776.php | 函数 | Hello World | Hello World | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 777 | test_777.php | 函数 | Hello | Hello | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 778 | test_778.php | 函数 | hELLO | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 779 | test_779.php | 函数 | olleh | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 780 | test_780.php | 函数 | 3 | 3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 781 | test_781.php | 函数 | a-b-c | a-b-c | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 782 | test_782.php | 函数 | yes | yes | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 783 | test_783.php | 函数 | yes | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 784 | test_784.php | 函数 | 1,3,5,8 | 1,3,5,8 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 785 | test_785.php | 函数 | 8,5,3,1 | 8,5,3,1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 786 | test_786.php | 函数 | a,b,c | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 787 | test_787.php | 函数 | 1,2,3 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 788 | test_788.php | 函数 | PHP Warning:  Array to string  | Array | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 789 | test_789.php | 函数 | 1,4,5 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 790 | test_790.php | 函数 | 1,2,3,4 | 1,2,3,4 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 791 | test_791.php | 函数 | PHP Warning:  Array to string  | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 792 | test_792.php | 函数 | 9 | 15 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 793 | test_793.php | 函数 | 3 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 794 | test_794.php | 函数 | 12 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 795 | test_795.php | 函数 | 3 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 796 | test_796.php | 表达式 | 1 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 797 | test_797.php | 函数 | 5 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 798 | test_798.php | 函数 | 34 | 34 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 799 | test_799.php | 函数 | 4 | 4 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 800 | test_800.php | 函数 | 256 | 256 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 801 | test_801.php | 函数 | 2.8284271247462 | 2.8284271247461903 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 802 | test_802.php | 函数 | 51 | ArrayArray | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 803 | test_803.php | 表达式 | 2 | 2 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 804 | test_804.php | 表达式 | 2 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 805 | test_805.php | 表达式 | 8 | 8 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 806 | test_806.php | 表达式 | 2 | 2 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 807 | test_807.php | 表达式 | 15 | 15 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 808 | test_808.php | 表达式 | 4 | 4 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 809 | test_809.php | 表达式 | 1 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 810 | test_810.php | 表达式 | true |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 811 | test_811.php | 表达式 | false |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 812 | test_812.php | 表达式 | true | true | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 813 | test_813.php | 表达式 | 1 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 814 | test_814.php | 表达式 | 7 | 7 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 815 | test_815.php | 表达式 | 6 | 3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 816 | test_816.php | 表达式 | 32 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 817 | test_817.php | 表达式 | 4 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 818 | test_818.php | 函数 | 3 | 3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 819 | test_819.php | 函数 | 55 | 55 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 820 | test_820.php | 循环 | 110 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 821 | test_821.php | 循环 | 45 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 822 | test_822.php | 循环 | 15 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 823 | test_823.php | 循环 | 64 | 64 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 824 | test_824.php | 循环 | 1 | Bytecode execution failed: Sta | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 825 | test_825.php | 循环 | 1 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 826 | test_826.php | 循环 | 9 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 827 | test_827.php | 表达式 | 9 | 9 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 828 | test_828.php | 表达式 | 600 | 600 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 829 | test_829.php | 表达式 | 6 | 6 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 830 | test_830.php | 函数 | a,b,c | a,b,c | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 831 | test_831.php | 函数 | 3,2,1 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 832 | test_832.php | 函数 | 6 | 6 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 833 | test_833.php | 函数 | 12 | 12 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 834 | test_834.php | 函数 | 104 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 835 | test_835.php | 函数 | A | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 836 | test_836.php | 循环 | 6 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 837 | test_837.php | 循环 | 15 | 15 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 838 | test_838.php | 循环 | 55 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 839 | test_839.php | 循环 | 2,4,6,8,10 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 840 | test_840.php | 循环 | found | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 841 | test_841.php | 循环 | 3 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 842 | test_842.php | 循环 | 30 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 843 | test_843.php | 函数 | 1,2,3 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 844 | test_844.php | 函数 | PHP Warning:  Array to string  | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 845 | test_845.php | 函数 | 2 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 846 | test_846.php | 函数 | a,b,c | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 847 | test_847.php | 函数 | hello | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 848 | test_848.php | 数组 | 3,4 | 5,5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 849 | test_849.php | 函数 | [1,2,3] | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 850 | test_850.php | 函数 | {"a":1,"b":2} | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 851 | test_851.php | 函数 | 1,2,3 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 852 | test_852.php | 函数 | PHP Deprecated:  str_getcsv(): | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 853 | test_853.php | 函数 | 1 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 854 | test_854.php | 函数 | 4 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 855 | test_855.php | 函数 | 123.5 | 123.5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 856 | test_856.php | 函数 | 64 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 857 | test_857.php | 函数 | 255 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 858 | test_858.php | 函数 | 12 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 859 | test_859.php | 函数 | PHP Deprecated:  Invalid chara | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 860 | test_860.php | 函数 | 5 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 861 | test_861.php | 函数 | 0 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 862 | test_862.php | 函数 | -1 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 863 | test_863.php | 函数 | 0 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 864 | test_864.php | 函数 | 0 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 865 | test_865.php | 函数 | 6 | 6 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 866 | test_866.php | 函数 | 2 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 867 | test_867.php | 函数 | 3 | 3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 868 | test_868.php | 函数 | 3 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 869 | test_869.php | 函数 | llo | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 870 | test_870.php | 函数 | llo | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 871 | test_871.php | 函数 | ello | ello | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 872 | test_872.php | 函数 | ell | ell | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 873 | test_873.php | 函数 | hxxlo | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 874 | test_874.php | 函数 | hexxy | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 875 | test_875.php | 函数 | hexxy | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 876 | test_876.php | 函数 | 6 | 6 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 877 | test_877.php | 函数 | 6 | 6 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 878 | test_878.php | 函数 | 15 | 15 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 879 | test_879.php | 函数 | 3,4,5 | 1,2,3,4,5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 880 | test_880.php | 函数 | 2,4,6 | 1,2,3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 881 | test_881.php | 函数 | yes | yes | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 882 | test_882.php | 函数 | 1 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 883 | test_883.php | 函数 | yes | yes | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 884 | test_884.php | 函数 | no | no | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 885 | test_885.php | 函数 | abc | abc | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 886 | test_886.php | 函数 | 0 | 0 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 887 | test_887.php | 函数 | array | array | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 888 | test_888.php | 函数 | string | string | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 889 | test_889.php | 函数 | int | int | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 890 | test_890.php | 函数 | float | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 891 | test_891.php | 函数 | bool | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 892 | test_892.php | 函数 | null | null | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 893 | test_893.php | 函数 | integer | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 894 | test_894.php | 函数 | 123 | 123 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 895 | test_895.php | 函数 | 123.45 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 896 | test_896.php | 函数 | 123 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 897 | test_897.php | 函数 | 1 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 898 | test_898.php | 函数 | 1 | 1.5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 899 | test_899.php | 函数 | 5 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 900 | test_900.php | 函数 | Array
(
    [0] => 1
    [1] = | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 901 | test_901.php | 函数 | Array
(
    [a] => 1
    [b] = | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 902 | test_902.php | 函数 | array(3) {
  [0]=>
  int(1)
   | array(...) | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 903 | test_903.php | 函数 | yes | yes | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 904 | test_904.php | 函数 | 1,2,3,4,5 | 1,2,3,4,5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 905 | test_905.php | 函数 | 6,7,8,9,10 | 6,7,8,9,10 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 906 | test_906.php | 函数 | 10,9,8,7,6,5,4,3,2,1 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 907 | test_907.php | 函数 | 1,2,3,4 | 1,2,3,4 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 908 | test_908.php | 函数 | 6 | 6 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 909 | test_909.php | 函数 | 6 | 6 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 910 | test_910.php | 函数 | 6 | 6 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 1 warning |
| 911 | test_911.php | 循环 | 1,4,9,16,25 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 912 | test_912.php | 循环 | 2,4,6,8,10 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 913 | test_913.php | 循环 | 2,4,6,8,10,12,14,16,18,20 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 914 | test_914.php | 循环 | 63 | Bytecode execution failed: Sta | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 915 | test_915.php | 循环 | 275 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 916 | test_916.php | 循环 | 479001600 | 479001600 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 917 | test_917.php | 循环 | 1,1,2,3,5,8,13,21,34,55 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 918 | test_918.php | 循环 | 15 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 919 | test_919.php | 循环 | 55 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 920 | test_920.php | 循环 | found | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 921 | test_921.php | 循环 | 2 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 922 | test_922.php | 循环 | 55 | 55 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 923 | test_923.php | 循环 | 3628800 | 3628800 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 924 | test_924.php | 循环 | 55 | 0 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 925 | test_925.php | 循环 | 15 | 15 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 926 | test_926.php | 循环 | 15 | 15 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 927 | test_927.php | 函数 | 15120 | 15120 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 928 | test_928.php | 函数 | 51 | ArrayArray | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 929 | test_929.php | 循环 | 2870 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 930 | test_930.php | 循环 | 165 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 931 | test_931.php | 循环 | 35 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 932 | test_932.php | 循环 | 338350 | 338350 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 933 | test_933.php | 循环 | 610 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 934 | test_934.php | 函数 | 1 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 935 | test_935.php | 函数 | 9 | 9 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 936 | test_936.php | 函数 | 15 | 15 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 937 | test_937.php | 函数 | 720 | 720 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 938 | test_938.php | 函数 | 11 | 11 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 939 | test_939.php | 函数 | hello | hello | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 940 | test_940.php | 函数 | HELLO | HELLO | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 941 | test_941.php | 函数 | Hello World | Hello World | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 942 | test_942.php | 函数 | Hello | Hello | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 943 | test_943.php | 函数 | hELLO | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 944 | test_944.php | 函数 | olleh | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 945 | test_945.php | 函数 | 4 | 4 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 946 | test_946.php | 函数 | a-b-c | a-b-c | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 947 | test_947.php | 函数 | yes | yes | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 948 | test_948.php | 函数 | yes | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 949 | test_949.php | 函数 | 1,3,5,8,9 | 1,3,5,8,9 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 950 | test_950.php | 函数 | 9,8,5,3,1 | 9,8,5,3,1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 951 | test_951.php | 函数 | a,b,c | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 952 | test_952.php | 函数 | 1,2,3 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 953 | test_953.php | 函数 | PHP Warning:  Array to string  | Array | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 954 | test_954.php | 函数 | 1,4,5 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 955 | test_955.php | 函数 | 1,2,3,4,5 | 1,2,3,4,5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 956 | test_956.php | 函数 | 3,2,1 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 957 | test_957.php | 函数 | 9 | 15 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 958 | test_958.php | 函数 | 3 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 959 | test_959.php | 函数 | 12 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 960 | test_960.php | 函数 | 3 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 961 | test_961.php | 表达式 | 2 | 2 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 962 | test_962.php | 函数 | 10 | 10 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 963 | test_963.php | 函数 | 3 | 3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 964 | test_964.php | 函数 | 4 | 4 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 965 | test_965.php | 函数 | 4 | 4 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 966 | test_966.php | 函数 | 1024 | 1024 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 967 | test_967.php | 函数 | 4 | 4 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 968 | test_968.php | 函数 | 4 | Array | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 969 | test_969.php | 函数 | 1 | Array | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 970 | test_970.php | 表达式 | 6 | 6 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 971 | test_971.php | 表达式 | 6 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 972 | test_972.php | 表达式 | 17 | 17 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 973 | test_973.php | 表达式 | 7 | 7 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 974 | test_974.php | 表达式 | 12 | 12 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 975 | test_975.php | 表达式 | 4 | 4 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 976 | test_976.php | 表达式 | 1 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 977 | test_977.php | 表达式 | 1 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 978 | test_978.php | 表达式 | 0 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 979 | test_979.php | 表达式 |  |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 980 | test_980.php | 表达式 | 2 | 2 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 981 | test_981.php | 表达式 | 7 | 7 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 982 | test_982.php | 表达式 | 5 | 3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 983 | test_983.php | 表达式 | 16 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 984 | test_984.php | 表达式 | 4 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 985 | test_985.php | 函数 | 3 | 3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 986 | test_986.php | 函数 | 120 | 120 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 987 | test_987.php | 循环 | 156 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 988 | test_988.php | 循环 | 165 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 989 | test_989.php | 循环 | 180 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 990 | test_990.php | 循环 | 128 | 128 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 991 | test_991.php | 循环 | 1 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 992 | test_992.php | 循环 | 1 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 993 | test_993.php | 循环 | 9 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 994 | test_994.php | 表达式 | 20 | 20 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 995 | test_995.php | 表达式 | 150 | 150 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 996 | test_996.php | 表达式 | 5 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 997 | test_997.php | 函数 | a,b,c,d | a,b,c,d | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 998 | test_998.php | 函数 | 3,2,1 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 999 | test_999.php | 函数 | 3 | 3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1000 | test_1000.php | 函数 | 9 | 9 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1001 | test_1001.php | 函数 | 97 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1002 | test_1002.php | 函数 | F | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1003 | test_1003.php | 循环 | 6 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1004 | test_1004.php | 循环 | 15 | 15 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1005 | test_1005.php | 循环 | 120 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1006 | test_1006.php | 循环 | 2,4,6,8,10,12 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1007 | test_1007.php | 循环 | found | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1008 | test_1008.php | 循环 | 3 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1009 | test_1009.php | 循环 | 45 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1010 | test_1010.php | 函数 | 1,2,3 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1011 | test_1011.php | 函数 | PHP Warning:  Array to string  | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1012 | test_1012.php | 函数 | 2 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1013 | test_1013.php | 函数 | a,b,c | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1014 | test_1014.php | 函数 | hello | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1015 | test_1015.php | 循环 | 1,4,9,16,25,36,49,64 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1016 | test_1016.php | 函数 | 30 | 30 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1017 | test_1017.php | 函数 | 25 | 25 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1018 | test_1018.php | 函数 | 40 | 55 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1019 | test_1019.php | 函数 | 1,4,9,16,25,36,49,64 | 1,2,3,4,5,6,7,8 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1020 | test_1020.php | 函数 | 43 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1021 | test_1021.php | 函数 | abc--- | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1022 | test_1022.php | 函数 | ---abc | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1023 | test_1023.php | 函数 | testtesttest | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1024 | test_1024.php | 函数 | el | el | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1025 | test_1025.php | 函数 | llo | llo | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1026 | test_1026.php | 表达式 | 9 | 9 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1027 | test_1027.php | 函数 | 3 | 0 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1028 | test_1028.php | 表达式 | 75 | 75 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1029 | test_1029.php | 表达式 | 23.333333333333 | 23.333333333333332 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1030 | test_1030.php | 循环 | 15 | 15 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1031 | test_1031.php | 循环 | 120 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1032 | test_1032.php | 循环 | 3628800 | 3628800 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1033 | test_1033.php | 循环 | 1,1,2,3,5,8,13,21 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1034 | test_1034.php | 函数 | 1,2,3,4,5,6,7,8,9 | 1,2,3,4,5,6,7,8,9 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1035 | test_1035.php | 函数 | b,a,c | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1036 | test_1036.php | 函数 | a,b,c | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1037 | test_1037.php | 函数 | no | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1038 | test_1038.php | 函数 | yes | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1039 | test_1039.php | 函数 | not int | not int | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1040 | test_1040.php | 函数 | not float | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1041 | test_1041.php | 函数 | null | null | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1042 | test_1042.php | 函数 | string | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1043 | test_1043.php | 表达式 | 130 | 130 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1044 | test_1044.php | 表达式 | 6.28 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1045 | test_1045.php | 表达式 | 123abc | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1046 | test_1046.php | 表达式 | 1 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1047 | test_1047.php | 表达式 | 5 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1048 | test_1048.php | 表达式 | 10 | 10.5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1049 | test_1049.php | 函数 | Array
(
    [0] => 1
    [1] = | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1050 | test_1050.php | 函数 | Array
(
    [name] => Tom
     | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1051 | test_1051.php | 函数 | array(3) {
  [0]=>
  int(1)
   | array(...) | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1052 | test_1052.php | 函数 | PHP Deprecated:  str_getcsv(): | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1053 | test_1053.php | 函数 | 0 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1054 | test_1054.php | 函数 | 0 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1055 | test_1055.php | 函数 | -1 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1056 | test_1056.php | 函数 | 0 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1057 | test_1057.php | 函数 | 0 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1058 | test_1058.php | 函数 | 4 | 4 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1059 | test_1059.php | 函数 | 7 | 7 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1060 | test_1060.php | 函数 | 2 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1061 | test_1061.php | 函数 | 7 | 7 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1062 | test_1062.php | 函数 | 7 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1063 | test_1063.php | 函数 |  World | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1064 | test_1064.php | 函数 | ELLO | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1065 | test_1065.php | 函数 | bcd | bcd | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1066 | test_1066.php | 函数 | ef | ef | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1067 | test_1067.php | 函数 | hxxlo | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1068 | test_1068.php | 函数 | hell0 w0rld | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1069 | test_1069.php | 函数 | xxyy | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1070 | test_1070.php | 函数 | ff | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1071 | test_1071.php | 函数 | 255 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1072 | test_1072.php | 函数 | 77 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1073 | test_1073.php | 函数 | 63 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1074 | test_1074.php | 函数 | 10 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1075 | test_1075.php | 函数 | 1,234,567 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1076 | test_1076.php | 函数 | 1234.57 | 1234.57 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1077 | test_1077.php | 函数 | 3.142 | 3.142 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1078 | test_1078.php | 循环 | 20 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1079 | test_1079.php | 函数 | 210 | 210 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1080 | test_1080.php | 循环 | 1.5511210043331E+25 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1081 | test_1081.php | 循环 | 1307674368000 | 1307674368000 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1082 | test_1082.php | 函数 | 55 | 55 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1083 | test_1083.php | 循环 | 6 | 6 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1084 | test_1084.php | 循环 | 5 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1085 | test_1085.php | 循环 | 1 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1086 | test_1086.php | 循环 | 2 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1087 | test_1087.php | 循环 | 3 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1088 | test_1088.php | 循环 | prime | prime | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1089 | test_1089.php | 函数 | 3 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1090 | test_1090.php | 函数 | a,b,c | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1091 | test_1091.php | 函数 | 1,2,3,4,5,6 | 1,2,3,4,5,6 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1092 | test_1092.php | 函数 | 1,2 | 1,2 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1093 | test_1093.php | 函数 | 1 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1094 | test_1094.php | 函数 | 4 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1095 | test_1095.php | 函数 | 3 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1096 | test_1096.php | 函数 | 8 | 8 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1097 | test_1097.php | 函数 | hello | hello | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1098 | test_1098.php | 函数 | hello | ---hello--- | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1099 | test_1099.php | 函数 | hello | hello | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1100 | test_1100.php | 函数 | hello | hello | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1101 | test_1101.php | 函数 | --hello--- | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1102 | test_1102.php | 函数 | abcabcabcabcabc | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1103 | test_1103.php | 函数 | 1 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1104 | test_1104.php | 函数 | 4 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1105 | test_1105.php | 表达式 | 5 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1106 | test_1106.php | 表达式 | 6 | 6 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1107 | test_1107.php | 表达式 | 5 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1108 | test_1108.php | 表达式 | 16 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1109 | test_1109.php | 表达式 | 5 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1110 | test_1110.php | 函数 | 15 | 15 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1111 | test_1111.php | 函数 | 120 | 16 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1112 | test_1112.php | 函数 | PHP Warning:  Array to string  | Array | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1113 | test_1113.php | 函数 | PHP Warning:  Array to string  | Array | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1114 | test_1114.php | 函数 | 3 | 3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1115 | test_1115.php | 函数 | 5 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1116 | test_1116.php | 函数 | 1,2,3,4,5 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1117 | test_1117.php | 函数 | 5,4,3,2,1 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1118 | test_1118.php | 函数 | a,b,c | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1119 | test_1119.php | 函数 | c,b,a | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1120 | test_1120.php | 函数 | 7 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1121 | test_1121.php | 函数 | lhole | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1122 | test_1122.php | 函数 | c,a,b | b,c,a | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1123 | test_1123.php | 函数 | yes | yes | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1124 | test_1124.php | 函数 | yes | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1125 | test_1125.php | 函数 | 2 | 2 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1126 | test_1126.php | 函数 | 22 | 22 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1127 | test_1127.php | 表达式 | 1 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1128 | test_1128.php | 表达式 |  |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1129 | test_1129.php | 表达式 | 1 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1130 | test_1130.php | 函数 | 0 | 0 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1131 | test_1131.php | 函数 | empty | empty | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1132 | test_1132.php | 函数 | set | set | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1133 | test_1133.php | 函数 | not | not | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1134 | test_1134.php | 函数 | null | null | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1135 | test_1135.php | 函数 | not | not | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1136 | test_1136.php | 函数 | empty | empty | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1137 | test_1137.php | 函数 | empty | not | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1138 | test_1138.php | 函数 | empty | empty | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1139 | test_1139.php | 函数 | empty | empty | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1140 | test_1140.php | 表达式 | null | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1141 | test_1141.php | 表达式 | zero | zero | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1142 | test_1142.php | 表达式 | 5 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1143 | test_1143.php | 表达式 | 10 | 10 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1144 | test_1144.php | 表达式 | 10 | 10 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1145 | test_1145.php | 表达式 | 1 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 2 errors, 0 warning |
| 1146 | test_1146.php | 表达式 | -1 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 2 errors, 0 warning |
| 1147 | test_1147.php | 表达式 | 0 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 2 errors, 0 warning |
| 1148 | test_1148.php | 函数 | 1 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1149 | test_1149.php | 函数 | 1 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1150 | test_1150.php | 函数 | 0 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1151 | test_1151.php | 函数 | a | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1152 | test_1152.php | 函数 | 3 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1153 | test_1153.php | 函数 | false | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1154 | test_1154.php | 表达式 | -1 | -1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1155 | test_1155.php | 表达式 | 5 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1156 | test_1156.php | 表达式 | 5 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1157 | test_1157.php | 表达式 | yes | yes | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1158 | test_1158.php | 表达式 | no | no | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1159 | test_1159.php | 表达式 | yes | yes | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1160 | test_1160.php | 表达式 | yes | no | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1161 | test_1161.php | 表达式 | no | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1162 | test_1162.php | 表达式 | yes | yes | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1163 | test_1163.php | 表达式 | yes |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1164 | test_1164.php | 表达式 | yes | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1165 | test_1165.php | 表达式 | positive | positive | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1166 | test_1166.php | 表达式 | has | has | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1167 | test_1167.php | 表达式 | not |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1168 | test_1168.php | 表达式 | odd | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1169 | test_1169.php | 表达式 | multiple | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1170 | test_1170.php | 表达式 | 15 | 15 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1171 | test_1171.php | 表达式 | 13 | 7 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1172 | test_1172.php | 表达式 | -2 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1173 | test_1173.php | 表达式 |  |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1174 | test_1174.php | 表达式 |  |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1175 | test_1175.php | 表达式 | 8 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1176 | test_1176.php | 表达式 | 4 | 16 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1177 | test_1177.php | 表达式 | 1 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1178 | test_1178.php | 表达式 | 7 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1179 | test_1179.php | 表达式 | 6 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1180 | test_1180.php | 表达式 | false | false | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1181 | test_1181.php | 表达式 | true | true | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1182 | test_1182.php | 表达式 | false | false | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1183 | test_1183.php | 表达式 | true | true | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1184 | test_1184.php | 表达式 | false | false | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1185 | test_1185.php | 表达式 | true | true | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1186 | test_1186.php | 表达式 | true | true | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1187 | test_1187.php | 表达式 | false | false | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1188 | test_1188.php | 表达式 | true | true | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1189 | test_1189.php | 表达式 | false | false | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1190 | test_1190.php | 表达式 | true | true | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1191 | test_1191.php | 表达式 | false | false | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1192 | test_1192.php | 函数 | integer | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1193 | test_1193.php | 函数 | double | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1194 | test_1194.php | 函数 | string | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1195 | test_1195.php | 函数 | boolean | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1196 | test_1196.php | 函数 | array | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1197 | test_1197.php | 函数 | NULL | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1198 | test_1198.php | 函数 |  |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1199 | test_1199.php | 函数 |  |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1200 | test_1200.php | 函数 | 1 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1201 | test_1201.php | 函数 |  | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1202 | test_1202.php | 函数 | 1 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1203 | test_1203.php | 函数 | 1 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1204 | test_1204.php | 函数 |  | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1205 | test_1205.php | 函数 | 3 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1206 | test_1206.php | 函数 |  | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1207 | test_1207.php | 函数 | 1 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1208 | test_1208.php | 函数 | PHP Warning:  Array to string  | Array | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1209 | test_1209.php | 函数 | PHP Warning:  Array to string  | Array | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1210 | test_1210.php | 函数 | PHP Warning:  Array to string  | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1211 | test_1211.php | 函数 | PHP Warning:  Array to string  | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1212 | test_1212.php | 函数 | 4 | 4 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1213 | test_1213.php | 函数 | 3 | 3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1214 | test_1214.php | 函数 | 1 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1215 | test_1215.php | 函数 | 3 | 3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1216 | test_1216.php | 函数 | PHP Warning:  Array to string  | Array | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1217 | test_1217.php | 函数 | PHP Warning:  Array to string  | Array | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1218 | test_1218.php | 函数 | 1,4,5 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1219 | test_1219.php | 函数 | 1,9,2,3 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1220 | test_1220.php | 函数 | PHP Warning:  Array to string  | Array | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1221 | test_1221.php | 函数 | PHP Warning:  Array to string  | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1222 | test_1222.php | 函数 | PHP Warning:  Array to string  | Array | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1223 | test_1223.php | 函数 | 5,4,3,2,1 | 5,4,3,2,1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1224 | test_1224.php | 函数 | 0,2,4,6,8,10 | 0,2,4,6,8,10 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1225 | test_1225.php | 函数 | 25 | 25 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1226 | test_1226.php | 函数 | 256 | 256 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1227 | test_1227.php | 函数 | 2 | 2 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1228 | test_1228.php | 函数 | 0.69314718055995 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1229 | test_1229.php | 函数 | 7.3890560989307 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1230 | test_1230.php | 函数 | 3.1415926535898 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1231 | test_1231.php | 函数 | 5 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1232 | test_1232.php | 函数 | 3 | 3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1233 | test_1233.php | 函数 | 4 | 4 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1234 | test_1234.php | 函数 | 4 | 4 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1235 | test_1235.php | 函数 | 4 | 4 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1236 | test_1236.php | 函数 | 3 | 4 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1237 | test_1237.php | 函数 | 14 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1238 | test_1238.php | 控制流 | big | big | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1239 | test_1239.php | 控制流 | small | small | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1240 | test_1240.php | 控制流 | C | C | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1241 | test_1241.php | 控制流 | B | B | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1242 | test_1242.php | 控制流 | A | A | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1243 | test_1243.php | 控制流 | one |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1244 | test_1244.php | 控制流 | two |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1245 | test_1245.php | 控制流 | other |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1246 | test_1246.php | 控制流 | hi |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1247 | test_1247.php | 控制流 | ? |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1248 | test_1248.php | 循环 | 01234 | 01234 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1249 | test_1249.php | 循环 | 01234 | 01234 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1250 | test_1250.php | 循环 | 54321 | 54321 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1251 | test_1251.php | 循环 | 012 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1252 | test_1252.php | 循环 | 012 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1253 | test_1253.php | 循环 | 123 | 123 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1254 | test_1254.php | 循环 | 12345 | 12345 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1255 | test_1255.php | 循环 | 54321 | 54321 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1256 | test_1256.php | 循环 | 123 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1257 | test_1257.php | 循环 | 12345 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1258 | test_1258.php | 循环 | abc | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1259 | test_1259.php | 循环 | x1y2 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1260 | test_1260.php | 循环 | 6 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1261 | test_1261.php | 循环 | 10 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1262 | test_1262.php | 循环 | 1245 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1263 | test_1263.php | 循环 | 15 | 15 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1264 | test_1264.php | 循环 | 1245 | 1245 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1265 | test_1265.php | 循环 | 37 | 37 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1266 | test_1266.php | 循环 | 28 | 28 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1267 | test_1267.php | 循环 | 2,4 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1268 | test_1268.php | 循环 | 0:1;1:2;2:3; | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1269 | test_1269.php | 表达式 | big | big | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1270 | test_1270.php | 表达式 | small | small | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1271 | test_1271.php | 表达式 | 5 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1272 | test_1272.php | 表达式 | one | one | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1273 | test_1273.php | 表达式 | two | two | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1274 | test_1274.php | 表达式 | other | other | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1275 | test_1275.php | 表达式 | 10 | 10 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1276 | test_1276.php | 控制流 | false | false | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1277 | test_1277.php | 控制流 | true | true | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1278 | test_1278.php | 控制流 | false | false | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1279 | test_1279.php | 控制流 | true | true | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1280 | test_1280.php | 控制流 | false | false | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1281 | test_1281.php | 控制流 | true | true | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1282 | test_1282.php | 控制流 | false | false | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1283 | test_1283.php | 控制流 | true | true | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1284 | test_1284.php | 控制流 | false | false | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1285 | test_1285.php | 控制流 | true | false | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1286 | test_1286.php | 控制流 | true | false | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1287 | test_1287.php | 控制流 | true | true | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1288 | test_1288.php | 控制流 | true | true | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1289 | test_1289.php | 控制流 | found | found | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1290 | test_1290.php | 控制流 | not | not | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1291 | test_1291.php | 控制流 | yes | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1292 | test_1292.php | 控制流 | no | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1293 | test_1293.php | 控制流 | in range | in range | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1294 | test_1294.php | 控制流 | out | out | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1295 | test_1295.php | 控制流 | in range | in range | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1296 | test_1296.php | 控制流 | in range | in range | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1297 | test_1297.php | 控制流 | not big | not big | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1298 | test_1298.php | 控制流 | big | big | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1299 | test_1299.php | 循环 | 5050 | 5050 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1300 | test_1300.php | 循环 | 3628800 | 3628800 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1301 | test_1301.php | 循环 | 6765 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1302 | test_1302.php | 循环 | 196 | Bytecode execution failed: Sta | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1303 | test_1303.php | 循环 | 2 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1304 | test_1304.php | 循环 | 8 | 8 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1305 | test_1305.php | 循环 | 1 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1306 | test_1306.php | 循环 | prime | prime | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1307 | test_1307.php | 循环 | not | not | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1308 | test_1308.php | 循环 | 2870 | 2870 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1309 | test_1309.php | 循环 | 479001600 | 479001600 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1310 | test_1310.php | 循环 | 325 | 325 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1311 | test_1311.php | 循环 | 325 | 0 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1312 | test_1312.php | 循环 | 1,3,5,7,9,11,13,15 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1313 | test_1313.php | 循环 | 2,4,6,8,10,12,14 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1314 | test_1314.php | 循环 | 55 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1315 | test_1315.php | 循环 | 40320 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1316 | test_1316.php | 表达式 | 2 | 2 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1317 | test_1317.php | 表达式 | 2.5 | 2.5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1318 | test_1318.php | 表达式 | 31 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1319 | test_1319.php | 表达式 | 32 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1320 | test_1320.php | 表达式 | 142 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1321 | test_1321.php | 函数 | 1,9 | 1,9 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1322 | test_1322.php | 函数 | 9,1 | 9,1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1323 | test_1323.php | 函数 | 5.5 | 5.5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1324 | test_1324.php | 函数 | 10.5 | 10.5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1325 | test_1325.php | 表达式 | not | not | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1326 | test_1326.php | 表达式 | found | found | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1327 | test_1327.php | 表达式 | 7.5 | 7.5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1328 | test_1328.php | 表达式 | 6 | 6 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1329 | test_1329.php | 表达式 | 15 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1330 | test_1330.php | 表达式 | 7 | 7 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1331 | test_1331.php | 数组 | a,b,c | ,a,b,c | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1332 | test_1332.php | 数组 | abc | abc | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1333 | test_1333.php | 数组 | ae | ae | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1334 | test_1334.php | 数组 | 1 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1335 | test_1335.php | 数组 | 3 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1336 | test_1336.php | 数组 | 4 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1337 | test_1337.php | 数组 | 1 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1338 | test_1338.php | 数组 | 4 | 4 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1339 | test_1339.php | 数组 | 6 | 6 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1340 | test_1340.php | 数组 | 15 | 15 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1341 | test_1341.php | 数组 | 2 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1342 | test_1342.php | 数组 | 2 | 2 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1343 | test_1343.php | 循环 | 0,1,4 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1344 | test_1344.php | 循环 | 1,3,5,7 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1345 | test_1345.php | 循环 | 0,2,4,6,8 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1346 | test_1346.php | 循环 | 100 | 100 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1347 | test_1347.php | 循环 | 35 | 35 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1348 | test_1348.php | 循环 | *
**
***
****
***** | * | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1349 | test_1349.php | 循环 | 285 | 29030400 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1350 | test_1350.php | 循环 | found | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1351 | test_1351.php | 循环 | 12 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1352 | test_1352.php | 循环 | 2,4 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1353 | test_1353.php | 循环 | 2,4,6 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1354 | test_1354.php | 循环 | 9 | 9 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1355 | test_1355.php | 数组 | 1,2,3,4,5 | 1,2,3,4,5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1356 | test_1356.php | 函数 | 9 | Array | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1357 | test_1357.php | 函数 | 1 | Array | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1358 | test_1358.php | 函数 | 21 | 21 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1359 | test_1359.php | 函数 | 3 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1360 | test_1360.php | 函数 | 2 | 2 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1361 | test_1361.php | 函数 | e | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1362 | test_1362.php | 表达式 | big | big | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1363 | test_1363.php | 表达式 | three | three | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1364 | test_1364.php | 循环 | 0,1,2,3,4 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1365 | test_1365.php | 循环 | 120 | 120 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1366 | test_1366.php | 数组 | 1,2,3,4,5 | 1,2,3,4,5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1367 | test_1367.php | 数组 | 23 | 44 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1368 | test_1368.php | 函数 | abcABC | abcABC | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1369 | test_1369.php | 表达式 | 8 | 8 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1370 | test_1370.php | 表达式 | 36 | 36 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1371 | test_1371.php | 表达式 | 10 | 10 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1372 | test_1372.php | 表达式 | 0 | 0 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1373 | test_1373.php | 表达式 | 正奇 | Bytecode execution failed: Sta | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1374 | test_1374.php | 表达式 | 正偶 | Bytecode execution failed: Sta | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1375 | test_1375.php | 表达式 | 非正 | Bytecode execution failed: Sta | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1376 | test_1376.php | 控制流 | valid | valid | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1377 | test_1377.php | 控制流 | invalid | invalid | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1378 | test_1378.php | 控制流 | odd digit | odd digit | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1379 | test_1379.php | 控制流 | other | other | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1380 | test_1380.php | 循环 | 9 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1381 | test_1381.php | 循环 | 12 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1382 | test_1382.php | 循环 | 1245 | 1245 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1383 | test_1383.php | 循环 | 123 | 123 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1384 | test_1384.php | 函数 | 6 | 6 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1385 | test_1385.php | 函数 | 40 | 40 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1386 | test_1386.php | 函数 | 3 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1387 | test_1387.php | 函数 | 1,2 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1388 | test_1388.php | 函数 | 6 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1389 | test_1389.php | 函数 | 2 | 2 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1390 | test_1390.php | 循环 | 55 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1391 | test_1391.php | 表达式 | 3 | 3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1392 | test_1392.php | 函数 | found | found | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1393 | test_1393.php | 函数 | 6 | 6 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1394 | test_1394.php | 循环 | 6 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 1 warning |
| 1395 | test_1395.php | 函数 | a | a | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1396 | test_1396.php | 函数 | 2 | 2 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1397 | test_1397.php | 函数 | 3 | 3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1398 | test_1398.php | 表达式 | 123 | 123 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1399 | test_1399.php | 表达式 | 1PHP Deprecated:  Implicit con | 123 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1400 | test_1400.php | 表达式 | 30 | 30 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1401 | test_1401.php | 循环 | 1,2,5,10 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1402 | test_1402.php | 循环 | prime | prime | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1403 | test_1403.php | 函数 | 1,2,3 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1404 | test_1404.php | 表达式 | both | both | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1405 | test_1405.php | 表达式 | three | Bytecode execution failed: Sta | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1406 | test_1406.php | 表达式 | one | Bytecode execution failed: Sta | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1407 | test_1407.php | 表达式 | other | Bytecode execution failed: Sta | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1408 | test_1408.php | 循环 | 55 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1409 | test_1409.php | 循环 | 2,4,6,8,10,12,14,16,18,20 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1410 | test_1410.php | 循环 | 1,3,5,7,9 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1411 | test_1411.php | 循环 | 6 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1412 | test_1412.php | 循环 | 9 | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1413 | test_1413.php | 函数 | 110 | 210 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1414 | test_1414.php | 函数 | 100 | 210 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1415 | test_1415.php | 函数 | 10,20,30,40,50,60,70,80,90,100 | 1,2,3,4,5,6,7,8,9,10 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1416 | test_1416.php | 函数 | 15 | 15 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1417 | test_1417.php | 函数 | 0 | 15 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1418 | test_1418.php | 函数 | 5 | 15 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1419 | test_1419.php | 函数 |  | 15 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1420 | test_1420.php | 表达式 | 7.5 | 7.5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1421 | test_1421.php | 函数 | 12.5 | 12.5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1422 | test_1422.php | 表达式 | in | in | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1423 | test_1423.php | 表达式 | out | out | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1424 | test_1424.php | 表达式 | a | a | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1425 | test_1425.php | 表达式 | b | b | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1426 | test_1426.php | 表达式 | 0 | 0 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1427 | test_1427.php | 表达式 | 0 | 0 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1428 | test_1428.php | 表达式 | default | default | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1429 | test_1429.php | 数组 | a,b,c | a,b,c | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1430 | test_1430.php | 数组 | 3 | 3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1431 | test_1431.php | 表达式 | complete | complete | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1432 | test_1432.php | 表达式 | not | not | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1433 | test_1433.php | 函数 | ***hello | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1434 | test_1434.php | 函数 | hello*** | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1435 | test_1435.php | 函数 | ***hello*** | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1436 | test_1436.php | 函数 | abc | abc | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1437 | test_1437.php | 函数 | def | def | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1438 | test_1438.php | 函数 | bcde | bcde | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1439 | test_1439.php | 函数 | abcabcabcabc | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1440 | test_1440.php | 函数 | a-b-c-d-e | a-b-c-d-e | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1441 | test_1441.php | 函数 | 3,2,1 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1442 | test_1442.php | 函数 | 1,1,3,4,5 | 1,1,3,4,5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1443 | test_1443.php | 函数 | 5,4,3,1,1 | 5,4,3,1,1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1444 | test_1444.php | 函数 | 1,2,3 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1445 | test_1445.php | 函数 | 3,2,1 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1446 | test_1446.php | 常量 | 9223372036854775807 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1447 | test_1447.php | 常量 | -9223372036854775808 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1448 | test_1448.php | 常量 | 8.4.8 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1449 | test_1449.php | 常量 | Darwin |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1450 | test_1450.php | 常量 | 3.1415926535898 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1451 | test_1451.php | 常量 | 2.718281828459 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1452 | test_1452.php | 函数 | 1,1,1,1,1 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1453 | test_1453.php | 函数 | a,a,a | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1454 | test_1454.php | 函数 | 15 | 15 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1455 | test_1455.php | 函数 | 5,4,3,2,1 | 5,4,3,2,1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1456 | test_1456.php | 函数 | 0,2,4,6,8,10 | 0,2,4,6,8,10 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1457 | test_1457.php | 函数 | 0,3,6,9 | 0,3,6,9 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1458 | test_1458.php | 表达式 | h |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1459 | test_1459.php | 表达式 | o |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1460 | test_1460.php | 表达式 | Hello | hello | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1461 | test_1461.php | 表达式 | 1 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1462 | test_1462.php | 表达式 | c | c | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1463 | test_1463.php | 表达式 | 1 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1464 | test_1464.php | 表达式 | x=5,y=10 | x=5,y=10 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1465 | test_1465.php | 表达式 | 15 | 15 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1466 | test_1466.php | 表达式 | 50 | 50 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1467 | test_1467.php | 表达式 | 3.3333333333333 | 3.3333333333333335 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1468 | test_1468.php | 表达式 | 1 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1469 | test_1469.php | 表达式 | 1024 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1470 | test_1470.php | 表达式 | 1048576 |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1471 | test_1471.php | 表达式 | 5 | 5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1472 | test_1472.php | 表达式 | 3.5 | 3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1473 | test_1473.php | 表达式 | 3 | 3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1474 | test_1474.php | 表达式 | 4 | 4 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1475 | test_1475.php | 表达式 | 4 | 4 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1476 | test_1476.php | 表达式 | 3.1416 | 3.1416 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1477 | test_1477.php | 表达式 | 4 | 4 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1478 | test_1478.php | 表达式 | 0.69314718055995 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1479 | test_1479.php | 表达式 | 7.3890560989307 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1480 | test_1480.php | 表达式 | 1 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1481 | test_1481.php | 表达式 | 64 | 64 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1482 | test_1482.php | 表达式 | 0.90929742682568 | 0.9092974268256817 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1483 | test_1483.php | 表达式 | -0.41614683654714 | -0.4161468365471424 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1484 | test_1484.php | 表达式 | -2.1850398632615 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1485 | test_1485.php | 函数 | 3 | 3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1486 | test_1486.php | 函数 | 3 | 3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1487 | test_1487.php | 函数 | 6 | 6 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1488 | test_1488.php | 函数 | 6 | 6 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1489 | test_1489.php | 函数 | 1-2-3 | 1-2-3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1490 | test_1490.php | 函数 | 3 | 3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1491 | test_1491.php | 函数 | HELLO | HELLO | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1492 | test_1492.php | 函数 | hello | hello | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1493 | test_1493.php | 函数 | Hello World | Hello World | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1494 | test_1494.php | 函数 | Hello | Hello | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1495 | test_1495.php | 函数 | hELLO | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1496 | test_1496.php | 函数 | olleh | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1497 | test_1497.php | 函数 | abcde | abcde | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1498 | test_1498.php | 函数 | PHP Warning:  Array to string  | Array | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1499 | test_1499.php | 函数 | PHP Warning:  Array to string  | Array | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1500 | test_1500.php | 函数 | 1,4,5 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1501 | test_1501.php | 函数 | 1,2,3,4 | 1,2,3,4 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1502 | test_1502.php | 函数 | 1,2,3 | 1,2,3 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1503 | test_1503.php | 函数 | 3,2,1 | 3,2,1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1504 | test_1504.php | 函数 | a,b,c | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1505 | test_1505.php | 函数 | 1,2,3 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1506 | test_1506.php | 函数 | yes | yes | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1507 | test_1507.php | 函数 | yes | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1508 | test_1508.php | 函数 | 1 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1509 | test_1509.php | 函数 | 1,2,3 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1510 | test_1510.php | 函数 | PHP Warning:  Array to string  | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1511 | test_1511.php | 函数 | hello----- | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1512 | test_1512.php | 函数 | -----hello | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1513 | test_1513.php | 函数 | ---hello--- | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1514 | test_1514.php | 函数 | aaaaaaaaa | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1515 | test_1515.php | 函数 | hello | hello | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1516 | test_1516.php | 函数 | world | world | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1517 | test_1517.php | 函数 | world | world | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1518 | test_1518.php | 函数 | 3 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1519 | test_1519.php | 函数 | heLLo | heLLo | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1520 | test_1520.php | 函数 | hello | hello | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1521 | test_1521.php | 函数 | hello | ---hello--- | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1522 | test_1522.php | 函数 | hello | hello | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1523 | test_1523.php | 函数 | hello | hello | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1524 | test_1524.php | 函数 | 5d41402abc4b2a76b9719d911017c5 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1525 | test_1525.php | 函数 | aaf4c61ddcc5e8a2dabede0f3b482c | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1526 | test_1526.php | 函数 | 65 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1527 | test_1527.php | 函数 | A | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1528 | test_1528.php | 函数 | ff | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1529 | test_1529.php | 函数 | 255 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1530 | test_1530.php | 函数 | 77 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1531 | test_1531.php | 函数 | 63 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1532 | test_1532.php | 函数 | 10 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1533 | test_1533.php | 函数 | 1,234,567 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1534 | test_1534.php | 函数 | 1,234,567.89 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1535 | test_1535.php | 函数 | 123 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1536 | test_1536.php | 函数 | 123 | 123 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1537 | test_1537.php | 函数 | 123.45 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1538 | test_1538.php | 表达式 | 1 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1539 | test_1539.php | 表达式 | 0 | 0 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1540 | test_1540.php | 表达式 | 1 | 1.5 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1541 | test_1541.php | 函数 | empty | empty | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1542 | test_1542.php | 函数 | empty | empty | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1543 | test_1543.php | 函数 | empty | empty | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1544 | test_1544.php | 函数 | null | null | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1545 | test_1545.php | 函数 | yes | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1546 | test_1546.php | 函数 | no | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1547 | test_1547.php | 函数 | yes | yes | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1548 | test_1548.php | 函数 | integer | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1549 | test_1549.php | 函数 | double | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1550 | test_1550.php | 函数 | boolean | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1551 | test_1551.php | 函数 | NULL | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1552 | test_1552.php | 函数 | 1 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1553 | test_1553.php | 函数 | 2 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1554 | test_1554.php | 函数 | 3 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1555 | test_1555.php | 函数 | 3 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1556 | test_1556.php | 函数 | 0 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1557 | test_1557.php | 函数 | b | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1558 | test_1558.php | 函数 | 1 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1559 | test_1559.php | 函数 | 1 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1560 | test_1560.php | 函数 | 1 | 1 | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1561 | test_1561.php | 表达式 |  | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 2 errors, 0 warning |
| 1562 | test_1562.php | 表达式 |  | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 2 errors, 0 warning |
| 1563 | test_1563.php | 表达式 |  | InvalidOpcode: func='main' ip= | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 2 errors, 0 warning |
| 1564 | test_1564.php | 表达式 |  |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1565 | test_1565.php | 表达式 |  |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1566 | test_1566.php | 表达式 |  |  | [编译失败] | AOT_COMPILE_ERROR | Error: Compilation failed with 1 errors, 0 warning |
| 1000000 | test_1000000.php | 循环 | 2870 |  | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=br setTerminator: block=1, term |
| 1000001 | test_1000001.php | 循环 | 165 |  | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=br setTerminator: block=1, term |
| 1000002 | test_1000002.php | 循环 | 35 |  | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=br setTerminator: block=1, term |
| 1000003 | test_1000003.php | 循环 | 338350 | 338350 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=br setTerminator: block=1, term |
| 1000004 | test_1000004.php | 循环 | 610 |  | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=br setTerminator: block=1, term |
| 1000005 | test_1000005.php | 函数 | 1 | 1 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000006 | test_1000006.php | 函数 | 9 | 9 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000007 | test_1000007.php | 函数 | 15 | 15 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000008 | test_1000008.php | 函数 | 720 | 720 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000009 | test_1000009.php | 函数 | 11 | 11 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000010 | test_1000010.php | 函数 | hello | hello | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000011 | test_1000011.php | 函数 | HELLO | HELLO | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000012 | test_1000012.php | 函数 | Hello World | Hello World | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000013 | test_1000013.php | 函数 | Hello | Hello | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000014 | test_1000014.php | 函数 | hELLO | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000015 | test_1000015.php | 函数 | olleh | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000016 | test_1000016.php | 函数 | 4 | 4 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000017 | test_1000017.php | 函数 | a-b-c | a-b-c | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000018 | test_1000018.php | 函数 | yes | yes | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=cond_br setTerminator: block=1, |
| 1000019 | test_1000019.php | 函数 | yes | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=cond_br setTerminator: block=1, |
| 1000020 | test_1000020.php | 函数 | 1,3,5,8,9 | 1,3,5,8,9 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000021 | test_1000021.php | 函数 | 9,8,5,3,1 | 9,8,5,3,1 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000022 | test_1000022.php | 函数 | a,b,c | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000023 | test_1000023.php | 函数 | 1,2,3 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000024 | test_1000024.php | 函数 | PHP Warning:  Array to string  | Array | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000025 | test_1000025.php | 函数 | 1,4,5 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000026 | test_1000026.php | 函数 | 1,2,3,4,5 | 1,2,3,4,5 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000027 | test_1000027.php | 函数 | 3,2,1 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000028 | test_1000028.php | 函数 | 9 | 15 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret setTerminator: block=0, ter |
| 1000029 | test_1000029.php | 函数 | 3 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000030 | test_1000030.php | 函数 | 12 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000031 | test_1000031.php | 函数 | 3 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000032 | test_1000032.php | 表达式 | 2 | 2 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000033 | test_1000033.php | 函数 | 10 | 10 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000034 | test_1000034.php | 函数 | 3 | 3 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000035 | test_1000035.php | 函数 | 4 | 4 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000036 | test_1000036.php | 函数 | 4 | 4 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000037 | test_1000037.php | 函数 | 1024 | 1024 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000038 | test_1000038.php | 函数 | 4 | 4 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000039 | test_1000039.php | 函数 | 4 | Array | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000040 | test_1000040.php | 函数 | 1 | Array | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000041 | test_1000041.php | 表达式 | 6 | 6 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000042 | test_1000042.php | 表达式 | 6 | 5 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000043 | test_1000043.php | 表达式 | 17 | 17 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000044 | test_1000044.php | 表达式 | 7 | 7 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000045 | test_1000045.php | 表达式 | 12 | 12 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000046 | test_1000046.php | 表达式 | 4 | 4 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000047 | test_1000047.php | 表达式 | 1 | 1 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000048 | test_1000048.php | 表达式 | 1 |  | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000049 | test_1000049.php | 表达式 | 0 |  | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000050 | test_1000050.php | 表达式 |  |  | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000051 | test_1000051.php | 表达式 | 2 | 2 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000052 | test_1000052.php | 表达式 | 7 | 7 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000053 | test_1000053.php | 表达式 | 5 | 3 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000054 | test_1000054.php | 表达式 | 16 |  | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000055 | test_1000055.php | 表达式 | 4 |  | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000056 | test_1000056.php | 函数 | 3 | 3 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000057 | test_1000057.php | 函数 | 120 | 120 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000058 | test_1000058.php | 循环 | 156 | foreach_init: iterable type =  | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=br setTerminator: block=1, term |
| 1000059 | test_1000059.php | 循环 | 165 | foreach_init: iterable type =  | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=br setTerminator: block=1, term |
| 1000060 | test_1000060.php | 循环 | 180 | foreach_init: iterable type =  | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=br setTerminator: block=1, term |
| 1000061 | test_1000061.php | 循环 | 128 | 128 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=br setTerminator: block=1, term |
| 1000062 | test_1000062.php | 循环 | 1 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=br setTerminator: block=1, term |
| 1000063 | test_1000063.php | 循环 | 1 | foreach_init: iterable type =  | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=br setTerminator: block=1, term |
| 1000064 | test_1000064.php | 循环 | 9 | foreach_init: iterable type =  | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=br setTerminator: block=1, term |
| 1000065 | test_1000065.php | 表达式 | 20 | 20 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000066 | test_1000066.php | 表达式 | 150 | 150 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000067 | test_1000067.php | 表达式 | 5 | 5 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000068 | test_1000068.php | 函数 | a,b,c,d | a,b,c,d | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000069 | test_1000069.php | 函数 | 3,2,1 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000070 | test_1000070.php | 函数 | 3 | 3 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000071 | test_1000071.php | 函数 | 9 | 9 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000072 | test_1000072.php | 函数 | 97 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000073 | test_1000073.php | 函数 | F | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000074 | test_1000074.php | 循环 | 6 | foreach_init: iterable type =  | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=br setTerminator: block=1, term |
| 1000075 | test_1000075.php | 循环 | 15 | 15 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=br setTerminator: block=1, term |
| 1000076 | test_1000076.php | 循环 | 120 |  | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=br setTerminator: block=1, term |
| 1000077 | test_1000077.php | 循环 | 2,4,6,8,10,12 |  | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=br setTerminator: block=1, term |
| 1000078 | test_1000078.php | 循环 | found | foreach_init: iterable type =  | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=br setTerminator: block=1, term |
| 1000079 | test_1000079.php | 循环 | 3 | foreach_init: iterable type =  | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=br setTerminator: block=1, term |
| 1000080 | test_1000080.php | 循环 | 45 | foreach_init: iterable type =  | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=br setTerminator: block=1, term |
| 1000081 | test_1000081.php | 函数 | 1,2,3 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000082 | test_1000082.php | 函数 | PHP Warning:  Array to string  | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000083 | test_1000083.php | 函数 | 2 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000084 | test_1000084.php | 函数 | a,b,c | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000085 | test_1000085.php | 函数 | hello | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000086 | test_1000086.php | 循环 | 1,4,9,16,25,36,49,64 |  | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=br setTerminator: block=1, term |
| 1000087 | test_1000087.php | 函数 | 30 | 30 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000088 | test_1000088.php | 函数 | 25 | 25 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000089 | test_1000089.php | 函数 | 40 | 55 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret setTerminator: block=0, ter |
| 1000090 | test_1000090.php | 函数 | 1,4,9,16,25,36,49,64 | 1,2,3,4,5,6,7,8 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret setTerminator: block=0, ter |
| 1000091 | test_1000091.php | 函数 | 43 | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000092 | test_1000092.php | 函数 | abc--- | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000093 | test_1000093.php | 函数 | ---abc | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000094 | test_1000094.php | 函数 | testtesttest | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000095 | test_1000095.php | 函数 | el | el | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000096 | test_1000096.php | 函数 | llo | llo | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000097 | test_1000097.php | 表达式 | 9 | 9 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000098 | test_1000098.php | 函数 | 3 | 0 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000099 | test_1000099.php | 表达式 | 75 | 75 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000100 | test_1000100.php | 表达式 | 23.333333333333 | 23.333333333333332 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000101 | test_1000101.php | 循环 | 15 | 15 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=br setTerminator: block=1, term |
| 1000102 | test_1000102.php | 循环 | 120 | foreach_init: iterable type =  | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=br setTerminator: block=1, term |
| 1000103 | test_1000103.php | 循环 | 3628800 | 3628800 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=br setTerminator: block=1, term |
| 1000104 | test_1000104.php | 循环 | 1,1,2,3,5,8,13,21 |  | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=br setTerminator: block=1, term |
| 1000105 | test_1000105.php | 函数 | 1,2,3,4,5,6,7,8,9 | 1,2,3,4,5,6,7,8,9 | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000106 | test_1000106.php | 函数 | b,a,c | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
| 1000107 | test_1000107.php | 函数 | a,b,c | Bytecode execution failed: Und | [编译失败] | AOT_COMPILE_ERROR | setTerminator: block=0, term=ret Optimizer: Starting optimiz |
