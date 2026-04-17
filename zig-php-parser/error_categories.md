# 失败脚本错误归类

| 脚本 | 第一个关键差异 | 类别 |
|------|----------------|------|
| test_001_variables | - | AOT-PARSE-ERROR |
| test_002_operators | - | OUTPUT-DIFF: 19c19\|< XOR: true\|---\|> XOR: 1\| |
| test_003_type_juggling | - | AOT-PARSE-ERROR |
| test_006_loops_for | - | AOT-PARSE-ERROR |
| test_007_loops_while | - | AOT-PARSE-ERROR |
| test_008_loops_foreach | - | OUTPUT-DIFF: 22,23d21\|< x => 10\|< y => 20\|34,35d31\| |
| test_009_functions_basic | - | AOT-PARSE-ERROR |
| test_010_closures | - | OUTPUT-DIFF: 13c13,16\|< bound closure: 2\|---\|> PHP Fatal error:  Call to a member function on a non-object\| |
| test_012_arrays_basic | - | OUTPUT-DIFF: 3,4c3,4\|<   'key1' => 'value1',\|<   'key2' => 'value2',\|---\| |
| test_014_oop_basic | - | OUTPUT-DIFF: 11c11\|< After unset count: 1\|---\|> After unset count: 2\| |
| test_018_magic_methods | - | OUTPUT-DIFF: 19,24c19,23\|< debugInfo: \MagicClass::__set_state(array(\|<    'data' => \|<   array (\| |
| test_021_math_functions | - | OUTPUT-DIFF: 18,56c18,26\|< sinh(0) = 0\|< cosh(0) = 1\|< tanh(0) = 0\| |
| test_023_string_advanced | - | UNDEFINED-FN: undefined function mb_detect_encoding |
| test_029_callback | - | ZIG-COMPILE-ERROR |
| test_030_variables_advanced | - | AOT-PARSE-ERROR |
| test_032_spl_iterators | - | OUTPUT-DIFF: 11,57c11,19\|<   com.apple.ImageIOXPCService\|< EvenFilter:\|<   2\| |
| test_033_namespaces | - | MISSING-PHP-FATAL |
| test_043_fibers_basic | - | OUTPUT-DIFF: 22d21\|< Caught exception: Fiber exception\|24,27c23\|< PHP Warning:  Undefined variable $fiberCurrent in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php- |
| test_047_readonly_props | - | ZIG-COMPILE-ERROR |
| test_048_dnf_types | - | ZIG-COMPILE-ERROR |
| test_049_type_system | - | AOT-PARSE-ERROR |
| test_050_spl_datastructures | - | ZIG-COMPILE-ERROR |
| test_051_closures_advanced | - | ZIG-COMPILE-ERROR |
| test_052_complex_expressions | - | ZIG-COMPILE-ERROR |
| test_053_generators_basic | - | OUTPUT-DIFF: 29,33d28\|< Infinite gen: 0\|< Infinite gen: 1\|< Infinite gen: 2\| |
| test_056_superglobals | - | OUTPUT-DIFF: 1c1\|< GLOBALS testVar: global value\|---\|> GLOBALS testVar: \| |
| test_057_output_buffering | - | OUTPUT-DIFF: 1,3c1,3\|< Buffered content: This is buffered\|< Outer: Outer buffer\|< Inner:  - Inner buffer\| |
| test_059_reflection | - | OUTPUT-DIFF: 4d3\|<   Property: privateProp (private)\|5a5\|>   Property: privateProp (private)\| |
| test_063_sorting_algorithms | - | OUTPUT-DIFF: 5c5\|< Quick sort: 11, 12, 22, 25, 33, 34, 45, 64, 78, 90\|---\|> Quick sort: 90, 78, 90, 64, 90, 78, 90, 45, 90, 78, 90, 64, 90, 78, 90, 34, 90, 78, 90, |
| test_064_string_manipulation | - | OUTPUT-DIFF: 7c7,10\|< mb_detect_encoding: ASCII\|---\|> PHP Fatal error:  Uncaught Error: Call to undefined function mb_detect_encoding() in /Users/tuoke/Desktop/ai- |
| test_065_array_walk | - | OUTPUT-DIFF: 7,9c7,9\|< Filtered: 3, 4, 5\|< Reduced sum: 15\|< Reduced product: 120\| |
| test_068_misc_functions | - | OUTPUT-DIFF: 16c16\|< resource: is_int=false, is_float=false, is_string=false\|---\|> resource: is_int=true, is_float=false, is_string=false\| |
