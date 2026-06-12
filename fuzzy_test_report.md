# AOT模糊测试报告

测试时间: 2026-04-17 17:33:59


### test_001_variables.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `a=42 b=3.14159 c='hello world' d=true e=NULL f=array (   0 => 1,   1 => 2,   2 => 3, ) g=array (   'key' => 'value',   'num' => 123, ) dynamic=dynamic indirect=indirect ` |
| AOT输出 | ` Parse error: Unexpected token in expression in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_001_variables.php on line 12 PHP Parse error:  Unexpected token in expression in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_001_variables.php on line 12 ` |

### test_002_operators.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `加法: 13 减法: 7 乘法: 30 除法: 3.3333333333333 取模: 1 幂运算: 1000 相等: false 全等: false 不等: true 不全等: true 大于: true 小于: false 大于等于: true 小于等于: false 太空船: 1 AND: false OR: true NOT: false XOR: true 按位与: 15 按位或: 255 按位异或: 255 按位非: -1 左移: 16 右移: 4 +=: 150 -=: 125 *=: 250 /=: 50 %=: 1 **=: 1 字符串拼接: Hello World .=: Hello PHP 数组联合: array (   'a' => 1,   'b' => 2,   'c' => 4, ) 数组相等` |
| AOT输出 | `加法: 13 减法: 7 乘法: 30 除法: 3.3333333333333 取模: 1 幂运算: 1000 相等: false 全等: false 不等: true 不全等: true 大于: true 小于: false 大于等于: true 小于等于: false 太空船: 1 AND: false OR: true NOT: false XOR: 1 按位与: 15 按位或: 255 按位异或: 255 按位非: -1 左移: 16 右移: 4 +=: 150 -=: 125 *=: 250 /=: 50 %=: 1 **=: 1 字符串拼接: Hello World .=: Hello PHP PHP Fatal error:  Uncaught TypeError: Unsupported operand types: array + ar` |

### test_003_type_juggling.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `字符串+数字: 8 数字+字符串: 30 PHP Fatal error:  Uncaught TypeError: Unsupported operand types: string + int in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_003_type_juggling.php:7 Stack trace: #0 {main}   thrown in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_003_type_juggling.php on line 7  Fatal error: Uncaught TypeError: Unsupported operand types: string + int in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scri` |
| AOT输出 | ` Parse error: Unexpected token in expression in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_003_type_juggling.php on line 12 PHP Parse error:  Unexpected token in expression in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_003_type_juggling.php on line 12 ` |

### test_006_loops_for.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `基础循环: 0 1 2 3 4  多变量: i=0, j=10 i=1, j=9 i=2, j=8 i=3, j=7 i=4, j=6 break测试: 0 1 2 3 4  continue测试: 1 3 5 7 9  嵌套循环: 1 2 3  2 4 6  3 6 9  替代语法: item0 item1 item2 复杂表达式: arr[0]=10 arr[1]=20 arr[2]=30 arr[3]=40 arr[4]=50 函数调用: iteration 0 iteration 1 iteration 2 省略初始化: 0 1 2  省略条件: 0 1 2  省略递增: 3 2 1  空for体: done 双重break: (0,0) (0,1)  ` |
| AOT输出 | ` Parse error: Unexpected token in expression in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_006_loops_for.php on line 88 PHP Parse error:  Unexpected token in expression in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_006_loops_for.php on line 88 ` |

### test_007_loops_while.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `基础while: 0 1 2 3 4  while替代语法: item0 item1 item2 while+break: 0 1 2 3  while+continue: 1 3 5 7 9  嵌套while: 1 2 3  2 4 6  3 6 9  do-while: 0 1 2 3 4  do-while至少执行一次: executed once 复杂条件: count=1, sum=1 count=2, sum=3 count=3, sum=6 count=4, sum=10 count=5, sum=15 count=6, sum=21 count=7, sum=28 count=8, sum=36 count=9, sum=45 count=10, sum=55 函数条件: val=0 val=1 val=2 空while: done break层级: (0,0) (0,1) (0,2) (1,0)  ` |
| AOT输出 | ` Parse error: Unexpected token in expression in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_007_loops_while.php on line 19 PHP Parse error:  Unexpected token in expression in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_007_loops_while.php on line 19 ` |

### test_008_loops_foreach.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `索引数组: apple banana cherry  带键遍历: 0: apple 1: banana 2: cherry 关联数组: name => John age => 30 city => NYC 修改值: 2, 4, 6, 8, 10 替代语法: [0] = a [1] = b [2] = c 嵌套foreach: 1 2 3  4 5 6  7 8 9  对象遍历: x => 10 y => 20 遍历+break: 1 2 3 4 5  遍历+continue: 1 2 4 5 7 8 10  空数组: done 修改数组: i=0, val=1 i=1, val=2 i=2, val=3 i=3, val=4 i=4, val=5 list解构: 1 => a 2 => b 3 => c 带键list解构: [0] 1 => a [1] 2 => b [2] 3 => c ` |
| AOT输出 | `索引数组: apple banana cherry  带键遍历: 0: apple 1: banana 2: cherry 关联数组: name => John age => 30 city => NYC 修改值: 2, 4, 6, 8, 10 替代语法: [0] = a [1] = b [2] = c 嵌套foreach: 1 2 3  4 5 6  7 8 9  对象遍历: 遍历+break: 1 2 3 4 5  遍历+continue: 1 2 4 5 7 8 10  空数组: done 修改数组: i=0, val=1 i=1, val=2 i=2, val=3 list解构: 1 => a 2 => b 3 => c 带键list解构: [0] 1 => a [1] 2 => b [2] 3 => c ` |

### test_009_functions_basic.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP Fatal error:  Can't use function return value in write context in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_009_functions_basic.php on line 63  Fatal error: Can't use function return value in write context in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_009_functions_basic.php on line 63 ` |
| AOT输出 | ` Parse error: Unexpected token in expression in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_009_functions_basic.php on line 113 PHP Parse error:  Unexpected token in expression in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_009_functions_basic.php on line 113 ` |

### test_010_closures.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `Hello, Closure! Hello, World! count after closure: 3 value after modification: 15 squared: 1, 4, 9, 16, 25 evens: 2, 4 sum: 15 double(5) = 10 triple(5) = 15 counter1: 1, 2 counter2: 1 closure with this: 42 bound closure: 2 add(3,2) = 5 sub(3,2) = 1 mul(3,2) = 6 nested(3) = 6 execute: 5 execute closure: 42 ` |
| AOT输出 | `Hello, Closure! Hello, World! count after closure: 3 value after modification: 15 squared: 1, 4, 9, 16, 25 evens: 2, 4 sum: 15 double(5) = 10 triple(5) = 15 counter1: 1, 2 counter2: 1 closure with this: 42 PHP Fatal error:  Call to a member function on a non-object  Fatal error: Call to a member function on a non-object bound closure:  add(3,2) = 5 sub(3,2) = 1 mul(3,2) = 6 nested(3) = 6 execute: 5 execute closure: 42 ` |

### test_012_arrays_basic.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `arr3: 1, 2, 3, 4, 5 arr5: array (   'key1' => 'value1',   'key2' => 'value2', ) arr3[0]: 1 arr5['key1']: value1 modified arr3[0]: 100 modified arr5['key1']: modified appended arr3: 100, 2, 3, 4, 5, 6 count: 6 sizeof: 6 is_array: true array_key_exists: true in_array: true isset: true array_keys: key1, key2, key3 array_values: modified, value2, value3 after push: 1, 2, 3, 4, 5 popped: 5, remaining: 1, 2, 3, 4 after unshift: 0, 1, 2, 3 shifted: 0, remaining: 1, 2, 3 array_search: 0 array_search not` |
| AOT输出 | `arr3: 1, 2, 3, 4, 5 arr5: array (     'key1' => 'value1',     'key2' => 'value2', ) arr3[0]: 1 arr5['key1']: value1 modified arr3[0]: 100 modified arr5['key1']: modified appended arr3: 100, 2, 3, 4, 5, 6 count: 6 sizeof: 6 is_array: true array_key_exists: true in_array: true isset: true array_keys: key1, key2, key3 array_values: modified, value2, value3 after push: 1, 2, 3, 4, 5 popped: 5, remaining: 1, 2, 3, 4 after unshift: 0, 1, 2, 3 shifted: 0, remaining: 1, 2, 3 array_search: 0 array_search` |

### test_014_oop_basic.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `Hello, I'm Alice, 25 years old. Hello, I'm Bob, 30 years old. Name: Alice Age: 25 Species: Human Count: 2 Static count: 2 Secret: hidden New secret: new secret is Person: true After unset count: 1 Owner before: NULL Owner after: Alice Hello from anonymous class! Anonymous value: Test Typed int: 42 Typed float: 3.14 Typed string: hello Typed bool: true Typed array count: 3 ` |
| AOT输出 | `Hello, I'm Alice, 25 years old. Hello, I'm Bob, 30 years old. Name: Alice Age: 25 Species: Human Count: 2 Static count: 2 Secret: hidden New secret: new secret is Person: true After unset count: 2 Owner before: NULL Owner after: Alice Hello from anonymous class! Anonymous value: Test Typed int: 42 Typed float: 3.14 Typed string: hello Typed bool: true Typed array count: 3 ` |

### test_017_oop_trait.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `[LOG] Doing something at 2026-04-17 09:34:26 [LOG] Running... conflict from A: A conflict from B: B now public: secret also public: internal Trait property: trait value Modified: modified Value: concrete value Counter: 1 Counter: 2 Total: 2 [LOG] Nested trait call ` |
| AOT输出 | `[LOG] Doing something at 2026-04-17 09:34:28 [LOG] Running... conflict from A: A conflict from B: B now public: secret also public: internal Trait property: trait value Modified: modified Value: concrete value Counter: 1 Counter: 2 Total: 2 [LOG] Nested trait call ` |

### test_018_magic_methods.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `__construct called with TestObject __set called for dynamicProp = 'dynamic value' __get called for dynamicProp dynamicProp: dynamic value __isset called for dynamicProp isset check: true __unset called for dynamicProp __isset called for dynamicProp after unset: false __call called for dynamicMethod with args: arg1, arg2 dynamicMethod: dynamic method result __callStatic called for staticDynamic staticDynamic: static dynamic method result toString: MagicClass(TestObject) __invoke called with test ` |
| AOT输出 | `__construct called with TestObject __set called for dynamicProp = 'dynamic value' __get called for dynamicProp dynamicProp: dynamic value __isset called for dynamicProp isset check: true __unset called for dynamicProp __isset called for dynamicProp after unset: false __call called for dynamicMethod with args: arg1, arg2 dynamicMethod: dynamic method result __callStatic called for staticDynamic staticDynamic: static dynamic method result toString: MagicClass(TestObject) __invoke called with test ` |

### test_021_math_functions.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `abs(-5) = 5 ceil(4.3) = 5 floor(4.7) = 4 round(4.5) = 5 round(4.4) = 4 pow(2, 10) = 1024 2 ** 10 = 1024 exp(1) = 2.718281828459 log(M_E) = 1 log10(100) = 2 sqrt(16) = 4 sin(0) = 0 cos(0) = 1 tan(M_PI_4) = 1 asin(1) = 1.5707963267949 acos(0) = 1.5707963267949 atan(1) = 0.78539816339745 sinh(0) = 0 cosh(0) = 1 tanh(0) = 0 decbin(10) = 1010 dechex(255) = ff decoct(8) = 10 bindec('1010') = 10 hexdec('FF') = 255 octdec('10') = 8 base_convert('FF', 16, 2) = 11111111 max(1, 5, 3) = 5 min(1, 5, 3) = 1 m` |
| AOT输出 | `abs(-5) = 5 ceil(4.3) = 5 floor(4.7) = 4 round(4.5) = 5 round(4.4) = 4 pow(2, 10) = 1024 2 ** 10 = 1024 exp(1) = 2.718281828459 log(M_E) = 1 log10(100) = 2 sqrt(16) = 4 sin(0) = 0 cos(0) = 1 tan(M_PI_4) = 1 asin(1) = 1.5707963267949 acos(0) = 1.5707963267949 atan(1) = 0.78539816339745 PHP Fatal error:  Uncaught Error: Call to undefined function sinh() in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_021_math_functions.php:28 Stack trace: #0 {main}   thrown in /Users/tu` |

### test_023_string_advanced.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `strlen: 17 mb_strlen: 9 mb_substr: 你好 mb_detect_encoding: UTF-8 mb_strtolower: hello world mb_strtoupper: HELLO WORLD strpos: 16 strrpos: 41 stripos: 16 strripos: 41 strstr: fox jumps over the lazy dog stristr: fox jumps over the lazy dog strrchr:  dog str_replace count: 4 replacements substr_count: 4 substr_replace: The SLOW brown fox jumps over the lazy dog preg_replace: hello-world preg_replace callback: 2, 4, 6 preg_split: a\|b\|c str_split: he\|ll\|o preg_match: hello world, hello, world pr` |
| AOT输出 | `strlen: 17 mb_strlen: 9 mb_substr: 你好 PHP Fatal error:  Uncaught Error: Call to undefined function mb_detect_encoding() in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_023_string_advanced.php:12 Stack trace: #0 {main}   thrown in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_023_string_advanced.php on line 12  Fatal error: Uncaught Error: Call to undefined function mb_detect_encoding() in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-pa` |

### test_029_callback.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `double: 10 square: 25 uppercase: HELLO static method: 15 static method alt: 15 instance method: 7 closure: 15 reduce sum: 15 array_map: 1, 4, 9, 16, 25 array_filter: 2, 4 array_reduce: 120 sorted by age: Bob, Alice, Charlie sumAll: 15 sorted by id: A, B, C multiplier 1: 15 multiplier 2: 20 is_callable valid: true is_callable invalid: false invokable: 27 is_callable invokable: true ` |
| AOT输出 | `double: 10 square: 25 uppercase: HELLO error: UnknownFunction /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/.zigphp_aot_build/runtime_lib.zig:24354:9: 0x104febc63 in php_call_user_func (main)         return error.UnknownFunction;         ^ /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/.zigphp_aot_build/main.zig:3115:14: 0x105005833 in __main__ (main)     reg_30 = try runtime.php_call_user_func(&[_]runtime.Value{reg_26, reg_29}, runtime.runtime_allocator);              ^ /Users/tu` |

### test_030_variables_advanced.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP Fatal error:  Can't use function return value in write context in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_030_variables_advanced.php on line 88  Fatal error: Can't use function return value in write context in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_030_variables_advanced.php on line 88 ` |
| AOT输出 | ` Parse error: Unexpected token in expression in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_030_variables_advanced.php on line 18 PHP Parse error:  Unexpected token in expression in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_030_variables_advanced.php on line 18 ` |

### test_032_spl_iterators.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `ArrayIterator:   0 => a   1 => b   2 => c   3 => d   current: a   current: b   current: c   current: d DirectoryIterator on temp dir:   com.apple.ImageIOXPCService EvenFilter:   2   4   6   8   10 LimitIterator (5-9):   f   g   h   i   j IteratorIterator:   x   y   z RecursiveIteratorIterator:   a => 1   c => 2   e => 3 CachingIterator:   cached: 1, 2, 3 InfiniteIterator (limited):   a   b   c   a   b   c NoRewindIterator first pass:   1   2   3 NoRewindIterator second pass: AppendIterator:   1 ` |
| AOT输出 | `ArrayIterator:   0 => a   1 => b   2 => c   3 => d   current: a   current: b   current: c   current: d DirectoryIterator on temp dir: PHP Fatal error:  Uncaught Error: Class "DirectoryIterator" not found in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_032_spl_iterators.php:21 Stack trace: #0 {main}   thrown in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_032_spl_iterators.php on line 21  Fatal error: Uncaught Error: Class "DirectoryIterator` |

### test_033_namespaces.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP Fatal error:  Cannot mix bracketed namespace declarations with unbracketed namespace declarations in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_033_namespaces.php on line 25  Fatal error: Cannot mix bracketed namespace declarations with unbracketed namespace declarations in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_033_namespaces.php on line 25 ` |
| AOT输出 | ` Parse error: syntax error, unexpected "{", expecting ";" in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_033_namespaces.php on line 83 PHP Parse error:  syntax error, unexpected "{", expecting ";" in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_033_namespaces.php on line 83 ` |

### test_039_union_types.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `int result: 10 float result: 6.28 Integer: 42 Float: 3.14 String: hello found: 'Item 1' null: NULL handle A: A handle B: B process FileHandler: test data process MemoryHandler: test data int return: integer string return: string int id: 1 string id: abc complex array: array complex bool: bool complex null: null Factory type: Concrete mixed int: 42 mixed array: array (   0 => 1,   1 => 2,   2 => 3, ) Union types tests completed ` |
| AOT输出 | `int result: 10 float result: 6.28 Integer: 42 Float: 3.14 String: hello found: 'Item 1' null: NULL handle A: A handle B: B process FileHandler: test data process MemoryHandler: test data int return: integer string return: string int id: 1 string id: abc complex array: array complex bool: bool complex null: null Factory type: Concrete mixed int: 42 mixed array: array (     0 => 1,     1 => 2,     2 => 3, ) Union types tests completed ` |

### test_047_readonly_props.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `User: Alice <alice@example.com> Updated email: alice.new@example.com Distance: 5 New point x: 5 Product: Widget costs $19.99 Debug: true Missing: 'default' Col1 count: 3 Col2 count: 4 Delayed: initialized Container content exists: true Empty container: true Readonly properties tests completed ` |
| AOT输出 | `User: Alice <alice@example.com> Updated email: alice.new@example.com Distance: 5 New point x: 5 PHP Fatal error:  Uncaught Error: Class "DateTimeImmutable" not found in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_047_readonly_props.php:71 Stack trace: #0 {main}   thrown in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_047_readonly_props.php on line 71  Fatal error: Uncaught Error: Class "DateTimeImmutable" not found in /Users/tuoke/Desktop/` |

### test_048_dnf_types.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP Parse error:  syntax error, unexpected token "&", expecting variable in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_048_dnf_types.php on line 59  Parse error: syntax error, unexpected token "&", expecting variable in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_048_dnf_types.php on line 59 ` |
| AOT输出 | ` Parse error: syntax error, unexpected "(", expecting "token" in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_048_dnf_types.php on line 69 PHP Parse error:  syntax error, unexpected "(", expecting "token" in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_048_dnf_types.php on line 69 ` |

### test_049_type_system.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP Fatal error:  strict_types declaration must be the very first statement in the script in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_049_type_system.php on line 37  Fatal error: strict_types declaration must be the very first statement in the script in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_049_type_system.php on line 37 ` |
| AOT输出 | ` Parse error: Unexpected token in expression in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_049_type_system.php on line 37 PHP Parse error:  Unexpected token in expression in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_049_type_system.php on line 37 ` |

### test_050_spl_datastructures.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `SplFixedArray[2]: 20 SplFixedArray count: 5 DLL top: c DLL bottom: start DLL pop: c DLL shift: start Stack top: 3 Stack pop: 3 Stack count: 2 Queue bottom: first Queue dequeue: first Queue count: 2 MinHeap top: 1 After extract: 2 MaxHeap top: 8 Priority top: high Storage contains obj1: true Storage count: 2 After detach count: 1 toArray: a, b, c FIFO mode:   1   2   3 LIFO mode:   3   2   1 After resize: 3 SPL data structure tests completed ` |
| AOT输出 | `SplFixedArray[2]: 20 SplFixedArray count: 5 PHP Fatal error:  Uncaught Error: Class "SplDoublyLinkedList" not found in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_050_spl_datastructures.php:13 Stack trace: #0 {main}   thrown in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_050_spl_datastructures.php on line 13  Fatal error: Uncaught Error: Class "SplDoublyLinkedList" not found in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_s` |

### test_051_closures_advanced.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `First increment: 1 Second increment: 2 Counter count: 2 Private value: secret Bound factor: 2 call result: secret fromCallable: 7 static closure add: 8 mul: 15 Curried result: 6 Memoized 1: 25 Memoized 2 (cached): 25 Composed: Result: 11 Advanced closures tests completed ` |
| AOT输出 | ` Parse error: syntax error, unexpected token, expecting ";" in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_051_closures_advanced.php on line 72 PHP Parse error:  syntax error, unexpected token, expecting ";" in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_051_closures_advanced.php on line 72 ` |

### test_052_complex_expressions.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP Parse error:  syntax error, unexpected token "if", expecting "=>" in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_052_complex_expressions.php on line 101  Parse error: syntax error, unexpected token "if", expecting "=>" in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_052_complex_expressions.php on line 101 ` |
| AOT输出 | ` Parse error: syntax error, unexpected token, expecting "token" in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_052_complex_expressions.php on line 101 PHP Parse error:  syntax error, unexpected token, expecting "token" in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_052_complex_expressions.php on line 101 ` |

### test_056_superglobals.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `GLOBALS testVar: global value newGlobal: new value PHP_VERSION: 8.4.8 PHP_OS: Darwin PHP_SAPI: cli PHP_INT_MAX: 9223372036854775807 APP_NAME: TestApp APP_VERSION: 1.0.0 __LINE__: 24 __FILE__: test_056_superglobals.php __DIR__: fuzzy_scripts __FUNCTION__: testMagicConstants __NAMESPACE__: global __CLASS__: MagicTest __METHOD__: MagicTest::show PHP_EOL exists: true PHP_INT_SIZE: 8 TRUE: true FALSE: false NULL: NULL User constants: 2 HOME env: tuoke ENV is empty Running in CLI mode GLOBALS exists: ` |
| AOT输出 | `GLOBALS testVar:  newGlobal: new value PHP_VERSION: 8.3.0 PHP_OS: Darwin PHP_SAPI: cli PHP_INT_MAX: 9223372036854775807 APP_NAME: TestApp APP_VERSION: 1.0.0 __LINE__: 24 __FILE__: test_056_superglobals.php __DIR__: fuzzy_scripts __FUNCTION__: testMagicConstants __NAMESPACE__: global __CLASS__: MagicTest __METHOD__: MagicTest::MagicTest::show PHP_EOL exists: true PHP_INT_SIZE: 8 TRUE: true FALSE: false NULL: NULL PHP Fatal error:  Uncaught Error: Call to undefined function get_defined_constants()` |

### test_057_output_buffering.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `Buffered content: This is buffered Outer: Outer buffer Inner:  - Inner buffer Initial level: 0 Level after clean: 0 Uppercased: lowercase content Buffer length was: 5 Content1: Content A Content2: Content A + Content B All cleaned, level: 0 Conditional: Conditional output Template result: Alice is 25 years old gzhandler available Output buffering tests completed ` |
| AOT输出 | `This is bufferedBuffered content:  Outer buffer - Inner bufferOuter:  Inner:  Initial level: 0 Level after start: 1 Level after clean: 0 Status name: default output handler lowercase contentUppercased:  To be flushed12345Buffer length was: 0 Content A + Content BContent1:  Content2:  Nested buffers: 3 All cleaned, level: 0 Conditional outputConditional:  PHP Fatal error:  Uncaught Error: Call to undefined function eval() in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test` |

### test_059_reflection.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `Class name: SampleClass Is instantiable: true Properties count: 3   Property: privateProp (private)   Property: protectedProp (protected)   Property: publicProp (public) Methods count: 3   Method: __construct   Method: publicMethod   Method: privateMethod Instance created: 'custom value' Function name: strlen Number of params: 1 Param: param1 Param: param2 (optional, default: 'default') Core extension functions: 59 Constant value: constant value Private method invoked Private prop value: private` |
| AOT输出 | `Class name: SampleClass Is instantiable: true Properties count: 3   Property: protectedProp (protected)   Property: privateProp (private)   Property: publicProp (public) Methods count: 3   Method: __construct   Method: publicMethod   Method: privateMethod Instance created: 'custom value' Function name: strlen Number of params: 0 Param: param1 Param: param2 PHP Fatal error:  Uncaught Error: Class "ReflectionExtension" not found in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_script` |

### test_063_sorting_algorithms.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `Built-in sort: 11, 12, 22, 25, 33, 34, 45, 64, 78, 90 Bubble sort: 11, 12, 22, 25, 33, 34, 45, 64, 78, 90 Selection sort: 11, 12, 22, 25, 33, 34, 45, 64, 78, 90 Insertion sort: 11, 12, 22, 25, 33, 34, 45, 64, 78, 90 Quick sort: 11, 12, 22, 25, 33, 34, 45, 64, 78, 90 Merge sort: 11, 12, 22, 25, 33, 34, 45, 64, 78, 90 Heap sort: 11, 12, 22, 25, 33, 34, 45, 64, 78, 90  Validation:   bubble: OK   selection: OK   insertion: OK   quick: OK   merge: OK   heap: OK  Sorting tests completed ` |
| AOT输出 | `Built-in sort: 11, 12, 22, 25, 33, 34, 45, 64, 78, 90 Bubble sort: 11, 12, 22, 25, 33, 34, 45, 64, 78, 90 Selection sort: 11, 12, 22, 25, 33, 34, 45, 64, 78, 90 Insertion sort: 11, 12, 22, 25, 33, 34, 45, 64, 78, 90 Quick sort: 90, 78, 90, 64, 90, 78, 90, 45, 90, 78, 90, 64, 90, 78, 90, 34, 90, 78, 90, 64, 90, 78, 90, 45, 90, 78, 90, 64, 90, 78, 90, 33, 90, 78, 90, 64, 90, 78, 90, 45, 90, 78, 90, 64, 90, 78, 90, 34, 90, 78, 90, 64, 90, 78, 90, 45, 90, 78, 90, 64, 90, 78, 90, 25, 90, 78, 90, 64, ` |

### test_064_string_manipulation.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Multibyte String === strlen: 23 mb_strlen: 12 mb_substr: 你好世  === Encoding === mb_detect_encoding: ASCII  === Case Conversion === strtolower: hello world strtoupper: HELLO WORLD ucfirst: HeLLo WoRLd lcfirst: heLLo WoRLd ucwords: Hello World mb_strtolower: ß mb_strtoupper: SS  === String Search === strpos 'fox': 16 strrpos 'o': 41 stripos 'FOX': 16 strripos 'O': 41  === String Extract === substr(4, 5): quick substr(-8): lazy dog strstr 'fox': fox jumps over the lazy dog stristr 'FOX': ` |
| AOT输出 | `=== Multibyte String === strlen: 23 mb_strlen: 12 mb_substr: 你好世  === Encoding === PHP Fatal error:  Uncaught Error: Call to undefined function mb_detect_encoding() in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_064_string_manipulation.php:14 Stack trace: #0 {main}   thrown in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_064_string_manipulation.php on line 14  Fatal error: Uncaught Error: Call to undefined function mb_detect_encoding` |

### test_065_array_walk.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `Before walk: 1, 2, 3 After walk: 2, 4, 6 After walk with data: 20, 40, 60 Flattened: 1, 2, 3, 4 array_map: 1, 4, 9, 16, 25 array_walk: 1, 4, 9, 16, 25 Filtered: 3, 4, 5 Reduced sum: 15 Reduced product: 120 Names: Alice, Bob, Charlie Total age: 90 Multi-array sums: 12, 15, 18 Transposed rows: 3 Sorted by price: Thing, Widget, Gadget array_walk tests completed ` |
| AOT输出 | `Compile Error: main.zig:9697:10: error: cannot dereference non-pointer type 'runtime_lib.Value'     reg_0.* = reg_2;     ~~~~~^~ runtime_lib.zig:2014:19: note: struct declared here pub const Value = struct {                   ^~~~~~ referenced by:     registerAllFunctions: main.zig:10626:65     main: main.zig:11624:25     4 reference(s) hidden; use '-freference-trace=6' to see all references main.zig:9765:10: error: cannot dereference non-pointer type 'runtime_lib.Value'     reg_0.* = reg_3;    ` |

### test_068_misc_functions.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Variable Functions === isset: true empty: false is_null: false gettype: string gettype null: NULL  === Type Check Functions === int: is_int=true, is_float=false, is_string=false float: is_int=false, is_float=true, is_string=false string: is_int=false, is_float=false, is_string=true bool: is_int=false, is_float=false, is_string=false array: is_int=false, is_float=false, is_string=false object: is_int=false, is_float=false, is_string=false null: is_int=false, is_float=false, is_string=false re` |
| AOT输出 | `=== Variable Functions === isset: true empty: false is_null: false gettype: string gettype null: NULL  === Type Check Functions === int: is_int=true, is_float=false, is_string=false float: is_int=false, is_float=true, is_string=false string: is_int=false, is_float=false, is_string=true bool: is_int=false, is_float=false, is_string=false array: is_int=false, is_float=false, is_string=false object: is_int=false, is_float=false, is_string=false null: is_int=false, is_float=false, is_string=false re` |

## 测试统计

| 统计项 | 数量 |
|--------|------|
| 总计 | 44 |
| 通过 | 10 |
| 失败 | 32 |
| 跳过 | 2 |
