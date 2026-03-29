# AOT测试报告

测试时间: 2026-03-29 21:41:32

### test_001_complex_oop.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: PHP Fatal error:  Cannot redeclare interface Serializable in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_001_complex_oop.php on line 13

Fatal error:` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: Type: User
Username: admin
Email count: 2
Virtual: virtual_1
Logs:
  2026-03-29 13:41:35: Entity created: 1
  2026-03-29 13:41:35: User constructed: admin
  2026-03-29 13:41:35: ` |

### test_002_type_juggling.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `--- Testing: '123' ---
Original: '123'
As int: 123 (type: integer)
As float: 123 (type: double)
As string: 123 (type: string)
As bool: true (type: boolean)
As array: 1 elements
As object: stdClass
Str` |
| AOT输出 | `--- Testing: '123' ---
Original: '123'
As int: 123 (type: integer)
As float: 123 (type: double)
As string: 123 (type: string)
As bool: true (type: boolean)
As array: 1 elements
As object: stdClass
Str` |

### test_003_advanced_oop.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `Result: 65.477225575052
Calculator[value=30]
Instance count: 1
Factorial of 5: 120
Array
(
    [0] => 2026-03-29 13:41:38: Calculator created with value: 10
    [1] => 2026-03-29 13:41:38: Added: 5
  ` |
| AOT输出 | `Result: 65.477225575052
Calculator[value=30]
Instance count: 1
Factorial of 5: 120
Array
(
    [0] => 2026-03-29 13:41:41: Calculator created with value: 10
    [1] => 2026-03-29 13:41:41: Added: 5
  ` |

### test_003_closures.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: Double(5): 10
Add(5): 15
PHP Fatal error:  Uncaught Error: Object of class Closure could not be converted to string in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: Double(5): 10
Add(5): 15
Outer(3)(7): 
PHP Fatal error:  Uncaught Exception: Object of class Closure could not be converted to string in /Users/tuoke/Desktop/ai-zig-php-parser/zi` |

### test_004_strings.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: PHP Fatal error:  Uncaught Error: Call to undefined function rot13() in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_004_strings.php:31
Stack trace:
#` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: PHP Fatal error:  Uncaught Error: Call to undefined function rot13() in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_004_strings.php:31
Stack trace:
#` |

### test_005_arrays.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: === Test 0: [1,2,3,4,5] ===
Count: 5
Is array: yes
Is list: yes
Keys: 0,1,2,3,4
Values: 1,2,3,4,5
Diff with [a,b,c]: 1,2,3,4,5
Intersect with [a,b,c]: 
Filtered (numeric > 2): 3,` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: === Test 0: [1,2,3,4,5] ===
Count: 5
Is array: yes
Is list: yes
Keys: 0,1,2,3,4
Values: 1,2,3,4,5
Diff with [a,b,c]: 1,2,3,4,5
Intersect with [a,b,c]: 
Filtered (numeric > 2): 3,` |

### test_006_exceptions.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `Test 1: Division by zero
Caught: DivisionByZeroError: Division by zero
Test 2: Safe division
10/2 = 5
Caught division by zero: Cannot divide by zero
Test 3: JSON throw on error
Parsed: {"valid":true}` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: Test 1: Division by zero
Caught: DivisionByZeroError: Division by zero
Test 2: Safe division
10/2 = 5
Caught division by zero: Cannot divide by zero
Test 3: JSON throw on error
P` |

### test_007_enums.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `Status::Active->value: active
Status::Active->label(): Active Status
Status::Active->isActive(): true
Status::Pending->isActive(): false

e1->getLabel(): [Test1] Active Status
e2->getLabel(): [Test2] ` |
| AOT输出 | `Status::Active->value: active
Status::Active->label(): Active Status
Status::Active->isActive(): true
Status::Pending->isActive(): false

e1->getLabel(): [Test1] Active Status
e2->getLabel(): [Test2] ` |

### test_007_error_handling.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `Processed: 10, 2
Processed: 10, 0
Processed: -5, 2
Processed: 100, 10
Caught: Wrapped: Inner error
Error [512]: Custom warning
Array
(
    [0] => 5
    [1] => InvalidArg: Division by zero!
    [2] => ` |
| AOT输出 | `Processed: 10, 2
Processed: 10, 0
Processed: -5, 2
Processed: 100, 10
Caught: Wrapped: Inner error
Error [Custom warning]: 512
Array
(
    [0] => 5
    [1] => InvalidArg: Division by zero!
    [2] => ` |

### test_008_datetime.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `Now (NY): 2026-03-29 09:42:01 EDT
Now (Shanghai): 2026-03-29 21:42:01 CST
Created: 2024-01-15 10:30:00
After +1D: 2024-01-16
After -2D3H: 2024-01-13 07:30:00
Diff (dt1 to dt2): 1 days
After +1 week: 2` |
| AOT输出 | `ERROR: Property DateTimeInterface.ATOM not found
ERROR: Property DateTimeInterface.COOKIE not found
ERROR: Property DateTimeInterface.ISO8601 not found
Now (NY): 2026-03-29 13:42:03 America/New_York
N` |

### test_009_serialization.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `JSON_DEFAULT: {"string":"hello","int":42,"float":3.14159,"bool":true,"null":null,"array":[1,2,3],"nested":{"a":{"b":{"c":"deep"}}},"unicode":"\u4e2d\u6587\u6d4b\u8bd5","special":"line1
line2	tab"}
JSO` |
| AOT输出 | `int(1)
float(2.5)
bool(true)
string(3) "str"
JSON_DEFAULT: {"string":"hello","int":42,"float":3.14159,"bool":true,"null":null,"array":[1,2,3],"nested":{"a":{"b":{"c":"deep"}}},"unicode":"中文测试"` |

### test_010_filesystem.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `Wrote 40 bytes
Read: 40 bytes
Content match: yes
File exists: yes
Is file: yes
Is dir: no
File size: 40
File mtime: 1774791728
File atime: 1774791728
Basename: test.txt
Dirname: /var/folders/_w/w71wt9` |
| AOT输出 | `Wrote 40 bytes
Read: 40 bytes
Content match: yes
File exists: yes
Is file: yes
Is dir: no
File size: 40
File mtime: 1774791731914597444
File atime: 1774791731914881947
Basename: test.txt
Dirname: /tmp` |

### test_010_reference_pointer.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `a=20, b=20
Array
(
    [0] => 2
    [1] => 4
    [2] => 6
)
Array
(
    [0] => 9
    [1] => 6
    [2] => 5
    [3] => 4
    [4] => 3
    [5] => 2
    [6] => 1
    [7] => 1
)
x=100, y=100, z=100` |
| AOT输出 | `a=10, b=
Array
(
    [0] => 2
    [1] => 4
    [2] => 6
)
Array
(
    [0] => 9
    [1] => 6
    [2] => 5
    [3] => 4
    [4] => 3
    [5] => 2
    [6] => 1
    [7] => 1
)
x=1, y=1, z=1` |

### test_011_reflection.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: PHP Fatal error:  Uncaught Error: Call to undefined method ReflectionClass::isClass() in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_011_reflection.p` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: PHP Fatal error:  Uncaught Error: Call to undefined method ReflectionClass::isClass()

Fatal error: Uncaught Error: Call to undefined method ReflectionClass::isClass()
PHP Fatal ` |

### test_012_network.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `Function checks:
  fsockopen exists: yes
  stream_socket_client exists: yes
  curl_init exists: yes
  gethostbyname exists: yes
  getmxrr exists: yes
  checkdnsrr exists: yes

gethostbyname('localhost` |
| AOT输出 | `Function checks:
  fsockopen exists: no
  stream_socket_client exists: no
  curl_init exists: no
  gethostbyname exists: yes
  getmxrr exists: no
  checkdnsrr exists: no

gethostbyname('localhost'): 1` |

### test_012_variadic_splat.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `15
a-b-c
Array
(
    [0] => req
    [1] => opt
    [2] => Array
        (
            [0] => extra1
            [1] => extra2
        )

)
15
Array
(
    [0] => 1
    [1] => 2
    [2] => 3
    [3] => ` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: ` |

### test_013_datetime.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `Seconds in a day: 86400
mktime result: 2024-12-25 15:30:00
Array
(
    [seconds] => 27
    [minutes] => 42
    [hours] => 13
    [mday] => 29
    [wday] => 0
    [mon] => 3
    [year] => 2026
    [yda` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: Seconds in a day: 86400
mktime result: 2024-12-25 15:30:00
PHP Fatal error:  Uncaught Error: Call to undefined function getdate() in /Users/tuoke/Desktop/ai-zig-php-parser/zig-ph` |

### test_013_regex.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `preg_match('/Hello/'): found
preg_match_all('/\d+/'): ["123","456","7890","192","168","1","1","2024","03","15","19","99","42","3","14","1","10","0"]
preg_replace('/\d+/' -> '#'): 200 chars
preg_split:` |
| AOT输出 | `PHP Warning:  Undefined variable $allMatches in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_013_regex.php on line 29

Warning: Undefined variable $allMatches in /Users/tuo` |

### test_014_spl.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `SplFixedArray count: 3
SplFixedArray[1]: second
toArray: first,second,third

SplStack top: c
SplStack pop: c
SplStack count: 2

SplQueue count: 3
SplQueue dequeue: first

SplMinHeap extract: 10
SplMin` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: PHP Fatal error:  Uncaught Error: Call to undefined method SplStack::top()

Fatal error: Uncaught Error: Call to undefined method SplStack::top()
PHP Fatal error:  Uncaught Error` |

### test_015_dynamic.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: Variable variable $$var where var='dynamic': value_of_dynamic
$prefix = 'outer', $$prefix = 'final_value'
$obj->$propName: prop_value
$funcName(): HELLO

Variable variables itema` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: 
Parse error: Unexpected token in expression in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_015_dynamic.php on line 31
PHP Parse error:  Unexpected t` |

### test_015_file_operations.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `Content:
Line 1
Line 2
Line 3
Lines count: 3
File exists: yes
File size: 21
Is readable: yes
Is writable: yes
First line: Line 1
First 5 bytes: Line 
Files in temp dir: 3032
File deleted: yes` |
| AOT输出 | `Content:
Line 1
Line 2
Line 3
Lines count: 3
File exists: yes
File size: 21
Is readable: yes
Is writable: yes
First line: Line 1
First 5 bytes: Line 
Files in temp dir: 64
File deleted: yes` |

### test_016_math.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: PHP Fatal error:  Uncaught Error: Call to undefined function log2() in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_016_math.php:29
Stack trace:
#0 /U` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: ` |

### test_017_serialize_unserialize.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `Serialized: a:7:{s:6:"string";s:4:"test";s:3:"int";i:42;s:5:"float";d:3.14;s:4:"bool";b:1;s:4:"null";N;s:5:"array";a:3:{i:0;i:1;i:1;i:2;i:2;i:3;}s:6:"nested";a:1:{s:1:"a";a:1:{s:1:"b";s:1:"c";}}}
Arra` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: Serialized: a:7:{s:6:"string";s:4:"test";s:3:"int";i:42;s:5:"float";d:3.14;s:4:"bool";b:1;s:4:"null";N;s:5:"array";a:3:{i:0;i:1;i:1;i:2;i:2;i:3;}s:6:"nested";a:1:{s:1:"a";a:1:{s:` |

### test_018_named_args.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Named Arguments ===
Name: John, Age: 30, Active: yes, Tags: php,developer, Email: none
Name: Jane, Age: 0, Active: no, Tags: designer,artist, Email: john@example.com
First middle Third

=== Spread` |
| AOT输出 | `=== Named Arguments ===
Name: , Age: 0, Active: yes, Tags: , Email: none
Name: , Age: 0, Active: yes, Tags: , Email: none


=== Spread Operator in Arrays ===
Combined: 1,2,3,4,5
Prepend 0: 0,1,2,3
App` |

### test_019_match.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Match with true condition ===
object: stdClass instance
object: DateTime instance
array: Array with 3 elements
string: String of length 5
integer: Integer: 42
double: Float: 3.14
boolean: Boolean:` |
| AOT输出 | `=== Match with true condition ===
object: stdClass instance
object: DateTime instance
array: Array with 3 elements
string: String of length 5
integer: Integer: 42
double: Float: 3.14
boolean: 
boolean` |

### test_020_functional.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: === Pipeline ===
Result: 20

=== Compose ===
compose((x-5), (x+10), (x*2)) applied to 5: 20

=== Curry ===
PHP Fatal error:  Uncaught ArgumentCountError: Too few arguments to fun` |
| AOT输出 | `=== Pipeline ===
Result: 20

=== Compose ===
compose((x-5), (x+10), (x*2)) applied to 5: 20

=== Curry ===
Curried add(1)(2)(3): 

=== Memoize ===
First call expensive(5): 25 (computations: 1)
Second ` |

### test_022_weakmap.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `WeakMap initial size: 2
obj1 in map: yes
obj1 value: first
Iterating: Object 1 data = first
Iterating: Object 2 data = second

WeakRef original: Object 1 data
WeakRef after unset obj1: null
WeakMap si` |
| AOT输出 | `WeakMap initial size: 2
obj1 in map: yes
obj1 value: first
Iterating: Object 1 data = first
Iterating: Object 2 data = second

WeakRef original: Object 1 data
WeakRef after unset obj1: null
WeakMap si` |

### test_023_cloning.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `After clone: a.value = 100, b.value = 200
Original nested inner data: modified
Clone nested inner data: modified
Original items: 1,2,3
Clone items: 1,2,3,4
Original nested name: cloned
Clone nested na` |
| AOT输出 | `After clone: a.value = 100, b.value = 200
Original nested inner data: modified
Clone nested inner data: modified
Original items: 1,2,3,4
Clone items: 1,2,3,4
Original nested name: cloned
Clone nested ` |

### test_024_iterators.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: PHP Fatal error:  Cannot redeclare class ArrayIterator in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_024_iterators.php on line 38

Fatal error: Cann` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: === RangeIterator ===
  [0] => 0
  [1] => 2
  [2] => 4
  [3] => 6
  [4] => 8
  [5] => 10

=== ArrayIterator ===
Count: 4
  [0] => a
  [1] => b
  [2] => c
  [3] => d

=== Director` |

### test_025_callables.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: === First-class callable syntax ===
PHP Fatal error:  Uncaught Error: Non-static method CallableLab::add() cannot be called statically in /Users/tuoke/Desktop/ai-zig-php-parser/z` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: === First-class callable syntax ===
error: UnknownFunction
/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/.zigphp_aot_build/main.zig:11518:5: 0x1005bdd83 in aot_dispatch_s` |

### test_026_network_socket.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: Host: localhost -> IP: 127.0.0.1 -> Name: localhost
Host: 127.0.0.1 -> IP: 127.0.0.1 -> Name: localhost
Server name: 192.168.1.10
URL parts:
Array
(
    [scheme] => https
    [ho` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: PHP Fatal error:  Uncaught Error: Call to undefined function gethostbyaddr() in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_026_network_socket.php:7` |

### test_026_readonly.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: === Readonly properties ===
Name: Test
Value: 42
Tags: php,zig
Created: 2026-03-29

=== Readonly class (PHP 8.2) ===
User: Alice, ID: 1
Permissions: read,write
Updated permission` |
| AOT输出 | `=== Readonly properties ===
Name: Test
Value: 42
Tags: php,zig
Created: 2026-03-29

=== Readonly class (PHP 8.2) ===
User: Alice, ID: 1
Permissions: read,write
Updated permissions: read,write,delete` |

### test_027_constants.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Final constants ===
ConstantsLab::FINAL_STRING: final_string
ConstantsLab::FINAL_INT: 42
ConstantsLab::FINAL_ARRAY: a,b,c

=== Typed constants ===
TYPED_INT: 100
TYPED_STRING: hello
TYPED_FLOAT: 3` |
| AOT输出 | `=== Final constants ===
ConstantsLab::FINAL_STRING: final_string
ConstantsLab::FINAL_INT: 42
ERROR: Property ConstantsLab.FINAL_ARRAY not found
ConstantsLab::FINAL_ARRAY: 

=== Typed constants ===
TYP` |

### test_028_builtin_functions.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `isset: yes
empty: no
after unset isset: no
integer: int=
double: float=
string: string=
array: array=
boolean: bool=
NULL: null=
object: object=
get_class: TestClass
get_parent_class: none
class_exist` |
| AOT输出 | `isset: yes
empty: no
PHP Warning:  Undefined variable $var in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_028_builtin_functions.php on line 8

Warning: Undefined variable ` |

### test_028_hooks.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Property hooks simulation ===
Name (after set hook): 'test'
Counter: 10
Computed: COMPUTED VALUE
After modification - Name: 'trimmed', Counter: 11

=== Override property hooks simulation ===
Deriv` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: 
Parse error: syntax error, unexpected "(", expecting "{" in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_028_hooks.php on line 10
PHP Parse error:  s` |

### test_029_new_functions.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== New string functions ===
str_contains('Hello World', 'World'): true
str_starts_with('Hello World', 'Hello'): true
str_ends_with('Hello World', 'World'): true
fdiv(10, 3): 3.3333333333333
fdiv(-10,` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: === New string functions ===
PHP Fatal error:  Uncaught Error: Call to undefined function enum_exists() in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/tes` |

### test_029_regular_expressions.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `Match 'quick': quick
First 3 words: The, quick, brown
Words 4+ chars: quick, brown, jumps, over, lazy, dogs, 2024
Numbers: 13, 3, 45, 2024, 03, 15
Date: 2024-03-15
Replaced: The quick brown fox jumps ` |
| AOT输出 | `Compile Error: main.zig:3778:26: error: expected 3 argument(s), found 5
    reg_114 = try runtime.preg_split(reg_110, reg_111, reg_112, reg_113, runtime.runtime_allocator);
                  ~~~~~~~^~` |

### test_030_namespaces.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: === Namespace tests ===
NamespaceClass greeting: Hello from namespace
PHP Fatal error:  Uncaught Error: Undefined constant "NAMESPACE_CONST" in /Users/tuoke/Desktop/ai-zig-php-pa` |
| AOT输出 | `=== Namespace tests ===
NamespaceClass greeting: Hello from namespace
NamespaceConst sum: 84
NamespaceFunc alias: namespace function

=== Direct namespace access ===
Direct access: Hello from namespac` |

### test_031_nullsafe.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Nullsafe operator ===
nullableString: hello
nullableInt ?? 0: 0
After null - nullableString ?? 'default': default

=== Chained nullsafe ===
nested?->value: nested_value
nested?->leaf?->data: leaf_` |
| AOT输出 | `=== Nullsafe operator ===
nullableString: hello
nullableInt ?? 0: 0
After null - nullableString ?? 'default': default

=== Chained nullsafe ===
nested?->value: nested_value
nested?->leaf?->data: leaf_` |

### test_032_type_declarations.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP Deprecated:  complexTypes(): Implicitly marking parameter $callback as nullable is deprecated, the explicit nullable type must be used instead in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-par` |
| AOT输出 | `20
4.64
HELLO
false
value
null was passed
20
7
3
5
MyClass
stdClass
No return
Base type: Base
Derived type: Derived
Array
(
    [name] => Test
    [age] => 25
    [tags] => Array
        (
           ` |

### test_032_types.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: PHP Fatal error:  Cannot redeclare interface Countable in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_032_types.php on line 49

Fatal error: Cannot r` |
| AOT输出 | `=== Union types ===
int: 42
string: hello
float: 3.14

=== Intersection types ===
Intersection type count: 5

=== Nullable types ===
With value: test
With null: was null

=== Mixed types ===
integer: ` |

### test_033_autoload.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Autoload simulation ===
ClassA loaded: yes
ClassC loaded: no
Total loaded: 2

=== Class exists and method exists ===
class_exists('stdClass'): yes
class_exists('NonExistentClass'): no
interface_ex` |
| AOT输出 | `=== Autoload simulation ===
ClassA loaded: yes
ClassC loaded: no
Total loaded: 2

=== Class exists and method exists ===
class_exists('stdClass'): yes
class_exists('NonExistentClass'): no
interface_ex` |

### test_034_interfaces.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== ArrayAccess implementation ===
obj['a']: 1
isset(obj['b']): true
isset(obj['c']): false
After set obj['c'] = 3: 3
After append: {"a":1,"b":2,"c":3,"0":4}
After unset(obj['a']): {"b":2,"c":3,"0":4}` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: === ArrayAccess implementation ===
obj['a']: 1
isset(obj['b']): true
isset(obj['c']): false
After set obj['c'] = 3: 3
Segmentation fault at address 0x8f
/Users/tuoke/Desktop/ai-z` |

### test_035_output_buffer.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Output Buffer Lab ===
Flush testob_level: 0
Content 1: First buffer content
Content 2 length: 55
Level content: Level: 1
Nested: 
Flush content: 

Current level: 3
After clean all, level: 0

=== O` |
| AOT输出 | `=== Output Buffer Lab ===
First buffer content
Second buffer
More content
 (captured but not cleaned)
Level: 1
Nested: 2
Flush testob_level: 0
Content 1: 
Content 2 length: 0
Level content: 
Nested: ` |

### test_037_globals.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Globals Lab ===
GLOBALS['test_var']: Hello from globals
count(GLOBALS): 9 keys
After unset, isset(GLOBALS['test_var']): false

=== Extract simulation ===
PHP Warning:  Undefined variable $pre_name` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: === Globals Lab ===
GLOBALS['test_var']: 
count(GLOBALS): 0 keys
After unset, isset(GLOBALS['test_var']): false

=== Extract simulation ===
PHP Warning:  Undefined variable $name` |

### test_038_anonymous_class.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `Array
(
    [0] => 13:44:18 - First message
    [1] => 13:44:18 - Second message
)
Counter start: 10
After increment: 11
Hello, World!
Processed: TEST` |
| AOT输出 | `Array
(
    [0] => 13:44:20 - First message
    [1] => 13:44:20 - Second message
)
Counter start: 10
After increment: 11
Hello, World!
Processed: TEST` |

### test_038_crypto.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Crypto Lab ===
=== Hashing ===
md5('secret_password_123'): 478f7a4e398493e64305957f98247b28
sha1('secret_password_123'): f1f8581726b2e68500e852620479c09ac05ed280
sha256('secret_password_123'): 011` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: === Crypto Lab ===
PHP Fatal error:  Uncaught Error: Call to undefined function hash_algos() in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_038_crypt` |

### test_039_variable_funcs.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Variable functions ===
strlen('hello'): 5
strtoupper('hello'): HELLO
array_sum([1,2,3,4,5]): 15

=== Dynamic method calls ===
sum(1,2,3,4,5): 15
concat('a','b','c'): abc

=== Callable variable ass` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: === Variable functions ===
strlen('hello'): 5
strtoupper('hello'): HELLO
array_sum([1,2,3,4,5]): 15

=== Dynamic method calls ===
error: UnknownFunction
/Users/tuoke/Desktop/ai-z` |

### test_040_constants.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Abstract class ===
abstractMethod: Implemented abstract
concreteMethod: Concrete implementation
staticMethod: Static in abstract

=== Interface ===
INTERFACE_CONST: interface_value
interfaceMethod` |
| AOT输出 | `=== Abstract class ===
abstractMethod: Implemented abstract
concreteMethod: Concrete implementation
staticMethod: Static in abstract

=== Interface ===
INTERFACE_CONST: interface_value
interfaceMethod` |

### test_040_reflection_deep.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `Class name: ReflectedClass
Is instantiable: yes
Is final: no

Properties (3):
  privateProp - private
  protectedProp - protected
  publicProp - public

Methods (4):
  privateMethod()
  protectedMetho` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: Class name: ReflectedClass
Is instantiable: yes
Is final: no

Properties (3):
error: UnknownMethod
/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/.zigphp_aot_build/runtime` |

### test_041_exceptions2.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Exception Lab 2 ===
Try block 1
Caught RuntimeException: First exception
Try block 2
Caught InvalidArgumentException: Invalid argument
Nested try block
Inner finally
Outer caught: Inner exception` |
| AOT输出 | `=== Exception Lab 2 ===
Try block 1
Caught RuntimeException: First exception
Try block 2
Caught InvalidArgumentException: Invalid argument
Nested try block
Inner finally
Division try-finally executed` |

### test_041_number_boundary.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: PHP_INT_MAX: 9223372036854775807
PHP_INT_MIN: -9223372036854775808
MAX + 1: 9.2233720368548E+18
Type: double
MIN - 1: -9.2233720368548E+18
0.1 + 0.2 == 0.3: false
0.1 + 0.2: 0.3` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: PHP_INT_MAX: 9223372036854775807
PHP_INT_MIN: -9223372036854775808
MAX + 1: 9.2233720368548E+18
Type: double
MIN - 1: -9.2233720368548E+18
0.1 + 0.2 == 0.3: false
0.1 + 0.2: 0.3` |

### test_042_array_hash.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `Array with string keys:
Array
(
    [a] => value_a
    [b] => value_b
    [c] => value_c
    [0] => value_0
    [1] => value_1
    [2] => value_2
    [00] => value_00
    [01] => value_01
    [true] =` |
| AOT输出 | `Array with string keys:
Array
(
    [a] => value_a
    [b] => value_b
    [c] => value_c
    [0] => value_0
    [1] => value_1
    [2] => value_2
    [00] => value_00
    [01] => value_01
    [true] =` |

### test_043_variable_variables.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `hello = world
Dynamic strlen: 4
method1 called
Dynamic
$$y = z
$$$y = final value
PHP Deprecated:  Creation of dynamic property Dynamic::$dynamic is deprecated in /Users/tuoke/Desktop/ai-zig-php-parse` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: 
Parse error: syntax error, unexpected variable "$x", expecting ";" in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_043_variable_variables.php on line` |

### test_044_memory_performance.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `String length: 1000
Peak memory: 453680 bytes
Current memory: 414192 bytes
Collected cycles: 0
Collected cycles after circular ref: 2
Execution time: 4.6014785766602E-5 seconds
User time: 0
Memory lim` |
| AOT输出 | `String length: 1000
Peak memory: 59788 bytes
Current memory: 59907 bytes
Collected cycles: 0
Collected cycles after circular ref: 0
Execution time: 0.0041120052337646 seconds
User time: 0
Memory limit` |

### test_0450_Trait组合.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `27
1
3` |
| AOT输出 | `Compile Error: main.zig:1691:11: error: redeclaration of local constant 'Counter_14_meta'
    const Counter_14_meta = try runtime.ClassMeta.init(allocator, "Counter_14");
          ^~~~~~~~~~~~~~~
mai` |

### test_0451_Trait组合.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `80
1
3` |
| AOT输出 | `Compile Error: main.zig:1691:11: error: redeclaration of local constant 'Counter_15_meta'
    const Counter_15_meta = try runtime.ClassMeta.init(allocator, "Counter_15");
          ^~~~~~~~~~~~~~~
mai` |

### test_045_stream_filter.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: From temp stream: Hello World! This is test data.
From memory stream: 31 bytes
STDIN defined: yes
STDOUT defined: yes
STDERR defined: yes
PHP Fatal error:  Uncaught Error: Call t` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: PHP Fatal error:  Uncaught Error: Call to undefined function rewind() in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_045_stream_filter.php:8
Stack tr` |

### test_047_const_expr.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Const Expressions ===
SUM: 6
PRODUCT: 24
MIXED: 6
STRING_CONCAT: Hello World
ARRAY_CONST: [1,2,3,4,5]
ARRAY_EXPR: [2,4,9]
BOOL_AND: false
BOOL_OR: true
NULL_COALESCE: default
NEGATIVE: -100
FLOAT_` |
| AOT输出 | `=== Const Expressions ===
ERROR: Property ConstExpressions.ARRAY_CONST not found
ERROR: Property ConstExpressions.ARRAY_EXPR not found
ERROR: Property ConstExpressions.CONDITIONAL not found
ERROR: Pro` |

### test_048_foreach_ref.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Foreach by reference ===
After foreach by ref, arr: [2,4,6,8,10]
Original after copy modify: ["modified","b","c"]

=== List destructuring ===
List destructure: x=10, y=20
Nested destructure: a=1, ` |
| AOT输出 | `=== Foreach by reference ===
After foreach by ref, arr: [2,4,6,8,10]
Original after copy modify: ["a","b","c"]

=== List destructuring ===
List destructure: x=10, y=20
Nested destructure: a=1, b=2, c=` |

### test_048_nullsafe_operator.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: PHP Fatal error:  New expressions are not supported in this context in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_048_nullsafe_operator.php on line ` |
| AOT输出 | `Street: unknown
CEO Name: No CEO
Street2: Main St
City: Beijing
Item: Item1
PHP Warning:  Trying to access array offset on null in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/t` |

### test_049_strings.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: === Heredoc ===
PHP Warning:  Undefined variable $heredoc in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_049_strings.php on line 14

Warning: Undefin` |
| AOT输出 | `=== Heredoc ===
This is a heredoc string
With multiple lines
Name: Test
Value: 42
Expression: 84
=== Nowdoc ===
This is a nowdoc string
No interpolation: \$label
Just literal text
=== Complex braces =` |

### test_050_spread.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: === Spread in function calls ===
PHP Fatal error:  Uncaught ArgumentCountError: Too few arguments to function SpreadLab::sum(), 2 passed in /Users/tuoke/Desktop/ai-zig-php-parser` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: 
Parse error: syntax error, unexpected variable "$nums", expecting ")" in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_050_spread.php on line 12
PHP P` |

### test_050_throw_expression.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: PHP Fatal error:  Constant expression contains invalid operations in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_050_throw_expression.php on line 77` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: 10 / 2 = 5
Caught: Cannot divide 10 by zero
Timeout: 30
Valid: 42
Validation failed: Value must be positive, got: -5
Status 200: OK
Invalid code: Unknown HTTP code: 999
Created 2` |

### test_051_anonymous.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Anonymous classes ===
Anonymous class: class@anonymous/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_051_anonymous.php:7$0
Anonymous value: anonymous_value
Anonymous meth` |
| AOT输出 | `=== Anonymous classes ===
Anonymous class: anonymous_class_0
Anonymous value: anonymous_value
Anonymous method: anonymous_value

=== Anonymous with constructor ===
Anon with constructor: $name=test, $` |

### test_052_const_expr2.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Const Expressions 2 ===
ARITH (10 + 5 * 2): 20
COMPARE: yes
SPACESHIP (5 <=> 10): -1
ARRAY_LITERAL: [1,2,3]
ASSOC_ARRAY: {"a":1,"b":2}
NESTED_ARRAY: [{"x":1},{"y":2}]
BOOLEAN (true and false): fal` |
| AOT输出 | `=== Const Expressions 2 ===
ARITH (10 + 5 * 2): 20
ERROR: Property ConstExpr2.COMPARE not found
COMPARE: 
SPACESHIP (5 <=> 10): -1
ERROR: Property ConstExpr2.ARRAY_LITERAL not found
ARRAY_LITERAL: nul` |

### test_052_first_class_callable.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: PHP Parse error:  syntax error, unexpected token "echo" in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_052_first_class_callable.php on line 98

Parse` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: 
Parse error: Unexpected token in expression in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_052_first_class_callable.php on line 98
PHP Parse error: ` |

### test_052_mixed_complex.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: PHP Parse error:  syntax error, unexpected identifier "StringOrInt" in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_052_mixed_complex.php on line 3

P` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: 
Parse error: syntax error, unexpected token, expecting "(" in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_052_mixed_complex.php on line 4
PHP Parse ` |

### test_052_union_types.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: PHP Parse error:  syntax error, unexpected identifier "StringOrInt" in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_052_union_types.php on line 3

Par` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: 
Parse error: syntax error, unexpected token, expecting "(" in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_052_union_types.php on line 4
PHP Parse er` |

### test_053_constructors.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: === Constructor tests ===
Initial count: 0
Constructor called with: first
After obj1: 1
Constructor called with: second
After obj2: 2
Constructor called with: default
After obj3 ` |
| AOT输出 | `=== Constructor tests ===
Initial count: 0
Constructor called with: first
After obj1: 1
Constructor called with: second
After obj2: 2
Constructor called with: default
After obj3 (default): 3

=== Chai` |

### test_053_intersection_types.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `Testing CountingLogger:
Count: 3

Testing AdvancedCounter:
Count: 3
Logs:
  2026-03-29 13:45:54: Incremented to 1
  2026-03-29 13:45:54: Incremented to 2
  2026-03-29 13:45:54: Incremented to 3
  2026` |
| AOT输出 | `Testing CountingLogger:
Count: 3

Testing AdvancedCounter:
Count: 3
Logs:
  2026-03-29 13:45:56: Incremented to 1
  2026-03-29 13:45:56: Incremented to 2
  2026-03-29 13:45:56: Incremented to 3
  2026` |

### test_054_pure_intersection.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: PHP Fatal error:  Cannot redeclare interface Serializable in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_054_pure_intersection.php on line 39

Fatal ` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: ` |

### test_055_readonly_properties.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `DTO Summary: ID: user_123, Items: 2, Created: 2026-03-29
ID: user_123
Data: {"name":"Alice","role":"admin"}
Shallow items: {"a":1,"b":2}

Configs:
Prod: env=production, debug=false
Dev: env=production` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: ` |

### test_055_static_late.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Static method binding ===
StaticBase::getName(): StaticBase
StaticBase::getNameLate(): StaticBase
StaticDerived::getName(): StaticBase
StaticDerived::getNameLate(): StaticDerived
StaticGrandChild:` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: === Static method binding ===
StaticBase::getName(): StaticBase
StaticBase::getNameLate(): StaticBase
StaticDerived::getName(): StaticBase
StaticDerived::getNameLate(): StaticDer` |

### test_056_final_constants.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: PHP Fatal error:  Private constant ApiEndpoints::RETRY_COUNT cannot be final as it is not visible to other classes in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: ` |

### test_056_interfaces.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Interface constants ===
A::A_CONST: A
B::B_CONST: B
C::C_CONST: C
C extends A, B - A_CONST: A
C extends A, B - B_CONST: B

=== Implementation checks ===
ImplABC instanceof A: yes
ImplABC instanceo` |
| AOT输出 | `=== Interface constants ===
A::A_CONST: A
B::B_CONST: B
C::C_CONST: C
C extends A, B - A_CONST: A
C extends A, B - B_CONST: B

=== Implementation checks ===
ImplABC instanceof A: yes
ImplABC instanceo` |

### test_057_higher_order.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: PHP Fatal error:  Duplicate declaration of static variable $cache in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_057_higher_order.php on line 47

Fat` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: Composed (1+1)*2^2 = 16
Piped (1+1)*2^2 = 16
Curried add: 15
Partial multiply: 24` |

### test_057_new_in_initializers.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `Service 1 logs:
Array
(
    [0] => 13:46:34 Work started
    [1] => 13:46:34 Work completed
)

Shared logger logs:
Array
(
    [0] => 13:46:34 Work started
    [1] => 13:46:34 Work completed
    [2] =` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: ` |

### test_058_arrayiterators.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `ArrayObject count: 3
ArrayObject['x']: 10
After ao['x']=100: 100

=== ArrayIterator ===
  a => 1
  b => 2
  c => 3

=== SeekableIterator ===
Seek to position 3: 40

=== RecursiveArrayIterator ===
  a ` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: ArrayObject count: 3
ArrayObject['x']: 10
After ao['x']=100: 100

=== ArrayIterator ===
  a => 1
  b => 2
  c => 3

=== SeekableIterator ===
Seek to position 3: 40

=== Recursive` |

### test_058_object_graph.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `root
  child1
    grandchild
      root (cycle detected)
  child2
1 2 3 
3 2 1 ` |
| AOT输出 | `Compile Error: main.zig:823:24: error: expected type 'runtime_lib.Value', found '*runtime_lib.Value'
            reg_21.* = reg_8;
                       ^~~~~
runtime_lib.zig:1994:19: note: struct de` |

### test_059_filter_iterator.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== FilterIterator ===
Even numbers: 2,4,6,8,10

=== KeyFilter ===
Keys starting with 'a': {"apple":1,"apricot":3}

=== RecursiveFilterIterator ===
PHP Warning:  Array to string conversion in /Users/t` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: === FilterIterator ===
PHP Fatal error:  Uncaught Error: Call to undefined function iterator_to_array() in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/tes` |

### test_059_mixed_complex.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `Stack (LIFO):
  third
  second
  first
Queue (FIFO):
  one
  two
  three
Fixed array size: 5
Fixed array: a, b, c
Storage count: 3
Contains obj1: yes
List (forward):
  c
  a
  b
List (reverse):
  b
  ` |
| AOT输出 | `Compile Error: main.zig:4084:25: error: expected 3 argument(s), found 2
    reg_76 = try runtime.php_array_filter(reg_75, runtime.runtime_allocator);
                 ~~~~~~~^~~~~~~~~~~~~~~~~
runtime_` |

### test_059_spl_structures.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `Stack (LIFO):
  third
  second
  first
Queue (FIFO):
  one
  two
  three
Fixed array size: 5
Fixed array: a, b, c
Storage count: 3
Contains obj1: yes
List (forward):
  c
  a
  b
List (reverse):
  b
  ` |
| AOT输出 | `Compile Error: main.zig:4084:25: error: expected 3 argument(s), found 2
    reg_76 = try runtime.php_array_filter(reg_75, runtime.runtime_allocator);
                 ~~~~~~~^~~~~~~~~~~~~~~~~
runtime_` |

### test_060_iterators.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== NumberRange iterator ===
  [0] => 0
  [1] => 2
  [2] => 4
  [3] => 6
  [4] => 8
  [5] => 10

=== Fibonacci iterator ===
  [0] => 0
  [1] => 1
  [2] => 1
  [3] => 2
  [4] => 3
  [5] => 5
  [6] => 8` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: === NumberRange iterator ===
  [0] => 0
  [1] => 2
  [2] => 4
  [3] => 6
  [4] => 8
  [5] => 10

=== Fibonacci iterator ===
  [0] => 0
  [1] => 1
  [2] => 1
  [3] => 2
  [4] => 3` |

### test_060_mixed_complex.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `Even numbers (first 5):
  2
  4
  6
  8
  10
Cached iteration:
  Current: 1 (next: 2)
  Current: 2 (next: 3)
  Current: 3 (next: 4)
  Current: 4 (next: 5)
  Current: 5
Flattened tree:
  leaf1
  leaf2` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: PHP Fatal error:  Uncaught Error: Class "LimitIterator" not found in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_060_mixed_complex.php:42
Stack trace` |

### test_060_mixed_type.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: PHP Fatal error:  Type mixed cannot be marked as nullable since mixed already includes null in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_060_mixed_` |
| AOT输出 | `Stored items:
  0: null value
  1: 
  2: integer: 42
  3: float: 3.14
  4: string: 'hello'
  5: array with 3 elements
  6: object of class stdClass
  7: callable

Fetched data:
config: array
count: in` |

### test_061_closure_bind.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: Closure with use: x=1, y=2, z=3
Closure with ref: x=1, y=100, z=3
After modify, y: 100
Closure without bind: anonymous
Closure bound to obj2: other

=== Closure call ===
Hello, W` |
| AOT输出 | `Closure with use: x=1, y=2, z=3
Closure with ref: x=1, y=100, z=3
After modify, y: 100
Closure without bind: anonymous
Closure bound to obj2: anonymous

=== Closure call ===
Hello, World!
PHP Fatal er` |

### test_063_arrays.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `Original: [3,1,4,1,5,9,2,6]
sort: [1,1,2,3,4,5,6,9]
rsort: [9,6,5,4,3,2,1,1]
asort: {"a":1,"b":2,"c":3}
ksort: {"a":1,"b":2,"c":3}
usort: [1,1,2,3,4,5,6,9]
array_unique: {"0":1,"1":2,"3":3}
array_keys` |
| AOT输出 | `Original: [3,1,4,1,5,9,2,6]
sort: [1,1,2,3,4,5,6,9]
rsort: [9,6,5,4,3,2,1,1]
asort: {"a":1,"b":2,"c":3}
ksort: {"a":1,"b":2,"c":3}
usort: [1,1,2,3,4,5,6,9]
array_unique: {"0":1,"1":2,"3":3}
array_keys` |

### test_064_array_splat_unpacking.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `Combined: 1, 2, 3, 4, 5, 6
Merged assoc: {"name":"Alice","age":30,"city":"Beijing","country":"China"}
Mixed: {"0":1,"1":2,"2":3,"key":"value","3":4,"4":5,"5":6}
With literals: 0, 1, 2, 3, 100, 4, 5, 6` |
| AOT输出 | `Combined: 1, 2, 3, 4, 5, 6
Merged assoc: {"name":"Alice","age":30,"city":"Beijing","country":"China"}
Mixed: {"0":1,"1":2,"2":3,"key":"value","3":4,"4":5,"5":6}
With literals: 0, 1, 2, 3, 100, 4, 5, 6` |

### test_064_inheritance.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Inheritance visibility ===
child->getProtected(): child_protected
child->getParentProtected(): child_protected
child->callProtected(): child protected method
child->getParentMethod(): child protec` |
| AOT输出 | `=== Inheritance visibility ===
child->getProtected(): child_protected
child->getParentProtected(): child_protected
child->callProtected(): child protected method
child->getParentMethod(): child protec` |

### test_065_attribute_reflection.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `Class attributes:
  Table: users

Property attributes:
  id: int
  name: string(255)
  email: string nullable

Method attributes:
  list: /users [GET, POST] name=user_list
  get: /users/{id} [GET] nam` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: Class attributes:
PHP Fatal error:  Uncaught Error: Call to undefined method ReflectionAttribute::newInstance()

Fatal error: Uncaught Error: Call to undefined method ReflectionA` |

### test_066_interpolation.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `Simple: local_value
With braces: local_value
Property: prop_value
Number: 42
Method: method_result
Array access: 1
Nested: deep

=== Complex interpolation ===
Object: std
Array direct: 10

=== Arithme` |
| AOT输出 | `PHP Warning:  Trying to access array offset on null in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_066_interpolation.php on line 21

Warning: Trying to access array offset` |

### test_066_spl_iterators.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `Limited (10-14): 11, 12, 13, 14, 15
First 5 evens: 2, 4, 6, 8, 10
Cached first 3: 1, 2, 3
Cache count: 3
Appended: 1, , c
Words starting with 'a': apple, apricot
Flattened: a, b, c, value
With depth:` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: PHP Fatal error:  Uncaught Error: Class "LimitIterator" not found in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_066_spl_iterators.php:12
Stack trace` |

### test_067_casting.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP Warning:  Array to string conversion in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_067_casting.php on line 27

Warning: Array to string conversion in /Users/tuoke/Des` |
| AOT输出 | `PHP Warning:  Array to string conversion in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_067_casting.php on line 27

Warning: Array to string conversion in /Users/tuoke/Des` |

### test_067_error_exception_hierarchy.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `Exception handling:
  [VALIDATION] Email is required
  [NOT FOUND] User not found
  [APP] Connection failed
  Unhandled: Generic error

Exception chain:
Top level: Cannot complete operation
Caused by:` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: Exception handling:
  [VALIDATION] Email is required
  [NOT FOUND] User not found
  Unhandled: Connection failed
  Unhandled: Generic error

Exception chain:
Top level: Cannot co` |

### test_069_arguments.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Required arguments ===
required: hello

=== Default values ===
a=x, b=10, c=true
a=x, b=20, c=true
a=x, b=20, c=false

=== Nullable ===
was_null
value

=== Variadic ===
first=first, rest=
first=fi` |
| AOT输出 | `=== Required arguments ===
required: hello

=== Default values ===
a=x, b=10, c=true
a=x, b=20, c=true
a=x, b=20, c=false

=== Nullable ===
was_null
value

=== Variadic ===
first=first, rest=
first=fi` |

### test_069_weakmap_weakref.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `Cache size: 3
obj1 data: Data for obj1
After removing obj2, cache size: 2

Weak cache get: temporary
After unset, weak cache get: null

Observer count: 2
Observer A received: Test event
Observer B rec` |
| AOT输出 | `Cache size: 1
obj1 data: Data for obj3
After removing obj2, cache size: 1

Weak cache get: temporary
After unset, weak cache get: null

Observer count: 1
PHP Fatal error:  Call to a member function on` |

### test_070_object_cloning.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: Original person: Alice, 123 Main St
Person Alice being cloned
  Address cloned

After clone and modify:
Person1: Alice, 123 Main St
Person2: Bob, 456 Oak Ave

--- Spouse cloning ` |
| AOT输出 | `Original person: Alice, 123 Main St
Person Alice being cloned
  Address cloned

After clone and modify:
Person1: Alice, 123 Main St
Person2: Bob, 456 Oak Ave

--- Spouse cloning ---
Original: Carol ma` |

### test_071_const_expr3.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Constant expressions ===
SIMPLE: 100
WITH_EXPRESSION: 50
WITH_PARENS: 60
STRING: Hello World
BOOLEAN: false
NULL: null
ARRAY: [1,2,3]
ASSOC: {"a":1,"b":2}

=== Child class constants ===
CHILD_ONLY` |
| AOT输出 | `=== Constant expressions ===
ERROR: Property ConstExpressions.ARRAY not found
ERROR: Property ConstExpressions.ASSOC not found
SIMPLE: 100
WITH_EXPRESSION: 50
WITH_PARENS: 60
STRING: Hello World
BOOLE` |

### test_071_serialize_magic.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: === Old Style ===
  __sleep called
Serialized: 94 bytes
  __wakeup called
Restored name: User

=== New Style ===
  __serialize called
Serialized: 142 bytes
  __unserialize called` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: === Old Style ===
  __sleep called
Serialized: 142 bytes
  __wakeup called
Restored name: User

=== New Style ===
  __serialize called
Serialized: 142 bytes
  __unserialize calle` |

### test_072_namespace.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: === Namespace functions ===
PHP Fatal error:  Uncaught Error: Undefined constant "NS_CONST" in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_072_namesp` |
| AOT输出 | `=== Namespace functions ===
NS_CONST: namespace_const
nsFunc(): namespace_function
NsClass->greet(): Hello from namespace

=== Global namespace ===
\Test\Space\NS_CONST: namespace_const
\Test\Space
sF` |

### test_073_late_static.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Late static binding ===
LateStaticBase::getName(): Base
LateStaticChild::getName(): Child
LateStaticGrandChild::getName(): GrandChild

=== create() ===
LateStaticBase::create() class: LateStaticBa` |
| AOT输出 | `=== Late static binding ===
LateStaticBase::getName(): Base
LateStaticChild::getName(): Child
LateStaticGrandChild::getName(): GrandChild

=== create() ===
LateStaticBase::create() class: LateStaticBa` |

### test_074_dynamic_vars.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: PHP Parse error:  syntax error, unexpected token ".", expecting "->" or "?->" or "[" in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_074_dynamic_vars.` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: 
Parse error: Unexpected token in expression in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_074_dynamic_vars.php on line 12
PHP Parse error:  Unexpec` |

### test_075_closures.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: Arrow add(5, 3): 8
Closure capture (5 + 10): 15
Closure with ref: 20
Ref after: 10

=== Closure from return ===
double(10): 20
triple(10): 30

=== Closure bind ===
From A: A
From` |
| AOT输出 | `Arrow add(5, 3): 8
Closure capture (5 + 10): 15
Closure with ref: 20
Ref after: 10

=== Closure from return ===
double(10): 20
triple(10): 30

=== Closure bind ===
PHP Fatal error:  Call to a member f` |

### test_076_clone.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Basic clone ===
Original value: original
Clone value: modified

=== Shallow clone (shared reference) ===
Original data: ["initial"]
Clone data: ["initial","added"]

=== Clone with __clone hook ===` |
| AOT输出 | `=== Basic clone ===
Original value: original
Clone value: modified

=== Shallow clone (shared reference) ===
Original data: ["initial","added"]
Clone data: ["initial","added"]

=== Clone with __clone ` |

### test_077_exceptions.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Exception hierarchy ===
Caught as Exception: Original

=== Custom exception ===
Message: Custom error
Extra: extra_data
Code: 0

=== Rethrow ===
Caught rethrown: Outer from: Inner

=== Multiple ca` |
| AOT输出 | `=== Exception hierarchy ===
Caught as Exception: Original

=== Custom exception ===
Message: Custom error
Extra: extra_data
Code: 0

=== Rethrow ===
Caught rethrown: Outer from: Inner

=== Multiple ca` |

### test_078_iterators2.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== ArrayObject ===
Count: 3
ao['x']: 10
After modify: ao['x']=100, ao['new']=999

=== ArrayIterator ===
  a => 1
  b => 2
  c => 3

=== Seek ===
Seek to 1: 2

=== RecursiveArrayIterator ===
  depth=0` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: === ArrayObject ===
Count: 3
ao['x']: 10
After modify: ao['x']=100, ao['new']=999

=== ArrayIterator ===
  a => 1
  b => 2
  c => 3

=== Seek ===
PHP Fatal error:  Uncaught Error` |

### test_079_anonymous_functions.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `Hello, World!
Mr. Smith Jr.
Counter: 1 2 3
Squares: 1, 4, 9, 16, 25
Hello, Alice!
Welcome, Alice!
Factorial 5: 120
Count: 1 2 3` |
| AOT输出 | `Hello, World!
Mr. Smith Jr.
Counter: 1 2 3
Squares: 1, 4, 9, 16, 25
PHP Warning:  foreach() argument must be of type array|object, unknown given in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parse` |

### test_080_partial_application.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: PHP Parse error:  syntax error, unexpected token "{" in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_080_partial_application.php on line 102

Parse er` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: 
Parse error: Unexpected token in expression in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_080_partial_application.php on line 103
PHP Parse error: ` |

### test_080_password.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Password hash ===
Hash: $2y$12$qxyaf.FhjBp2ax2EL3HK2OH...

=== Verify ===
Correct password: valid
Wrong password: invalid

=== Bcrypt ===
Bcrypt: $2y$10$TRVRGwzbV1FvB3BKM2a9Ped...

=== Password in` |
| AOT输出 | `password_hash not available` |

### test_081_hash.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Hash ===
md5('hello'): 5d41402abc4b2a76b9719d911017c592
sha1('hello'): aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d
sha256('hello'): 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824
sh` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: === Hash ===
md5('hello'): 5d41402abc4b2a76b9719d911017c592
sha1('hello'): aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d
sha256('hello'): 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa74` |

### test_082_json.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== JsonSerializable ===
json_encode: {"name":"test","value":42,"computed":"test_42"}

=== Nested ===
Nested json_encode: {"obj":{"name":"test","value":42,"computed":"test_42"},"arr":[1,2,3]}

=== Jso` |
| AOT输出 | `=== JsonSerializable ===
json_encode: {"value":42,"name":"test"}

=== Nested ===
Nested json_encode: {"obj":{"value":42,"name":"test"},"arr":[1,2,3]}

=== Json error ===
json_last_error: 4
json_last_e` |

### test_083_arrayaccess.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: === ArrayAccess ===
col['a']: 1
col['b']: 2

=== Set/Unset ===
After set col['c']=3: 3
isset(col['c']): yes
After unset col['a'], isset(col['a']): no

=== Append ===
PHP Fatal er` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: === ArrayAccess ===
col['a']: 1
col['b']: 2

=== Set/Unset ===
After set col['c']=3: 3
isset(col['c']): yes
After unset col['a'], isset(col['a']): yes

=== Append ===
Segmentatio` |

### test_086_filesystem.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Directory functions ===
sys_get_temp_dir(): /var/folders/_w/w71wt9952qj7615ggqkkfxfr0000gn/T

=== File operations ===
is_file: yes
file_exists: yes
filesize: 20
file_get_contents: Line 1
Line 2
Li` |
| AOT输出 | `=== Directory functions ===
sys_get_temp_dir(): /tmp

=== File operations ===
is_file: yes
file_exists: yes
filesize: 20
file_get_contents: Line 1
Line 2
Line 3

=== Directory listing ===
scandir: sub` |

### test_087_class_exists.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Exists checks ===
class_exists('TestClass'): yes
class_exists('NonExistent'): no
interface_exists('TestInterface'): yes
trait_exists('TestTrait'): yes

=== Method exists ===
method_exists($obj, 'p` |
| AOT输出 | `=== Exists checks ===
class_exists('TestClass'): yes
class_exists('NonExistent'): no
interface_exists('TestInterface'): yes
trait_exists('TestTrait'): yes

=== Method exists ===
method_exists($obj, 'p` |

### test_088_reflection.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: === ReflectionClass ===
Name: ReflectionTarget
PHP Fatal error:  Uncaught Error: Call to undefined method ReflectionClass::isClass() in /Users/tuoke/Desktop/ai-zig-php-parser/zig` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: === ReflectionClass ===
Name: ReflectionTarget
PHP Fatal error:  Uncaught Error: Call to undefined method ReflectionClass::isClass()

Fatal error: Uncaught Error: Call to undefin` |

### test_089_reflection2.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: === ReflectionMethod ===
Name: method
Number of parameters: 3
Number of required params: 1

=== ReflectionParameter ===
  a:
    Position: 0
    Optional: no
    Allows null: no` |
| AOT输出 | `=== ReflectionMethod ===
Name: method
Number of parameters: 0
Number of required params: 0

=== ReflectionParameter ===
PHP Fatal error:  Uncaught Error: Call to undefined method ReflectionMethod::get` |

### test_095_return_types.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Return types ===
returnsInt: 42
returnsString: string
returnsArray: [1,2,3]
returnsObject class: stdClass
returnsNull: null
returnsVoid: 
returnsMixed: anything
returnsUnion type: string, value: o` |
| AOT输出 | `=== Return types ===
returnsInt: 42
returnsString: string
returnsArray: [1,2,3]
returnsObject class: stdClass
returnsNull: null
returnsVoid: 
returnsMixed: anything
returnsUnion type: integer, value: ` |

### test_099_iterator_aggregate.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: === IteratorAggregate ===
  [0] => a
  [1] => b
  [2] => c
  [3] => d

=== With custom add ===
  a
  b
  c
  d
  e
  f

=== KeyValue ===
  x => 10
  y => 20
  z => 30

=== Count ` |
| AOT输出 | `=== IteratorAggregate ===
  [0] => a
  [1] => b
  [2] => c
  [3] => d

=== With custom add ===
  a
  b
  c
  d
  e
  f

=== KeyValue ===
  x => 10
  y => 20
  z => 30

=== Count via Countable ===
coun` |

### test_100_serializable.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP Deprecated:  SerializableClass implements the Serializable interface, which is deprecated. Implement __serialize() and __unserialize() instead (or in addition, if support for old PHP versions is n` |
| AOT输出 | `=== Serializable interface ===
Serialized length: 125
Unserialized data: test_data
Unserialized timestamp: 1774792175

=== Serialize __serialize/__unserialize (PHP 7.4+) ===
New serialized name: test,` |

### test_104_sleep_wakeup.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== __sleep/__wakeup ===
Before serialize: name=test, value=42, secret=hidden
Serialized: 62 bytes
After unserialize: name=test, value=42, secret=revealed_after_wakeup

=== Serialize with dynamic ===` |
| AOT输出 | `=== __sleep/__wakeup ===
Before serialize: name=test, value=42, secret=hidden
Serialized: 90 bytes
After unserialize: name=test, value=42, secret=revealed_after_wakeup

=== Serialize with dynamic ===` |

### test_105_final_const.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Final constants ===
FINAL_STRING: final_string
FINAL_INT: 42
FINAL_ARRAY: ["a","b","c"]

=== Cannot override final constant ===
ChildFinal::CHILD_ONLY: child
ChildFinal::FINAL_STRING: final_string` |
| AOT输出 | `=== Final constants ===
FINAL_STRING: final_string
FINAL_INT: 42
ERROR: Property FinalConstants.FINAL_ARRAY not found
FINAL_ARRAY: null

=== Cannot override final constant ===
ChildFinal::CHILD_ONLY: ` |

### test_107_match_types.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== match with true ===
int: 42
float: 3.14
string: hello
bool: true
array: 2 elements
null

=== match with union type ===
one
letter a
other

=== match in expression ===
Status result: Status is acti` |
| AOT输出 | `=== match with true ===
int: 42
float: 3.14
string: hello

array: 2 elements
null

=== match with union type ===
one
letter a
other

=== match in expression ===
Status result: Status is inactive` |

### test_111_timezone.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Timezones ===
NY: 2024-01-15 12:00:00 EST
Tokyo: 2024-01-16 02:00:00 JST

=== Create from timestamp ===
From timestamp: 2024-01-01 00:00:00 UTC

=== DateInterval create from string ===
Created int` |
| AOT输出 | `=== Timezones ===
NY: 2024-01-15 17:00:00 America/New_York
Tokyo: 2024-01-15 17:00:00 Asia/Tokyo

=== Create from timestamp ===
From timestamp: 2024-01-01 00:00:00 UTC

=== DateInterval create from st` |

### test_113_extract_compact.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== compact ===
compact('name', 'age', 'city', 'active'): {"name":"Alice","age":30,"city":"NYC","active":true}
compact(['name', 'age']): {"name":"Alice","age":30}

=== extract ===
After extract: x=10,` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: === compact ===` |

### test_117_array_find.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== array_find ===
First even: 2
First above 5: 6
Not found result: null

=== Custom find ===
Custom first even: 2` |
| AOT输出 | `=== array_find ===
array_find not available

=== Custom find ===
Custom first even: 2` |

### test_122_closure_call.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Closure::call ===
Closure::call($a): A
Closure::call($b): B

=== Closure with args ===
Adder: Sum: 8
Subtracter: Diff: 8` |
| AOT输出 | `=== Closure::call ===
PHP Fatal error:  Call to a member function on a non-object

Fatal error: Call to a member function on a non-object
Closure::call($a): 
PHP Fatal error:  Call to a member functio` |

### test_124_dynamic_const.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: === Dynamic constant access ===
PHP Fatal error:  Uncaught Error: Access to undeclared static property DynamicConst::$VALUE in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-pars` |
| AOT输出 | `=== Dynamic constant access ===
ERROR: Property DynamicConst.$constName not found
DynamicConst::$constName where constName='VALUE': 
ERROR: Property DynamicConst.$constNum not found
DynamicConst::$con` |

### test_126_named_variadic.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: PHP Fatal error:  Cannot use positional argument after named argument in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_126_named_variadic.php on line 1` |
| AOT输出 | `=== Named arguments with variadic ===
Name: Bob, Age: 30, Active: no, Roles: 
Name: Charlie, Age: 0, Active: yes, Roles: admin,Charlie
Name: Dave, Age: 25, Active: yes, Roles: user

=== Named argument` |

### test_127_union_null.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: === Union with null ===
Int prop: int: 123
String prop: string: string
Null prop: null

=== Return union with null ===
PHP Fatal error:  Uncaught TypeError: UnionNull::process():` |
| AOT输出 | `=== Union with null ===
Int prop: int: 123
String prop: string: string
Null prop: null

=== Return union with null ===
PHP Warning:  Array to string conversion in /Users/tuoke/Desktop/ai-zig-php-parse` |

### test_128_resource_id.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: === get_resource_id ===
Resource ID: 5
Resource type: stream

=== Null/false resources ===
PHP Fatal error:  Uncaught TypeError: get_resource_id(): Argument #1 ($resource) must b` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: === get_resource_id ===
Resource ID: 0
PHP Fatal error:  Uncaught Error: Call to undefined function get_resource_type() in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/f` |

### test_129_intersection.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: PHP Fatal error:  Class CountableTraversableImpl must implement interface Traversable as part of either Iterator or IteratorAggregate in Unknown on line 0

Fatal error: Class Cou` |
| AOT输出 | `=== Intersection types ===
process (Countable&Traversable): 5
countOnly (Countable): 5` |

### test_130_spread_method.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Spread in method calls ===
sum(...[10,20,30]): 60
sum(...[100,200], d=5): 305
concat(...$strings): Hello World` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: 
Parse error: syntax error, unexpected variable "$numbers", expecting ")" in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_130_spread_method.php on lin` |

### test_131_anon_interface.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Anonymous class with interface ===
Value: anonymous_data
Is AnonymousInterface: yes` |
| AOT输出 | `=== Anonymous class with interface ===
Value: anonymous_data
Is AnonymousInterface: no` |

### test_132_object_storage.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: === Object identity ===
$a === $b: false
$a === $c: true
$a == $b: true

=== Object as array key ===
PHP Fatal error:  Uncaught TypeError: Cannot access offset of type StorageObj` |
| AOT输出 | `=== Object identity ===
$a === $b: false
$a === $c: true
$a == $b: false

=== Object as array key ===
Array count: 1

=== Object serialization ===
Serialized length: 51` |

### test_133_callback_array.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: === Callback class ===
PHP Fatal error:  Uncaught TypeError: CallbackArray::filter(): Argument #1 ($predicate) must be of type callback, Closure given, called in /Users/tuoke/Des` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: === Callback class ===
Evens: 2,4,6,8,10
Doubled: 2,4,6,8,10,12,14,16,18,20

=== ArrayObject as callback target ===
error: InvalidArgument
/Users/tuoke/Desktop/ai-zig-php-parser/` |

### test_134_namespace_alias.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: === Namespace aliasing ===
DeepClass: Hello from deep namespace
PHP Fatal error:  Uncaught Error: Undefined constant "DEEP_CONST" in /Users/tuoke/Desktop/ai-zig-php-parser/zig-ph` |
| AOT输出 | `=== Namespace aliasing ===
DeepClass: Hello from deep namespace
DEEP_CONST: deep_constant
Alias Deep: Hello from deep namespace

=== Fully qualified ===
Fully qualified: Hello from deep namespace
Full` |

### test_136_multi_catch.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Multiple catch ===
RuntimeException: Runtime
Logic/Invalid: InvalidArgumentException - Invalid
Logic/Invalid: LogicException - Logic
DomainException: Domain
Throwable: Exception - Generic` |
| AOT输出 | `=== Multiple catch ===
RuntimeException: Runtime
Logic/Invalid: InvalidArgumentException - Invalid
Logic/Invalid: LogicException - Logic
DomainException: Domain` |

### test_139_trait_resolution.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: === Multiple trait method resolution ===
method(): T3
callT2(): T2

=== Insteadof ===
PHP Fatal error:  Trait method TWorld::greet has not been applied as Greeting::greet, becaus` |
| AOT输出 | `=== Multiple trait method resolution ===
method(): T3
callT2(): T2

=== Insteadof ===
fullGreet: Hello World` |

### test_141_list_destructure.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== List destructuring ===
First three: first, second, third

=== Partial list ===
First and third: first, third

=== Keyed list ===
x=value_x, y=value_y

=== Nested list ===
Nested: a, b, c, d` |
| AOT输出 | `=== List destructuring ===
First three: first, second, third

=== Partial list ===
First and third: first, second

=== Keyed list ===
x=value_x, y=value_y

=== Nested list ===
Nested: a, b, c, d` |

### test_144_const_expressions.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Constant expressions ===
TIME_BASED: 300
ARRAY_CONST: [1,2,3,4,5]
STRING_CONCAT: Hello World

=== Class constant from function ===
ConstFunc::COMPUTED: 100
ConstFunc::FROM_CONST: 300` |
| AOT输出 | `=== Constant expressions ===
TIME_BASED: 300
ARRAY_CONST: [1,2,3,4,5]
STRING_CONCAT: Hello World

=== Class constant from function ===
ConstFunc::COMPUTED: 100
ERROR: Property ConstFunc.FROM_CONST not` |

### test_145_heredoc.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Heredoc ===
PHP Warning:  Undefined variable $heredoc in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_145_heredoc.php on line 11

Warning: Undefined variable $heredoc i` |
| AOT输出 | `=== Heredoc ===
Hello, World!
Value: 42
Expression: 84

=== Nowdoc ===
Hello, $name
No interpolation here

=== Heredoc with indentation ===
    Indented content
    With value` |

### test_148_error_handling.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== @ operator ===
Undefined var with @: null

=== Error suppression ===
Missing array access with @: null

=== Custom error handler ===
Custom handler: Test notice
Restored handler` |
| AOT输出 | `=== @ operator ===
PHP Warning:  Undefined variable $undefined_var in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_148_error_handling.php on line 4

Warning: Undefined vari` |

### test_153_closure_binding.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Closure binding ===
From A: A
From B: B` |
| AOT输出 | `=== Closure binding ===
PHP Warning:  Undefined variable $this in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_153_closure_binding.php on line 13

Warning: Undefined variab` |

### test_165_const_arrays.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Constant arrays ===
NUMBERS: [1,2,3,4,5]
ASSOCIATIVE: {"a":1,"b":2,"c":3}
MIXED: [1,"two",3,true]

=== Access elements ===
NUMBERS[0]: 1
ASSOCIATIVE['b']: 2` |
| AOT输出 | `=== Constant arrays ===
ERROR: Property ConstArrays.NUMBERS not found
NUMBERS: null
ERROR: Property ConstArrays.ASSOCIATIVE not found
ASSOCIATIVE: null
ERROR: Property ConstArrays.MIXED not found
MIXE` |

### test_186_mixed.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Mixed type ===
integer: 42
string: 'hello'
array: array (
  0 => 1,
  1 => 2,
  2 => 3,
)` |
| AOT输出 | `=== Mixed type ===
integer: 42
string: 'hello'
array: array (
    0 => 1,
    1 => 2,
    2 => 3,
)` |

### test_196_array_slice.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `=== Array slice ===
slice[0:2]: 1,2
slice[2:3]: 3,4,5
slice[-2:]: 4,5` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: ` |

### test_201_stream_wrapper.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `stream
OK` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: PHP Fatal error:  Uncaught Error: Call to undefined function stream_register_wrapper() in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_201_stream_wrap` |

### test_202_magic_static.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `Tom
truenull
trueOK` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: ` |

### test_203_value_object.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: PHP Fatal error:  Declaration of Money::equals(Money $other): bool must be compatible with ValueObject::equals(ValueObject $other): bool in /Users/tuoke/Desktop/ai-zig-php-parser` |
| AOT输出 | `1500
false
1500
OK` |

### test_207_event_emitter.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: 4
Init once!
PHP Warning:  Undefined variable $wrapper in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_207_event_emitter.php on line 31

Warning: Unde` |
| AOT输出 | `PHP Warning:  foreach() argument must be of type array|object, unknown given in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_207_event_emitter.php on line 22

Warning: fore` |

### test_209_memoize.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `6765
6765
6765
Memoized: 0.000689s, Recursive: 0.000463s, Cached: 0.000004s
OK` |
| AOT输出 | `6765
6765
6765
Memoized: 0.011001s, Recursive: 0.005190s, Cached: 0.000032s
OK` |

### test_213_sorting.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `1,2,3,4,5,6,7,8,9,10
5,11,12,22,23,25,30,34,45,64,77,90

42
OK` |
| AOT输出 | `1,2,3,4,5,6,7,8,9,10
64,23,64,34,64,23,64,45,64,23,64,34,64,23,64,25,64,23,64,34,64,23,64,45,64,23,64,34,64,23,64,30,64,23,64,34,64,23,64,45,64,23,64,34,64,23,64,25,64,23,64,34,64,23,64,45,64,23,64,34` |

### test_219_rate_limiter.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `1
1
1
Rate limit exceeded
Rate limit exceeded
OK` |
| AOT输出 | `Rate limit exceeded
Rate limit exceeded
Rate limit exceeded
Rate limit exceeded
Rate limit exceeded
OK` |

### test_220_validator.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `name: Name must be at least 2 characters
email: Invalid email format
age: Must be 18 or older
OK` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: PHP Warning:  Trying to access array offset on unknown in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_220_validator.php on line 36

Warning: Trying t` |

### test_223_deep_array.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `Array
(
    [a] => 1
    [b] => Array
        (
            [c] => 2
            [d] => 5
        )

    [e] => 4
    [f] => 6
)
Array
(
    [a] => 1
    [b] => Array
        (
            [d] => 3
  ` |
| AOT输出 | `Array
(
    [a] => 1
    [b] => Array
        (
            [c] => 2
            [d] => 5
        )

    [e] => 4
    [f] => 6
)
Array
(
    [a] => 1
)
OK` |

### test_224_priority_queue.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `high priority task
low priority task
medium priority task
OK` |
| AOT输出 | `PHP Warning:  Trying to access array offset on null in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_224_priority_queue.php on line 10

Warning: Trying to access array offse` |

### test_226_levenshtein.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `3
2
3
3
0
OK` |
| AOT输出 | `6
3
3
3
3
OK` |

### test_233_matrix.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `3
19
50
OK` |
| AOT输出 | `4
62
72
OK` |

### test_244_stack.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `PHP_TIMEOUT_OR_ERROR: 3
2
2
PHP Fatal error:  Uncaught Error: Cannot call constructor in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_244_stack.php:40
Stack trace:
#0 /User` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: 3

3
error: MethodNotFound
/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/.zigphp_aot_build/runtime_lib.zig:14736:5: 0x102707127 in php_call_static_with_ctx (main)
    ret` |

### test_257_date_helper.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `truefalse
true29
167
2024-04-10
OK` |
| AOT输出 | `truefalse
true
167
2024-04-10
OK` |

### test_258_url_helper.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `https
example.com
/path/to/page
123
https://test.com/api
OK` |
| AOT输出 | `https
example.com
/path/to/page
PHP Warning:  Undefined variable $params in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_258_url_helper.php on line 27

Warning: Undefined v` |

### test_259_uuid.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `36
truefalse
78b355f2
OK` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: Segmentation fault at address 0xaaaaaaaaaaaaaa00
/opt/homebrew/Cellar/zig/0.15.2/lib/zig/std/array_hash_map.zig:2122:49: 0x1044459cc in capacityIndexType (main)
        return ha` |

### test_292_string_case_ops.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `HELLO
hello
Hello World
Hello
hELLO
hELLO wORLD
OK` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: HELLO
hello
Hello World
Hello
hELLO
Segmentation fault at address 0x1
/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/.zigphp_aot_build/runtime_lib.zig:1744:13: 0x1006a3814` |

### test_296_trim.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `11
trueHello World PHP
Hello \'World\'
Hello 'World'
OK` |
| AOT输出 | `AOT_TIMEOUT_OR_ERROR: 11
trueHello World PHP
Hello \'World\'
PHP Fatal error:  Uncaught Error: Call to undefined function addslashes2() in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_s` |

### test_297_char_ops.php

| 项目 | 内容 |
|------|------|
| PHP输出 | `65
A
5d41402abc4b2a76b9719d911017c592
aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d
907060870
olleh
OK` |
| AOT输出 | `65
A
5d41402abc4b2a76b9719d911017c592
aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d
%u
olleh
OK` |


## 测试统计

| 统计项 | 数量 |
|--------|------|
| 总计 | 325 |
| 通过 | 154 |
| 失败 | 166 |
| 跳过 | 5 |
