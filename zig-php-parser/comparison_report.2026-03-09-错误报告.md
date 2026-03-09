# PHP AOT 编译器测试对比报告

生成时间: 2026-03-09 22:25:31

## 问题汇总

| 序号 | 脚本路径 | 问题类型 | PHP输出 | AOT输出 | PHP退出码 | AOT退出码 | 详细错误 |
|------|----------|----------|---------|---------|-----------|-----------|----------|
| 19 | /Users/xiusin/Desktop/zig-php/zig-php-parser/tests/simple_benchmark.php | AOT超时 | === Zig-PHP Simple Performance | - | 0 | - | 运行超时 |
| 1 | /Users/xiusin/Desktop/zig-php/zig-php-parser/tests/aot/advanced_features_test.php | 输出不一致 | === Advanced PHP Features Test | === Advanced PHP Features Test | 0 | 1 | 详见下文 |

### 问题 #1: /Users/xiusin/Desktop/zig-php/zig-php-parser/tests/aot/advanced_features_test.php

**问题类型:** 输出不一致

**PHP 输出:**
```
=== Advanced PHP Features Test ===

1. Complex OOP Test:
   Processed: 2, 4, 6, 8, 10
   Process count: 1
   Logs: 1

2. Advanced Closures Test:
   compose(double, addTen)(5) = 30
   pipeline(5) = 90

3. Advanced Array Operations Test:
   High scorers: Alice, Bob, David
   Total score: 272
   Average: 90.666666666667

4. Advanced String Operations Test:
   Original: Hello World! This is a test.
   Words: 6, Chars: 28
   Reversed: test. a is This World! Hello

5. Advanced Recursion Test:
   Unsorted: 64, 34, 25, 12, 22, 11, 90
   Sorted: 11, 12, 22, 25, 34, 64, 90

6. Advanced Exception Handling Test:
   Result 1: 1, 2, 3
   Caught ProcessingException: Array cannot be empty
   Caught ValidationException: Data cannot be null

7. Advanced Type Operations Test:
   integer: 42
   float: 3.14
   string: hello
   bool: true
   array: 3 elements
   null

8. Advanced Control Flow Test:
   Even numbers sum: 20
   Even numbers count: 4
   Average: 5

=== All Advanced Tests Passed ===

```

**AOT 输出:**
```
=== Advanced PHP Features Test ===

1. Complex OOP Test:
   Processed: 0, 0, 0, 0, 0
   Process count: 1
   Logs: 1

2. Advanced Closures Test:
error: InvalidCallback
/Users/xiusin/Desktop/zig-php/zig-php-parser/.zigphp_aot_build/runtime_lib.zig:2467:5: 0x1024ec296 in php_invoke_callable (main)
    return error.InvalidCallback;
    ^
/Users/xiusin/Desktop/zig-php/zig-php-parser/.zigphp_aot_build/main.zig:979:13: 0x1024cbc75 in __closure_10 (main)
        reg_36 = runtime.Value.initNull();
            ^
/Users/xiusin/Desktop/zig-php/zig-php-parser/.zigphp_aot_build/runtime_lib.zig:2429:9: 0x1024ebe8d in php_invoke_callable (main)
        return closure.func(callback, args, allocator);
        ^
/Users/xiusin/Desktop/zig-php/zig-php-parser/.zigphp_aot_build/main.zig:6439:14: 0x10250ff1d in __main__ (main)
/Users/xiusin/Desktop/zig-php/zig-php-parser/.zigphp_aot_build/main.zig:23971:9: 0x102598ee7 in main (main)

```

**PHP 退出码:** 0
**AOT 退出码:** 1

---

## 测试统计

| 指标 | 数值 |
|------|------|
| 总计 | 39 |
| 通过 | 20 |
| 失败 | 19 |
| 超时 | 4 |
| 2 | /Users/xiusin/Desktop/zig-php/zig-php-parser/tests/aot/advanced_simple_test.php | 输出不一致 |  Fatal error: Cannot redeclare | === Advanced Features Test === | 255 | 0 | 详见下文 |

### 问题 #2: /Users/xiusin/Desktop/zig-php/zig-php-parser/tests/aot/advanced_simple_test.php

**问题类型:** 输出不一致

**PHP 输出:**
```

Fatal error: Cannot redeclare function getType() in /Users/xiusin/Desktop/zig-php/zig-php-parser/tests/aot/advanced_simple_test.php on line 129
Stack trace:
#0 {main}
PHP Fatal error:  Cannot redeclare function getType() in /Users/xiusin/Desktop/zig-php/zig-php-parser/tests/aot/advanced_simple_test.php on line 129
Stack trace:
#0 {main}

```

**AOT 输出:**
```
=== Advanced Features Test ===

1. Interface & Abstract Class Test:
   Result: 20
   Logs: 1

2. Higher-Order Functions Test:
   add5(3) = 8
   add10(3) = 13

3. Array Operations Test:
   Evens: 5
   Sum of doubled: 60

4. Quicksort Test:
   Sorted: 1, 2, 3, 5, 8, 9

5. Nested Exception Test:
   Result 1: 10
   Caught inner: Negative value
   Continued after inner catch

6. Type Checking Test:
   getType(42) = int
   getType('hello') = string
   getType([1,2,3]) = array

=== All Tests Passed ===

```

**PHP 退出码:** 255
**AOT 退出码:** 0

---
| 3 | /Users/xiusin/Desktop/zig-php/zig-php-parser/tests/aot/benchmark_constants.php | 输出不一致 | Iterations: 1000000 Time: 8.56 | Iterations: 1000000 Time: 1135 | 0 | 0 | 详见下文 |

### 问题 #3: /Users/xiusin/Desktop/zig-php/zig-php-parser/tests/aot/benchmark_constants.php

**问题类型:** 输出不一致

**PHP 输出:**
```
Iterations: 1000000
Time: 8.5690021514893 ms
Avg per access: 4.2845010757446 ns

```

**AOT 输出:**
```
Iterations: 1000000
Time: 1135.8020305633545 ms
Avg per access: 567.9010152816772 ns

```

**PHP 退出码:** 0
**AOT 退出码:** 0

---
| 4 | /Users/xiusin/Desktop/zig-php/zig-php-parser/tests/aot/benchmark_extreme.php | AOT超时 | Integer add: 83.008050918579ms | - | 0 | - | 运行超时 |
| 5 | /Users/xiusin/Desktop/zig-php/zig-php-parser/tests/aot/benchmark_full.php | 输出不一致 | Constant access: 2.99596786499 | Constant access: 48.0499267578 | 0 | 0 | 详见下文 |

### 问题 #5: /Users/xiusin/Desktop/zig-php/zig-php-parser/tests/aot/benchmark_full.php

**问题类型:** 输出不一致

**PHP 输出:**
```
Constant access: 2.9959678649902ms total, 0.029959678649902ns avg
Constant folding: 2.7010440826416ms total, 0.027010440826416ns avg
Function call: 4.9049854278564ms total, 0.049049854278564ns avg
Loop: 11.91520690918ms total, 0.1191520690918ns avg

```

**AOT 输出:**
```
Constant access: 48.0499267578125ms total, 0.4804992675781ns avg
Constant folding: 45.5420017242432ms total, 0.4554200172424ns avg
Function call: 111.2089157104492ms total, 1.1120891571045ns avg
Loop: 189.5511150360107ms total, 1.8955111503601ns avg

```

**PHP 退出码:** 0
**AOT 退出码:** 0

---
| 6 | /Users/xiusin/Desktop/zig-php/zig-php-parser/tests/aot/benchmark_performance.php | 输出不一致 | === AOT Performance Benchmark  | === AOT Performance Benchmark  | 0 | 0 | 详见下文 |

### 问题 #6: /Users/xiusin/Desktop/zig-php/zig-php-parser/tests/aot/benchmark_performance.php

**问题类型:** 输出不一致

**PHP 输出:**
```
=== AOT Performance Benchmark ===

1. Simple loop (100K): 0.77295303344727ms, sum=100000
2. Nested loop (100x100): 0.069141387939453ms, sum=10000
3. Arithmetic (10K): 0.11801719665527ms, result=20000
4. Array sum (10K): 0.44488906860352ms, sum=15
5. String concat (1K): 0.0059604644775391ms, len=11

Total time: 1.410961151123ms

```

**AOT 输出:**
```
=== AOT Performance Benchmark ===

1. Simple loop (100K): 136.2099647521973ms, sum=100000
2. Nested loop (100x100): 14.1329765319824ms, sum=10000
3. Arithmetic (10K): 13.9379501342773ms, result=20000
4. Array sum (10K): 15.2769088745117ms, sum=15
5. String concat (1K): 9.4139575958252ms, len=11

Total time: 188.971757888794ms

```

**PHP 退出码:** 0
**AOT 退出码:** 0

---
| 7 | /Users/xiusin/Desktop/zig-php/zig-php-parser/tests/aot/closures_advanced.php | 输出不一致 | Counter1: 11 Counter1: 12 Coun | Counter1: 1 Counter1: 1 Counte | 0 | 1 | 详见下文 |

### 问题 #7: /Users/xiusin/Desktop/zig-php/zig-php-parser/tests/aot/closures_advanced.php

**问题类型:** 输出不一致

**PHP 输出:**
```
Counter1: 11
Counter1: 12
Counter2: 101
Mapped: 3, 6, 9, 12, 15
Squared: 1, 4, 9, 16, 25
10 + 5 = 15
Result: start-middle-end
5! = 120

```

**AOT 输出:**
```
Counter1: 1
Counter1: 1
Counter2: 1
Mapped: 3, 6, 9, 12, 15
Squared: 1, 4, 9, 16, 25
error: NotAnObject
/Users/xiusin/Desktop/zig-php/zig-php-parser/.zigphp_aot_build/runtime_lib.zig:6301:9: 0x109ab6fa6 in php_object_get (main)
        return error.NotAnObject;
        ^
/Users/xiusin/Desktop/zig-php/zig-php-parser/.zigphp_aot_build/main.zig:350:13: 0x109a6ff81 in __closure_3 (main)
    reg_3 = try runtime.php_object_get(reg_2, "base");
            ^
/Users/xiusin/Desktop/zig-php/zig-php-parser/.zigphp_aot_build/runtime_lib.zig:2429:9: 0x109a7624d in php_invoke_callable (main)
        return closure.func(callback, args, allocator);
        ^
/Users/xiusin/Desktop/zig-php/zig-php-parser/.zigphp_aot_build/main.zig:1793:14: 0x109a9319d in __main__ (main)
    reg_60 = try runtime.php_invoke_callable(reg_58, &[_]runtime.Value{reg_59}, runtime.runtime_allocator);
             ^
/Users/xiusin/Desktop/zig-php/zig-php-parser/.zigphp_aot_build/main.zig:2621:9: 0x109aa0c17 in main (main)
    _ = try @"__main__"(runtime.Value.initNull(), &[_]runtime.Value{}, allocator);
        ^

```

**PHP 退出码:** 0
**AOT 退出码:** 1

---
| 8 | /Users/xiusin/Desktop/zig-php/zig-php-parser/tests/aot/complex_oop.php | 输出不一致 | [2026-03-09 14:26:36] #1 APP:  | error: ClassNotFound /Users/xi | 0 | 1 | 详见下文 |

### 问题 #8: /Users/xiusin/Desktop/zig-php/zig-php-parser/tests/aot/complex_oop.php

**问题类型:** 输出不一致

**PHP 输出:**
```
[2026-03-09 14:26:36] #1 APP: Application started
[2026-03-09 14:26:36] #2 APP: Processing data
[2026-03-09 14:26:36] #3 APP: Application finished
Total logs: 3
FileLogger instances: 2

```

**AOT 输出:**
```
error: ClassNotFound
/Users/xiusin/Desktop/zig-php/zig-php-parser/.zigphp_aot_build/runtime_lib.zig:6694:49: 0x104f6f173 in php_get_static_property (main)
        break :blk findClass(class_name) orelse return error.ClassNotFound;
                                                ^
/Users/xiusin/Desktop/zig-php/zig-php-parser/.zigphp_aot_build/main.zig:133:17: 0x104f59aeb in TimestampTrait::getTimestamp (main)
        reg_2 = try runtime.php_get_static_property("TimestampTrait", "counter");
                ^
/Users/xiusin/Desktop/zig-php/zig-php-parser/.zigphp_aot_build/runtime_lib.zig:6193:17: 0x104f6c646 in callMethod (main)
                return lookup.method.func(this_val, args, self.allocator);
                ^
/Users/xiusin/Desktop/zig-php/zig-php-parser/.zigphp_aot_build/runtime_lib.zig:6490:5: 0x104f6e4e6 in php_object_call (main)
    return obj.callMethod(method_name, args);
    ^
/Users/xiusin/Desktop/zig-php/zig-php-parser/.zigphp_aot_build/main.zig:447:14: 0x104f58afe in ConsoleLogger::write (main)
    reg_10 = try runtime.php_object_call(reg_9, "getTimestamp", &[_]runtime.Value{});
             ^
/Users/xiusin/Desktop/zig-php/zig-php-parser/.zigphp_aot_build/runtime_lib.zig:6193:17: 0x104f6c646 in callMethod (main)
                return lookup.method.func(this_val, args, self.allocator);
                ^
/Users/xiusin/Desktop/zig-php/zig-php-parser/.zigphp_aot_build/runtime_lib.zig:6490:5: 0x104f6e4e6 in php_object_call (main)
    return obj.callMethod(method_name, args);
    ^
/Users/xiusin/Desktop/zig-php/zig-php-parser/.zigphp_aot_build/main.zig:349:14: 0x104f57f7b in BaseLogger::log (main)
    reg_11 = try runtime.php_object_call(reg_4, "write", &[_]runtime.Value{reg_10});
             ^
/Users/xiusin/Desktop/zig-php/zig-php-parser/.zigphp_aot_build/runtime_lib.zig:6193:17: 0x104f6c646 in callMethod (main)
                return lookup.method.func(this_val, args, self.allocator);
                ^
/Users/xiusin/Desktop/zig-php/zig-php-parser/.zigphp_aot_build/runtime_lib.zig:6490:5: 0x104f6e4e6 in php_object_call (main)
    return obj.callMethod(method_name, args);
    ^
/Users/xiusin/Desktop/zig-php/zig-php-parser/.zigphp_aot_build/main.zig:923:13: 0x104f7081d in __main__ (main)
    reg_4 = try runtime.php_object_call(reg_2, "log", &[_]runtime.Value{reg_3});
            ^
/Users/xiusin/Desktop/zig-php/zig-php-parser/.zigphp_aot_build/main.zig:1453:9: 0x104f7cf4a in main (main)
    _ = try @"__main__"(runtime.Value.initNull(), &[_]runtime.Value{}, allocator);
        ^

```

**PHP 退出码:** 0
**AOT 退出码:** 1

---
| 9 | /Users/xiusin/Desktop/zig-php/zig-php-parser/tests/aot/complex_references_test.php | 输出不一致 | After increment: 6 Array: 1, 2 | After increment: 6 Array: 1, 2 | 0 | 0 | 详见下文 |

### 问题 #9: /Users/xiusin/Desktop/zig-php/zig-php-parser/tests/aot/complex_references_test.php

**问题类型:** 输出不一致

**PHP 输出:**
```
After increment: 6
Array: 1, 2, 3, 4, 5
Counter: 2
Modified array: 10, 99, 30

Test 4 passed!

```

**AOT 输出:**
```
After increment: 6
Array: 1, 2, 3, 4, 5
Counter: 2
Modified array: 10, 20, 30

Test 4 passed!

```

**PHP 退出码:** 0
**AOT 退出码:** 0

---
| 10 | /Users/xiusin/Desktop/zig-php/zig-php-parser/tests/aot/edge_cases_test.php | 输出不一致 | === Edge Cases Test ===  1. Ne | === Edge Cases Test ===  1. Ne | 0 | 0 | 详见下文 |

### 问题 #10: /Users/xiusin/Desktop/zig-php/zig-php-parser/tests/aot/edge_cases_test.php

**问题类型:** 输出不一致

**PHP 输出:**
```
=== Edge Cases Test ===

1. Nested Exception Test:
   Caught inner: Inner exception
   Caught outer: Outer exception

2. Empty Array Test:
   Count: 0
   Filtered count: 0

3. Type Conversion Test:
   0 to bool: false
   '' to bool: false
   null to bool: false

4. String Edge Cases:
   Length: 5
   Substr(0,0): ''
   Substr(5,1): ''

5. Deep Recursion Test:
   Depth 100: 100

6. Closure Capture Test:
   Result: 20 (should be 20, not 40)

7. Array Reference Test:
   Modified: 99

8. Multiple Return Test:
   multiReturn(5): positive
   multiReturn(-5): negative
   multiReturn(0): zero

=== All Edge Cases Passed ===

```

**AOT 输出:**
```
=== Edge Cases Test ===

1. Nested Exception Test:
   Caught inner: Inner exception
   Caught outer: Outer exception

2. Empty Array Test:
   Count: 0
   Filtered count: 0

3. Type Conversion Test:
   0 to bool: false
   '' to bool: false
   null to bool: false

4. String Edge Cases:
   Length: 5
   Substr(0,0): ''
   Substr(5,1): ''

5. Deep Recursion Test:
   Depth 100: 100

6. Closure Capture Test:
   Result: 40 (should be 20, not 40)

7. Array Reference Test:
   Modified: 2

8. Multiple Return Test:
   multiReturn(5): positive
   multiReturn(-5): negative
   multiReturn(0): zero

=== All Edge Cases Passed ===

```

**PHP 退出码:** 0
**AOT 退出码:** 0

---
| 11 | /Users/xiusin/Desktop/zig-php/zig-php-parser/tests/aot/error_handling.php | 输出不一致 | User saved: Alice Success! Val | User saved: Alice Success! Val | 0 | 1 | 详见下文 |

### 问题 #11: /Users/xiusin/Desktop/zig-php/zig-php-parser/tests/aot/error_handling.php

**问题类型:** 输出不一致

**PHP 输出:**
```
User saved: Alice
Success!
Validation error: Validation failed
  - Name must be at least 3 characters
  - Age must be at least 18
Database error: Database connection failed
Resource opened
Caught: Something went wrong
Resource closed
Inner catch: Validation failed
Outer catch: Wrapped error

```

**AOT 输出:**
```
User saved: Alice
Success!
Validation error: Validation failed
  - Name must be at least 3 characters
  - Age must be at least 18
error: NotAnObject
/Users/xiusin/Desktop/zig-php/zig-php-parser/.zigphp_aot_build/runtime_lib.zig:6487:9: 0x10980f7e9 in php_object_call (main)
        return error.NotAnObject;
        ^
/Users/xiusin/Desktop/zig-php/zig-php-parser/.zigphp_aot_build/main.zig:3642:14: 0x10982a3f7 in __main__ (main)
    reg_84 = try runtime.php_object_call(reg_83, "getMessage", &[_]runtime.Value{});
             ^
/Users/xiusin/Desktop/zig-php/zig-php-parser/.zigphp_aot_build/main.zig:5801:9: 0x109841997 in main (main)
    _ = try @"__main__"(runtime.Value.initNull(), &[_]runtime.Value{}, allocator);
        ^

```

**PHP 退出码:** 0
**AOT 退出码:** 1

---
| 12 | /Users/xiusin/Desktop/zig-php/zig-php-parser/tests/aot/minimal_nested_closure.php | 输出不一致 | Result: 6 Expected: 6  | Result: 3 Expected: 6  | 0 | 0 | 详见下文 |

### 问题 #12: /Users/xiusin/Desktop/zig-php/zig-php-parser/tests/aot/minimal_nested_closure.php

**问题类型:** 输出不一致

**PHP 输出:**
```
Result: 6
Expected: 6

```

**AOT 输出:**
```
Result: 3
Expected: 6

```

**PHP 退出码:** 0
**AOT 退出码:** 0

---
| 13 | /Users/xiusin/Desktop/zig-php/zig-php-parser/tests/aot/minimal_ref_test.php | 输出不一致 | Before: 20 After: 99 Expected: | Before: 20 After: 20 Expected: | 0 | 0 | 详见下文 |

### 问题 #13: /Users/xiusin/Desktop/zig-php/zig-php-parser/tests/aot/minimal_ref_test.php

**问题类型:** 输出不一致

**PHP 输出:**
```
Before: 20
After: 99
Expected: 99

```

**AOT 输出:**
```
Before: 20
After: 20
Expected: 99

```

**PHP 退出码:** 0
**AOT 退出码:** 0

---
| 14 | /Users/xiusin/Desktop/zig-php/zig-php-parser/tests/aot/static_property_test.php | 编译失败 | Initial: 0
After increment: 1
 | - | 0 | - | 编译错误 |
| 15 | /Users/xiusin/Desktop/zig-php/zig-php-parser/tests/aot/string_operations.php | 输出不一致 |  Parse error: syntax error, un | Hello, World! Count: 42 Expres | 255 | 0 | 详见下文 |

### 问题 #15: /Users/xiusin/Desktop/zig-php/zig-php-parser/tests/aot/string_operations.php

**问题类型:** 输出不一致

**PHP 输出:**
```

Parse error: syntax error, unexpected token "*", expecting "->" or "?->" or "[" in /Users/xiusin/Desktop/zig-php/zig-php-parser/tests/aot/string_operations.php on line 8
PHP Parse error:  syntax error, unexpected token "*", expecting "->" or "?->" or "[" in /Users/xiusin/Desktop/zig-php/zig-php-parser/tests/aot/string_operations.php on line 8

```

**AOT 输出:**
```
Hello, World! Count: 42
Expression: 84
Hello World
Original: '  PHP is awesome!  '
Trimmed: 'PHP is awesome!'
Upper:   PHP IS AWESOME!  
Lower:   php is awesome!  
Length: 15
Substr(4, 5): quick
Substr(10): brown fox
Substr(-3): fox
Position of 'World': 6
Last position of 'Hello': 12
Contains 'PHP': yes
Hello {name}, you have {count} messages
Fruits: apple | banana | orange | grape
Price: $1234.560000
This is a
multi-line
string with World

Compare 'apple' vs 'banana': -1
Case-insensitive compare: 0
Padded: '00042'
Repeat: **********
Reversed: olleH
Encoded: SGVsbG8gV29ybGQ=
Decoded: Hello World

```

**PHP 退出码:** 255
**AOT 退出码:** 0

---
| 16 | /Users/xiusin/Desktop/zig-php/zig-php-parser/tests/aot/super_complex_test.php | 输出不一致 | === Super Complex Single File  | === Super Complex Single File  | 0 | 1 | 详见下文 |

### 问题 #16: /Users/xiusin/Desktop/zig-php/zig-php-parser/tests/aot/super_complex_test.php

**问题类型:** 输出不一致

**PHP 输出:**
```
=== Super Complex Single File Test ===

1. Complex Inheritance Test:
   Dog: Woof! - Buddy (3 years)
   Breed: Golden Retriever
   Cat: Meow! - Whiskers (2 years)
   Indoor: yes

2. Complex Closure Chain Test:
   pipeline(5) = 25
   Expected: (5 + 10) * 2 - 5 = 25

3. Complex Array Chain Test:
   Result: 60
   Expected: (2+4+6+8+10)*2 = 60

4. Complex Recursion Test:
   fibonacci(5) = 5
   factorial(5) = 120
   combined(5) = 125

5. Complex String Processing Test:
   Text: Hello World PHP AOT Compiler
   Words: 5
   Longest: Compiler (8 chars)

6. Complex Control Flow Test:
   Sum: 55
   Count: 15
   Average: 3.6666666666667

7. Complex Ternary Test:
   classify(0) = zero
   classify(4) = positive even
   classify(5) = positive odd
   classify(-4) = negative even
   classify(-5) = negative odd

=== All Super Complex Tests Passed ===

```

**AOT 输出:**
```
=== Super Complex Single File Test ===

1. Complex Inheritance Test:
   Dog: Woof! - Buddy (3 years)
   Breed: Golden Retriever
   Cat: Meow! - Whiskers (2 years)
   Indoor: yes

2. Complex Closure Chain Test:
error: InvalidCallback
/Users/xiusin/Desktop/zig-php/zig-php-parser/.zigphp_aot_build/runtime_lib.zig:2467:5: 0x1040d6366 in php_invoke_callable (main)
    return error.InvalidCallback;
    ^
/Users/xiusin/Desktop/zig-php/zig-php-parser/.zigphp_aot_build/main.zig:984:13: 0x1040bd6b5 in __closure_14 (main)
    reg_6 = try runtime.php_invoke_callable(reg_4, &[_]runtime.Value{reg_5}, runtime.runtime_allocator);
            ^
/Users/xiusin/Desktop/zig-php/zig-php-parser/.zigphp_aot_build/runtime_lib.zig:2429:9: 0x1040d5f5d in php_invoke_callable (main)
        return closure.func(callback, args, allocator);
        ^
/Users/xiusin/Desktop/zig-php/zig-php-parser/.zigphp_aot_build/main.zig:5066:14: 0x1040f4772 in __main__ (main)
    reg_63 = try runtime.php_invoke_callable(reg_61, &[_]runtime.Value{reg_62}, runtime.runtime_allocator);
             ^
/Users/xiusin/Desktop/zig-php/zig-php-parser/.zigphp_aot_build/main.zig:13309:9: 0x104138387 in main (main)
    _ = try @"__main__"(runtime.Value.initNull(), &[_]runtime.Value{}, allocator);
        ^

```

**PHP 退出码:** 0
**AOT 退出码:** 1

---
| 17 | /Users/xiusin/Desktop/zig-php/zig-php-parser/tests/benchmark_suite.php | AOT超时 | === Zig-PHP Performance Benchm | - | 0 | - | 运行超时 |
| 18 | /Users/xiusin/Desktop/zig-php/zig-php-parser/tests/comprehensive_benchmark.php | AOT超时 | === Zig-PHP Comprehensive Perf | - | 0 | - | 运行超时 |
| 19 | /Users/xiusin/Desktop/zig-php/zig-php-parser/tests/quick_benchmark.php | 输出不一致 | === Quick Performance Benchmar | === Quick Performance Benchmar | 0 | 0 | 详见下文 |

### 问题 #19: /Users/xiusin/Desktop/zig-php/zig-php-parser/tests/quick_benchmark.php

**问题类型:** 输出不一致

**PHP 输出:**
```
=== Quick Performance Benchmark ===

--- Integer ---
Int add: 3 ms (33635156 ops/s)
Int mul: 2.9 ms (34484124 ops/s)
Int cmp: 2.9 ms (34903087 ops/s)

--- Float ---
Float add: 2.9 ms (34083406 ops/s)
Float mul: 3 ms (33235372 ops/s)

--- String ---
strlen: 3.4 ms (29206211 ops/s)
strpos: 5.2 ms (19260247 ops/s)

--- Array ---
Array get: 3.7 ms (27329797 ops/s)
count: 3.4 ms (29289832 ops/s)

--- Object ---
Prop get: 3.7 ms (26759627 ops/s)

--- Function ---
Func call: 4.5 ms (22202657 ops/s)

--- Loop ---
For loop: 8.8 ms (1133933 ops/s)

--- Fibonacci ---
Fib(15): 52.2 ms (19147 ops/s)

=== Total: 99.7 ms ===

```

**AOT 输出:**
```
=== Quick Performance Benchmark ===

--- Integer ---
Int add: 27.9 ms (3578178 ops/s)
Int mul: 29.3 ms (3416698 ops/s)
Int cmp: 28.2 ms (3540334 ops/s)

--- Float ---
Float add: 26.7 ms (3740539 ops/s)
Float mul: 26.7 ms (3742375 ops/s)

--- String ---
strlen: 64.1 ms (1559893 ops/s)
strpos: 141.8 ms (704976 ops/s)

--- Array ---
Array get: 89 ms (1123331 ops/s)
count: 81.2 ms (1231757 ops/s)

--- Object ---
Prop get: 82.8 ms (1208312 ops/s)

--- Function ---
Func call: 59.8 ms (1672043 ops/s)

--- Loop ---
For loop: 600.8 ms (16646 ops/s)

--- Fibonacci ---
Fib(15): 613.9 ms (1629 ops/s)

=== Total: 1872.3 ms ===

```

**PHP 退出码:** 0
**AOT 退出码:** 0

---
| 20 | /Users/xiusin/Desktop/zig-php/zig-php-parser/tests/simple_benchmark.php | AOT超时 | === Zig-PHP Simple Performance | - | 0 | - | 运行超时 |

## 测试统计

| 指标 | 数值 |
|------|------|
| 总计 | 39 |
| 通过 | 19 |
| 失败 | 20 |
| 超时 | 4 |
