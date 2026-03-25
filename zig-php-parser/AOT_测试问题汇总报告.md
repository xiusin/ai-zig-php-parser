# AOT 测试问题汇总报告

**测试时间**: 2026-03-24 12:54:05

**PHP解释器**: php
**AOT编译器**: /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/zig-out/bin/php-interpreter

## 测试结果汇总

| 类型 | 数量 | 说明 |
|------|------|------|
| **PASS** | 37 | AOT执行结果与PHP一致 |
| **MISMATCH** | 26 | AOT与PHP输出结果不一致 |
| **COMPILE_FAIL** | 0 | AOT编译失败 |
| **AOT_RUNTIME** | 60 | AOT运行时失败 |
| **PHP_FAIL** | 32 | PHP原生执行失败 |
| **SKIP** | 11 | 跳过测试 |

**通过率**: 30.1% (排除PHP失败和跳过)

---

## 问题详细列表

### 2. MISMATCH - 输出不一致

#### test_002_type_juggling.php

**目录**: fuzzy_scripts_27/failed

**PHP输出**:
```
--- Testing: '123' ---
Original: '123'
As int: 123 (type: integer)
As float: 123 (type: double)
As string: 123 (type: string)
As bool: true (type: boolean)
As array: 1 elements
As object: stdClass
String math: 123.456 + 1 = 124.456
Intval: 123
Floatval: 123.456
Hex(0xFF): 255, Oct(0755): 493, Bin(0b1010): 10
Scientific: 1.23e4 = 12300
INF: INF, -INF: -INF, NAN: NAN
is_infinite(INF): true
is_nan(NAN): true
is_finite(1.0): true
PHP_INT_MAX: 9223372036854775807
PHP_INT_MIN: -9223372036854775808
PHP
```

**AOT输出**:
```
--- Testing: '123' ---
Original: '123'
As int: 123 (type: integer)
As float: 123 (type: double)
As string: 123 (type: string)
As bool: true (type: boolean)
As array: 1 elements
As object: stdClass
String math: 123.456 + 1 = 124.456
Intval: 123
Floatval: 123.456
Hex(0xFF): 255, Oct(0755): 493, Bin(0b1010): 10
Scientific: 1.23e4 = 12300
INF: INF, -INF: -INF, NAN: nan
is_infinite(INF): true
is_nan(NAN): true
is_finite(1.0): true
PHP_INT_MAX: 9223372036854775807
PHP_INT_MIN: -9223372036854775808
PHP
```

#### test_017_traits.php

**目录**: fuzzy_scripts_27/failed

**PHP输出**:
```
=== Trait tests ===
Dog says: Hello World!
Dog speaks: Woof!
Dog plays: Buddy is playing

Cat says: Hello World!
Cat speaks: Meow!
Cat hunts: Whiskers is hunting

=== Interface type checks ===
Dog:
  is Animal: yes
  is Pet: yes
  is Wild: no
Cat:
  is Animal: yes
  is Pet: yes
  is Wild: yes
Robot:
  is Animal: yes
  is Pet: no
  is Wild: no
Fox:
  is Animal: no
  is Pet: no
  is Wild: yes

=== Static counts ===
Dog count: 1

=== Trait with abstract method ===
Hello Default!

=== Multiple trait
```

**AOT输出**:
```
=== Trait tests ===
Dog says: Hello World!
Dog speaks: Woof!
Dog plays: Buddy is playing

Cat says: Hello World!
Cat speaks: Meow!
Cat hunts: Whiskers is hunting

=== Interface type checks ===
Dog:
  is Animal: no
  is Pet: yes
  is Wild: no
Cat:
  is Animal: no
  is Pet: yes
  is Wild: yes
Robot:
  is Animal: yes
  is Pet: no
  is Wild: no
Fox:
  is Animal: no
  is Pet: no
  is Wild: yes

=== Static counts ===
Dog count: 1

=== Trait with abstract method ===
Hello Default!

=== Multiple trait c
```

#### test_031_nullsafe.php

**目录**: fuzzy_scripts_27/failed

**PHP输出**:
```
=== Nullsafe operator ===
nullableString: hello
nullableInt ?? 0: 0
After null - nullableString ?? 'default': default

=== Chained nullsafe ===
nested?->value: nested_value
nested?->leaf?->data: leaf_data
After leaf=null - nested?->leaf?->data: null
nested?->getLeaf()?->data: null

=== isset with nullsafe ===
isset(lab->nullableString): false
lab->nullableString ?? 'isset default': isset default

=== empty with nullsafe ===
empty(lab->nullableString): true
After 'non-empty' - empty(lab->nullable
```

**AOT输出**:
```
=== Nullsafe operator ===
nullableString: hello
nullableInt ?? 0: 0
After null - nullableString ?? 'default': default

=== Chained nullsafe ===
nested?->value: nested_value
nested?->leaf?->data: leaf_data
After leaf=null - nested?->leaf?->data: null
nested?->getLeaf()?->data: null

=== isset with nullsafe ===
isset(lab->nullableString): true
lab->nullableString ?? 'isset default': isset default

=== empty with nullsafe ===
empty(lab->nullableString): true
After 'non-empty' - empty(lab->nullableS
```

#### test_033_autoload.php

**目录**: fuzzy_scripts_27/failed

**PHP输出**:
```
=== Autoload simulation ===
ClassA loaded: yes
ClassC loaded: no
Total loaded: 2

=== Class exists and method exists ===
class_exists('stdClass'): yes
class_exists('NonExistentClass'): no
interface_exists('Countable'): yes
trait_exists('ArrayObject'): no
method_exists($obj, 'publicMethod'): yes
method_exists($obj, 'privateMethod'): yes
is_callable([$obj, 'publicMethod']): yes

=== Property exists ===
property_exists($p, 'public'): yes
property_exists($p, 'private'): yes
property_exists('PropTest
```

**AOT输出**:
```
=== Autoload simulation ===
ClassA loaded: yes
ClassC loaded: no
Total loaded: 2

=== Class exists and method exists ===
class_exists('stdClass'): yes
class_exists('NonExistentClass'): no
interface_exists('Countable'): no
trait_exists('ArrayObject'): no
method_exists($obj, 'publicMethod'): yes
method_exists($obj, 'privateMethod'): yes
is_callable([$obj, 'publicMethod']): yes

=== Property exists ===
property_exists($p, 'public'): yes
property_exists($p, 'private'): yes
property_exists('PropTest'
```

#### test_048_foreach_ref.php

**目录**: fuzzy_scripts_27/failed

**PHP输出**:
```
=== Foreach by reference ===
After foreach by ref, arr: [2,4,6,8,10]
Original after copy modify: ["modified","b","c"]

=== List destructuring ===
List destructure: x=10, y=20
Nested destructure: a=1, b=2, c=3, d=4
Manual spread dest: first=1, second=2, rest=[3,4,5]
Key destructure: x=1, y=2, z=3

=== Array unpacking ===
Array merge: [1,2,3,4,5,6]
Manual middle: [0,1,2,3,10]

=== Foreach with keys ===
After key ref: {"a":10,"b":20,"c":30}

=== Foreach with list ===
num=1, str=one
num=2, str=two
n
```

**AOT输出**:
```
=== Foreach by reference ===
After foreach by ref, arr: [2,4,6,8,10]
Original after copy modify: ["a","b","c"]

=== List destructuring ===
List destructure: x=10, y=20
Nested destructure: a=1, b=2, c=3, d=4
Manual spread dest: first=1, second=2, rest=[3,4,5]
Key destructure: x=1, y=2, z=3

=== Array unpacking ===
Array merge: [1,2,3,4,5,6]
Manual middle: [0,1,2,3,10]

=== Foreach with keys ===
After key ref: {"a":10,"b":20,"c":30}

=== Foreach with list ===
num=1, str=one
num=2, str=two
num=3, s
```

#### test_063_arrays.php

**目录**: fuzzy_scripts_27/failed

**PHP输出**:
```
Original: [3,1,4,1,5,9,2,6]
sort: [1,1,2,3,4,5,6,9]
rsort: [9,6,5,4,3,2,1,1]
asort: {"a":1,"b":2,"c":3}
ksort: {"a":1,"b":2,"c":3}
usort: [1,1,2,3,4,5,6,9]
array_unique: {"0":1,"1":2,"3":3}
array_keys: ["c","a","b"]
array_values: [3,1,2]
array_merge: [1,2,3,4,5,6]
array_slice([1,2,3,4,5], 1, 3): [2,3,4]
array_splice [1,2 -> x,y]: [1,"x","y",4,5]

=== Array search ===
array_search('c', $arr): 2
in_array('b', $arr): yes
isset($arr[2]): yes

=== Array walk ===
After walk (*10): {"a":10,"b":20,"c":3
```

**AOT输出**:
```
Original: [3,1,4,1,5,9,2,6]
sort: [1,1,2,3,4,5,6,9]
rsort: [9,6,5,4,3,2,1,1]
asort: {"a":1,"b":2,"c":3}
ksort: {"a":1,"b":2,"c":3}
usort: [1,1,2,3,4,5,6,9]
array_unique: {"0":1,"1":2,"3":3}
array_keys: ["a","b","c"]
array_values: [1,2,3]
array_merge: [1,2,3,4,5,6]
array_slice([1,2,3,4,5], 1, 3): [2,3,4]
array_splice [1,2 -> x,y]: [1,"x","y",4,5]

=== Array search ===
array_search('c', $arr): 2
in_array('b', $arr): yes
isset($arr[2]): yes

=== Array walk ===
After walk (*10): {"a":1,"b":2,"c":3}

```

#### test_064_inheritance.php

**目录**: fuzzy_scripts_27/failed

**PHP输出**:
```
=== Inheritance visibility ===
child->getProtected(): child_protected
child->getParentProtected(): child_protected
child->callProtected(): child protected method
child->getParentMethod(): child protected method

=== Private in parent vs child ===
child->getPrivate(): parent_private
child->getParentPrivate(): parent_private
child->callPrivate(): parent private method

=== Method resolution ===
b->greet(): Hello from B
b->greetParent(): Hello from A

=== Static in inheritance ===
StaticParent::get
```

**AOT输出**:
```
=== Inheritance visibility ===
child->getProtected(): child_protected
child->getParentProtected(): child_protected
child->callProtected(): child protected method
child->getParentMethod(): child protected method

=== Private in parent vs child ===
child->getPrivate(): child_private
child->getParentPrivate(): child_private
child->callPrivate(): child private method

=== Method resolution ===
b->greet(): Hello from B
b->greetParent(): Hello from A

=== Static in inheritance ===
StaticParent::get():
```

#### test_066_interpolation.php

**目录**: fuzzy_scripts_27/failed

**PHP输出**:
```
Simple: local_value
With braces: local_value
Property: prop_value
Number: 42
Method: method_result
Array access: 1
Nested: deep

=== Complex interpolation ===
Object: std
Array direct: 10

=== Arithmetic in interpolation ===
Sum: 5 + 10 = 15

=== Escape sequences ===

Warning: Undefined variable $notvar in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts_27/failed/test_066_interpolation.php on line 47
Escaped \: ${notvar}
Backslash: \
Tab: 	

=== Heredoc interpolation ===
Prop
```

**AOT输出**:
```

Warning: Trying to access array offset on null in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts_27/failed/test_066_interpolation.php on line 21
Simple: local_value
With braces: local_value
Property: prop_value
Number: 42
Method: method_result
Array access: 
Nested: deep

=== Complex interpolation ===
Object: std
Array direct: 10

=== Arithmetic in interpolation ===
Sum: 5 + 10 = 15

=== Escape sequences ===

Warning: Undefined variable $notvar in /Users/tuoke/Desktop/ai-zi
```

#### test_067_casting.php

**目录**: fuzzy_scripts_27/failed

**PHP输出**:
```

Warning: Array to string conversion in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts_27/failed/test_067_casting.php on line 27
=== Integer casting ===
(int)'123': 123
(int)'12.3': 12
(int)12.9: 12
(int)'abc': 0
(int)true: 1
(int)false: 0
(int)null: 0

=== Float casting ===
(float)'3.14': 3.14
(float)'123': 123
(float)100: 100

=== String casting ===
(string)123: 123
(string)3.14: 3.14
(string)true: 1
(string)false: 
(string)null: 
(string)['a','b']: Array

=== Boolean cast
```

**AOT输出**:
```

Warning: Array to string conversion in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts_27/failed/test_067_casting.php on line 27
=== Integer casting ===
(int)'123': 123
(int)'12.3': 12
(int)12.9: 12
(int)'abc': 0
(int)true: 1
(int)false: 0
(int)null: 0

=== Float casting ===
(float)'3.14': 3.14
(float)'123': 123
(float)100: 100

=== String casting ===
(string)123: 123
(string)3.14: 3.14
(string)true: 1
(string)false: 
(string)null: 
(string)['a','b']: Array

=== Boolean cast
```

#### test_069_arguments.php

**目录**: fuzzy_scripts_27/failed

**PHP输出**:
```
=== Required arguments ===
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
first=first, rest=second,third

=== All variadic ===
count=0, sum=0
count=5, sum=15

=== Named arguments ===
a=named, b=99, c=true
a=named, b=50, c=false

=== Type declarations ===
int=1, float=2.5, string=str, bool=true

=== Return type ===
returned

void function

```

**AOT输出**:
```
=== Required arguments ===
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
first=first, rest=second,third

=== All variadic ===
count=0, sum=0
count=5, sum=15

=== Named arguments ===
a=99, b=0, c=true
a=, b=0, c=true

=== Type declarations ===
int=1, float=2.5, string=str, bool=true

=== Return type ===
returned

void function

```

#### test_073_late_static.php

**目录**: fuzzy_scripts_27/failed

**PHP输出**:
```
=== Late static binding ===
LateStaticBase::getName(): Base
LateStaticChild::getName(): Child
LateStaticGrandChild::getName(): GrandChild

=== create() ===
LateStaticBase::create() class: LateStaticBase
LateStaticChild::create() class: LateStaticChild
LateStaticGrandChild::create() class: LateStaticGrandChild

=== setName mutation ===
After setName:
  LateStaticBase::getName(): ModifiedBase
  LateStaticChild::getName(): ModifiedChild
  LateStaticGrandChild::getName(): ModifiedGrand

```

**AOT输出**:
```
=== Late static binding ===
LateStaticBase::getName(): Base
LateStaticChild::getName(): Child
LateStaticGrandChild::getName(): GrandChild

=== create() ===
LateStaticBase::create() class: LateStaticBase
LateStaticChild::create() class: LateStaticChild
LateStaticGrandChild::create() class: LateStaticGrandChild

=== setName mutation ===
After setName:
  LateStaticBase::getName(): ModifiedGrand
  LateStaticChild::getName(): Child
  LateStaticGrandChild::getName(): GrandChild

```

#### test_076_clone.php

**目录**: fuzzy_scripts_27/failed

**PHP输出**:
```
=== Basic clone ===
Original value: original
Clone value: modified

=== Shallow clone (shared reference) ===
Original data: ["initial"]
Clone data: ["initial","added"]

=== Clone with __clone hook ===
Original name: original
Clone name: original_cloned
Original history: []
Clone history: ["cloned"]

=== Clone in function ===
Source value: original
Result value: function_modified

```

**AOT输出**:
```
=== Basic clone ===
Original value: original
Clone value: modified

=== Shallow clone (shared reference) ===
Original data: ["initial","added"]
Clone data: ["initial","added"]

=== Clone with __clone hook ===
Original name: original
Clone name: original_cloned
Original history: ["cloned"]
Clone history: ["cloned"]

=== Clone in function ===
Source value: original
Result value: function_modified

```

#### test_077_exceptions.php

**目录**: fuzzy_scripts_27/failed

**PHP输出**:
```
=== Exception hierarchy ===
Caught as Exception: Original

=== Custom exception ===
Message: Custom error
Extra: extra_data
Code: 0

=== Rethrow ===
Caught rethrown: Outer from: Inner

=== Multiple catch ===
RuntimeException: Runtime
LogicException: Invalid
LogicException: Logic
CustomException: Custom

```

**AOT输出**:
```
=== Exception hierarchy ===
Caught as Exception: Original

=== Custom exception ===
Message: Custom error
Extra: extra_data
Code: 0

=== Rethrow ===
Caught rethrown: Outer from: Inner

=== Multiple catch ===
RuntimeException: Runtime
Exception: Invalid
LogicException: Logic
CustomException: Custom

```

#### test_087_class_exists.php

**目录**: fuzzy_scripts_27/failed

**PHP输出**:
```
=== Exists checks ===
class_exists('TestClass'): yes
class_exists('NonExistent'): no
interface_exists('TestInterface'): yes
trait_exists('TestTrait'): yes

=== Method exists ===
method_exists($obj, 'publicMethod'): yes
method_exists($obj, 'privateMethod'): yes
is_callable([$obj, 'publicMethod']): yes

=== Property exists ===
property_exists($p, 'public'): yes
property_exists($p, 'private'): yes
property_exists('PropTest', 'public'): yes

=== is_subclass_of ===
is_subclass_of('ChildClass', 'Paren
```

**AOT输出**:
```
=== Exists checks ===
class_exists('TestClass'): yes
class_exists('NonExistent'): no
interface_exists('TestInterface'): yes
trait_exists('TestTrait'): yes

=== Method exists ===
method_exists($obj, 'publicMethod'): yes
method_exists($obj, 'privateMethod'): yes
is_callable([$obj, 'publicMethod']): yes

=== Property exists ===
property_exists($p, 'public'): yes
property_exists($p, 'private'): yes
property_exists('PropTest', 'public'): no

=== is_subclass_of ===
is_subclass_of('ChildClass', 'Parent
```

#### test_100_serializable.php

**目录**: fuzzy_scripts_27/failed

**PHP输出**:
```

Deprecated: SerializableClass implements the Serializable interface, which is deprecated. Implement __serialize() and __unserialize() instead (or in addition, if support for old PHP versions is necessary) in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts_27/failed/test_100_serializable.php on line 3
=== Serializable interface ===
Serialized length: 92
Unserialized data: test_data
Unserialized timestamp: 1774327927

=== Serialize __serialize/__unserialize (PHP 7.4+) ===
New 
```

**AOT输出**:
```
=== Serializable interface ===
Serialized length: 125
Unserialized data: test_data
Unserialized timestamp: 1774327929

=== Serialize __serialize/__unserialize (PHP 7.4+) ===
New serialized name: test, value: 42

```

#### test_101_multi_interface.php

**目录**: fuzzy_scripts_27/failed

**PHP输出**:
```
=== Multiple interfaces ===
methodA: A
methodB: B
methodC: C

=== instanceof ===
obj instanceof InterfaceA: yes
obj instanceof InterfaceB: yes
obj instanceof InterfaceC: yes

=== Interface constants ===
InterfaceA::class: InterfaceA
InterfaceC::class: InterfaceC

```

**AOT输出**:
```
=== Multiple interfaces ===
methodA: A
methodB: B
methodC: C

=== instanceof ===
obj instanceof InterfaceA: no
obj instanceof InterfaceB: no
obj instanceof InterfaceC: yes

=== Interface constants ===
InterfaceA::class: InterfaceA
InterfaceC::class: InterfaceC

```

#### test_104_sleep_wakeup.php

**目录**: fuzzy_scripts_27/failed

**PHP输出**:
```
=== __sleep/__wakeup ===
Before serialize: name=test, value=42, secret=hidden
Serialized: 62 bytes
After unserialize: name=test, value=42, secret=revealed_after_wakeup

=== Serialize with dynamic ===
Unserialized2: name=test, value=42, secret=revealed_after_wakeup

```

**AOT输出**:
```
=== __sleep/__wakeup ===
Before serialize: name=test, value=42, secret=hidden
Serialized: 90 bytes
After unserialize: name=test, value=42, secret=revealed_after_wakeup

=== Serialize with dynamic ===
Unserialized2: name=test, value=42, secret=revealed_after_wakeup

```

#### test_117_array_find.php

**目录**: fuzzy_scripts_27/failed

**PHP输出**:
```
=== array_find ===
First even: 2
First above 5: 6
Not found result: null

=== Custom find ===
Custom first even: 2

```

**AOT输出**:
```
=== array_find ===
array_find not available

=== Custom find ===
Custom first even: 2

```

#### test_131_anon_interface.php

**目录**: fuzzy_scripts_27/failed

**PHP输出**:
```
=== Anonymous class with interface ===
Value: anonymous_data
Is AnonymousInterface: yes

```

**AOT输出**:
```
=== Anonymous class with interface ===
Value: anonymous_data
Is AnonymousInterface: no

```

#### test_136_multi_catch.php

**目录**: fuzzy_scripts_27/failed

**PHP输出**:
```
=== Multiple catch ===
RuntimeException: Runtime
Logic/Invalid: InvalidArgumentException - Invalid
Logic/Invalid: LogicException - Logic
DomainException: Domain
Throwable: Exception - Generic

```

**AOT输出**:
```
=== Multiple catch ===
Logic/Invalid: RuntimeException - Runtime
Logic/Invalid: InvalidArgumentException - Invalid
Logic/Invalid: LogicException - Logic
DomainException: Domain
Logic/Invalid: Exception - Generic

```

#### test_141_list_destructure.php

**目录**: fuzzy_scripts_27/failed

**PHP输出**:
```
=== List destructuring ===
First three: first, second, third

=== Partial list ===
First and third: first, third

=== Keyed list ===
x=value_x, y=value_y

=== Nested list ===
Nested: a, b, c, d

```

**AOT输出**:
```
=== List destructuring ===
First three: first, second, third

=== Partial list ===
First and third: first, second

=== Keyed list ===
x=value_x, y=value_y

=== Nested list ===
Nested: a, b, c, d

```

#### test_145_heredoc.php

**目录**: fuzzy_scripts_27/failed

**PHP输出**:
```
=== Heredoc ===

Warning: Undefined variable $heredoc in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts_27/failed/test_145_heredoc.php on line 11

Warning: Undefined variable $heredoc in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts_27/failed/test_145_heredoc.php on line 12

Warning: Undefined variable $nowdoc in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts_27/failed/test_145_heredoc.php on line 15

Warning: Undefined variable $no
```

**AOT输出**:
```
=== Heredoc ===
Hello, World!
Value: 42
Expression: 84

=== Nowdoc ===
Hello, $name
No interpolation here

=== Heredoc with indentation ===
    Indented content
    With value

```

#### test_209_memoize.php

**目录**: fuzzy_scripts_27/failed

**PHP输出**:
```
6765
6765
6765
Memoized: 0.000458s, Recursive: 0.000440s, Cached: 0.000003s
OK

```

**AOT输出**:
```
6765
6765
6765
Memoized: 0.011373s, Recursive: 0.004525s, Cached: 0.000025s
OK

```

#### test_224_priority_queue.php

**目录**: fuzzy_scripts_27/failed

**PHP输出**:
```
high priority task
low priority task
medium priority task
OK

```

**AOT输出**:
```

Warning: Trying to access array offset on null in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts_27/failed/test_224_priority_queue.php on line 10

Warning: Trying to access array offset on null in /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts_27/failed/test_224_priority_queue.php on line 10
low priority task
medium priority task
high priority task
OK

[STDERR]
PHP Warning:  Trying to access array offset on null in /Users/tuoke/Desktop/ai-zig-php-parser
```

#### test_226_levenshtein.php

**目录**: fuzzy_scripts_27/failed

**PHP输出**:
```
3
2
3
3
0
OK

```

**AOT输出**:
```
6
3
3
3
3
OK

```

#### test_233_matrix.php

**目录**: fuzzy_scripts_27/failed

**PHP输出**:
```
3
19
50
OK

```

**AOT输出**:
```
4
62
72
OK

```

### 3. AOT_RUNTIME - 运行时错误

| 脚本名称 | 目录 | 错误类型 | 详情 |
|----------|------|----------|------|
| test_006_exceptions.php | fuzzy_scripts_27/failed | AOT_RUNTIME |  Fatal error: Uncaught Error: Call to undefined function set_error_handler() in  |
| test_007_enums.php | fuzzy_scripts_27/failed | AOT_RUNTIME | Status::Active->value: active Status::Active->label(): Active Status Status::Act |
| test_008_datetime.php | fuzzy_scripts_27/failed | AOT_RUNTIME |  Fatal error: Uncaught Error: Class "DateTimeZone" not found in /Users/tuoke/Des |
| test_009_serialization.php | fuzzy_scripts_27/failed | AOT_RUNTIME |  Warning: Undefined variable JSON_PRETTY_PRINT in /Users/tuoke/Desktop/ai-zig-ph |
| test_010_filesystem.php | fuzzy_scripts_27/failed | AOT_RUNTIME |  Fatal error: Uncaught Error: Call to undefined function filemtime() in /Users/t |
| test_012_network.php | fuzzy_scripts_27/failed | AOT_RUNTIME |  Fatal error: Uncaught Error: Call to undefined function gethostbyname() in /Use |
| test_013_regex.php | fuzzy_scripts_27/failed | AOT_RUNTIME |  Warning: Undefined variable $allMatches in /Users/tuoke/Desktop/ai-zig-php-pars |
| test_014_spl.php | fuzzy_scripts_27/failed | AOT_RUNTIME |  [STDERR] error: MethodNotFound ???:?:?: 0x100705217 in _runtime_lib.PHPObject.c |
| test_018_named_args.php | fuzzy_scripts_27/failed | AOT_RUNTIME | === Named Arguments === Name: John, Age: 30, Active: yes, Tags: , Email: none Na |
| test_019_match.php | fuzzy_scripts_27/failed | AOT_RUNTIME | === Match with true condition === object: stdClass instance object: DateTime ins |
| test_022_weakmap.php | fuzzy_scripts_27/failed | AOT_RUNTIME |  [STDERR] error: MethodNotFound ???:?:?: 0x102a9c697 in _runtime_lib.PHPObject.c |
| test_023_cloning.php | fuzzy_scripts_27/failed | AOT_RUNTIME | After clone: a.value = 100, b.value = 200 Original nested inner data: modified C |
| test_027_constants.php | fuzzy_scripts_27/failed | AOT_RUNTIME | === Final constants === ConstantsLab::FINAL_STRING: final_string ConstantsLab::F |
| test_028_hooks.php | fuzzy_scripts_27/failed | AOT_RUNTIME |  Parse error: syntax error, unexpected "(", expecting "{" in /Users/tuoke/Deskto |
| test_029_new_functions.php | fuzzy_scripts_27/failed | AOT_RUNTIME | === New string functions ===  Fatal error: Uncaught Error: Call to undefined fun |
| test_034_interfaces.php | fuzzy_scripts_27/failed | AOT_CRASH | === ArrayAccess implementation === obj['a']: 1 isset(obj['b']): true isset(obj[' |
| test_035_output_buffer.php | fuzzy_scripts_27/failed | AOT_RUNTIME | === Output Buffer Lab ===  Fatal error: Uncaught Error: Call to undefined functi |
| test_037_globals.php | fuzzy_scripts_27/failed | AOT_RUNTIME | === Globals Lab === GLOBALS['test_var']:  count(GLOBALS): 0 keys After unset, is |
| test_039_variable_funcs.php | fuzzy_scripts_27/failed | AOT_RUNTIME | === Variable functions === strlen('hello'): 5 strtoupper('hello'): HELLO array_s |
| test_040_constants.php | fuzzy_scripts_27/failed | AOT_RUNTIME | === Abstract class === abstractMethod: Implemented abstract concreteMethod: Conc |
| test_041_exceptions2.php | fuzzy_scripts_27/failed | AOT_RUNTIME | === Exception Lab 2 === Try block 1 Caught RuntimeException: First exception Try |
| test_047_const_expr.php | fuzzy_scripts_27/failed | AOT_RUNTIME | === Const Expressions === SUM:  PRODUCT:  MIXED:  STRING_CONCAT:  ARRAY_CONST:   |
| test_051_anonymous.php | fuzzy_scripts_27/failed | AOT_RUNTIME | === Anonymous classes === Anonymous class: anonymous_class_0 Anonymous value: an |
| test_052_const_expr2.php | fuzzy_scripts_27/failed | AOT_RUNTIME |  Parse error: syntax error, unexpected token, expecting ";" in /Users/tuoke/Desk |
| test_055_static_late.php | fuzzy_scripts_27/failed | AOT_RUNTIME | === Static method binding === StaticBase::getName(): StaticBase StaticBase::getN |
| test_056_interfaces.php | fuzzy_scripts_27/failed | AOT_RUNTIME | === Interface constants === A::A_CONST:  B::B_CONST:  C::C_CONST:  C extends A,  |
| test_058_arrayiterators.php | fuzzy_scripts_27/failed | AOT_RUNTIME |  Fatal error: Uncaught Error: Class "ArrayObject" not found in /Users/tuoke/Desk |
| test_059_filter_iterator.php | fuzzy_scripts_27/failed | AOT_RUNTIME | === FilterIterator ===  Fatal error: Uncaught Error: Call to undefined function  |
| test_060_iterators.php | fuzzy_scripts_27/failed | AOT_RUNTIME | === NumberRange iterator ===   [0] => 0   [1] => 2   [2] => 4   [3] => 6   [4] = |
| test_071_const_expr3.php | fuzzy_scripts_27/failed | AOT_RUNTIME | === Constant expressions === SIMPLE: 100 WITH_EXPRESSION: null WITH_PARENS: null |
| test_078_iterators2.php | fuzzy_scripts_27/failed | AOT_RUNTIME |  Fatal error: Uncaught Error: Class "ArrayObject" not found in /Users/tuoke/Desk |
| test_079_datetime2.php | fuzzy_scripts_27/failed | AOT_RUNTIME | === DateInterval ===  Fatal error: Uncaught Error: Class "DateInterval" not foun |
| test_081_hash.php | fuzzy_scripts_27/failed | AOT_RUNTIME | === Hash === md5('hello'): 5d41402abc4b2a76b9719d911017c592 sha1('hello'): aaf4c |
| test_082_json.php | fuzzy_scripts_27/failed | AOT_RUNTIME | === JsonSerializable === json_encode: {"value":42,"name":"test"}  === Nested === |
| test_084_strings.php | fuzzy_scripts_27/failed | AOT_RUNTIME | === Length functions === strlen('hello'): 5  Fatal error: Uncaught Error: Call t |
| test_085_math.php | fuzzy_scripts_27/failed | AOT_RUNTIME | === Basic math === abs(-10): 10 round(3.5): 4 floor(3.9): 3 ceil(3.1): 4  === Po |
| test_086_filesystem.php | fuzzy_scripts_27/failed | AOT_RUNTIME | === Directory functions === sys_get_temp_dir(): /tmp  === File operations === is |
| test_094_const_visibility.php | fuzzy_scripts_27/failed | AOT_RUNTIME | === Constant visibility === PUBLIC: public_const getProtected: protected_const g |
| test_105_final_const.php | fuzzy_scripts_27/failed | AOT_RUNTIME | === Final constants === FINAL_STRING: final_string FINAL_INT: 42 FINAL_ARRAY: nu |
| test_111_timezone.php | fuzzy_scripts_27/failed | AOT_RUNTIME |  Fatal error: Uncaught Error: Class "DateTimeZone" not found in /Users/tuoke/Des |
| test_112_callable.php | fuzzy_scripts_27/failed | AOT_RUNTIME | === call_user_func ===  Fatal error: Uncaught Error: Call to undefined function  |
| test_113_extract_compact.php | fuzzy_scripts_27/failed | AOT_RUNTIME | === compact === compact('name', 'age', 'city', 'active'): {"name":"Alice","age": |
| test_115_get_debug_type.php | fuzzy_scripts_27/failed | AOT_RUNTIME | === get_debug_type ===  Fatal error: Uncaught Error: Call to undefined function  |
| test_121_weakmap.php | fuzzy_scripts_27/failed | AOT_RUNTIME | === WeakMap basic === WeakMap count: 2  [STDERR] error: MethodNotFound ???:?:?:  |
| test_122_closure_call.php | fuzzy_scripts_27/failed | AOT_RUNTIME | === Closure::call ===  [STDERR] error: NotAnObject ???:?:?: 0x102c53763 in _runt |
| test_130_spread_method.php | fuzzy_scripts_27/failed | AOT_RUNTIME |  Parse error: syntax error, unexpected variable "$numbers", expecting ")" in /Us |
| test_144_const_expressions.php | fuzzy_scripts_27/failed | AOT_RUNTIME | === Constant expressions === TIME_BASED: 300 ARRAY_CONST: [1,2,3,4,5] STRING_CON |
| test_147_logical_ops.php | fuzzy_scripts_27/failed | AOT_RUNTIME |  Parse error: syntax error, unexpected token, expecting ")" in /Users/tuoke/Desk |
| test_148_error_handling.php | fuzzy_scripts_27/failed | AOT_RUNTIME | === @ operator ===  Warning: Undefined variable $undefined_var in /Users/tuoke/D |
| test_153_closure_binding.php | fuzzy_scripts_27/failed | AOT_RUNTIME | === Closure binding ===  [STDERR] error: ClassNotFound ???:?:?: 0x1041f4dbb in _ |
| test_165_const_arrays.php | fuzzy_scripts_27/failed | AOT_RUNTIME | === Constant arrays === NUMBERS: null ASSOCIATIVE: null MIXED: null  === Access  |
| test_201_stream_wrapper.php | fuzzy_scripts_27/failed | AOT_RUNTIME |  Fatal error: Uncaught Error: Call to undefined function stream_register_wrapper |
| test_229_expression_parser.php | fuzzy_scripts_27/failed | AOT_RUNTIME |  Fatal error: Uncaught Error: Call to undefined function ctype_space() in /Users |
| test_257_date_helper.php | fuzzy_scripts_27/failed | AOT_RUNTIME | truefalse true 167  [STDERR] error: MethodNotFound ???:?:?: 0x100385717 in _runt |
| test_258_url_helper.php | fuzzy_scripts_27/failed | AOT_RUNTIME |  Fatal error: Uncaught Error: Call to undefined function parse_url() in /Users/t |
| test_291_string_check.php | fuzzy_scripts_27/failed | AOT_RUNTIME | truetruetrue Fatal error: Uncaught Error: Call to undefined function mb_strlen() |
| test_292_string_case_ops.php | fuzzy_scripts_27/failed | AOT_RUNTIME | HELLO hello Hello World Hello hELLO  Fatal error: Uncaught Error: Call to undefi |
| test_293_string_pos.php | fuzzy_scripts_27/failed | AOT_RUNTIME | 6 12 false  Fatal error: Uncaught Error: Call to undefined function substr_count |
| test_296_trim.php | fuzzy_scripts_27/failed | AOT_RUNTIME | 11 trueHello   World  PHP  Fatal error: Uncaught Error: Call to undefined functi |
| test_297_char_ops.php | fuzzy_scripts_27/failed | AOT_RUNTIME | 65 A 5d41402abc4b2a76b9719d911017c592 aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d   |

### 4. PHP_FAIL - PHP原生执行失败

> 以下脚本在原生PHP执行时本身存在错误，不计入AOT问题统计

| 脚本名称 | 目录 |
|----------|------|
| test_001_complex_oop.php | fuzzy_scripts_27/failed |
| test_003_closures.php | fuzzy_scripts_27/failed |
| test_004_strings.php | fuzzy_scripts_27/failed |
| test_011_reflection.php | fuzzy_scripts_27/failed |
| test_015_dynamic.php | fuzzy_scripts_27/failed |
| test_020_functional.php | fuzzy_scripts_27/failed |
| test_024_iterators.php | fuzzy_scripts_27/failed |
| test_025_callables.php | fuzzy_scripts_27/failed |
| test_026_readonly.php | fuzzy_scripts_27/failed |
| test_030_namespaces.php | fuzzy_scripts_27/failed |
| test_049_strings.php | fuzzy_scripts_27/failed |
| test_050_spread.php | fuzzy_scripts_27/failed |
| test_053_constructors.php | fuzzy_scripts_27/failed |
| test_061_closure_bind.php | fuzzy_scripts_27/failed |
| test_072_namespace.php | fuzzy_scripts_27/failed |
| test_074_dynamic_vars.php | fuzzy_scripts_27/failed |
| test_075_closures.php | fuzzy_scripts_27/failed |
| test_080_partial_application.php | fuzzy_scripts |
| test_083_arrayaccess.php | fuzzy_scripts_27/failed |
| test_088_reflection.php | fuzzy_scripts_27/failed |
| test_089_reflection2.php | fuzzy_scripts_27/failed |
| test_099_iterator_aggregate.php | fuzzy_scripts_27/failed |
| test_124_dynamic_const.php | fuzzy_scripts_27/failed |
| test_126_named_variadic.php | fuzzy_scripts_27/failed |
| test_128_resource_id.php | fuzzy_scripts_27/failed |
| test_129_intersection.php | fuzzy_scripts_27/failed |
| test_132_object_storage.php | fuzzy_scripts_27/failed |
| test_133_callback_array.php | fuzzy_scripts_27/failed |
| test_134_namespace_alias.php | fuzzy_scripts_27/failed |
| test_139_trait_resolution.php | fuzzy_scripts_27/failed |
| test_207_event_emitter.php | fuzzy_scripts_27/failed |
| test_244_stack.php | fuzzy_scripts_27/failed |

---

## 问题分类统计

### 编译错误类型分布

| 错误类型 | 数量 |
|----------|------|

---

*报告生成完成于 2026-03-24 12:54:05*

---

## 已修复问题 (更新于 2026-03-24)

### 修复记录

| 问题 | 修复内容 | 修复文件 |
|------|----------|----------|
| NAN输出格式 | 修复var_export/printValue中NAN/INF输出为大写格式 | runtime_lib_template.zig |
| instanceof接口检查 | 修复接口继承链检查，递归检查父接口 | runtime_lib_template.zig (implementsInterface) |
| 接口继承处理 | 修复IR生成器中接口extends处理，正确收集父接口 | ir_generator.zig (generateInterfaceDecl) |
| isset属性检查 | 修复isset()对属性值为null的情况处理，属性存在但值为null时返回false | runtime_lib_template.zig (php_object_isset) |
| 内置接口注册 | 添加registerBuiltinInterfaces函数注册PHP内置接口(Countable等) | runtime_lib_template.zig |
| 多重捕获异常 | 修复catch子句中联合类型(如 A\|B)的处理 | ir_generator.zig |
| 方法命名参数 | 添加方法调用中命名参数的处理支持 | ir_generator.zig, runtime_lib_template.zig |
| filemtime/atime/ctime | 实现文件时间戳函数 | runtime_lib_template.zig |
| gethostbyname/gethostname | 实现主机名解析函数 | runtime_lib_template.zig |
| ip2long/long2ip | 实现IP地址转换函数 | runtime_lib_template.zig |
| parse_url | 实现URL解析函数 | runtime_lib_template.zig |
| set_error_handler | 实现错误处理器注册函数 | runtime_lib_template.zig |
| restore_error_handler | 实现错误处理器恢复函数 | runtime_lib_template.zig |
| trigger_error | 实现用户错误触发函数 | runtime_lib_template.zig |
| error_reporting | 实现错误报告级别设置函数 | runtime_lib_template.zig |
| ctype_* 函数 | 实现 ctype_alnum, ctype_alpha, ctype_cntrl, ctype_digit, ctype_graph, ctype_lower, ctype_print, ctype_punct, ctype_space, ctype_upper, ctype_xdigit | runtime_lib_template.zig |
| mb_strlen | 实现多字节字符串长度计算（支持UTF-8） | runtime_lib_template.zig |
| mb_substr | 实现多字节字符串截取（支持UTF-8） | runtime_lib_template.zig |
| mb_strtoupper | 实现多字节字符串大写转换 | runtime_lib_template.zig |
| mb_strtolower | 实现多字节字符串小写转换 | runtime_lib_template.zig |
| substr_count | 实现子字符串计数函数 | runtime_lib_template.zig |
| ucfirst/lcfirst | 实现首字母大小写转换 | runtime_lib_template.zig |
| ucwords | 实现单词首字母大写 | runtime_lib_template.zig |
| strrpos/strripos | 实现字符串反向查找函数 | runtime_lib_template.zig |
| str_word_count | 实现单词计数函数 | runtime_lib_template.zig |
| substr | 实现字符串截取函数 | runtime_lib_template.zig |
| strpos | 实现字符串位置查找函数 | runtime_lib_template.zig |
| floor/ceil | 实现向下/向上取整函数 | runtime_lib_template.zig |
| sin/cos/tan | 实现三角函数 | runtime_lib_template.zig |
| log/exp | 实现对数和指数函数 | runtime_lib_template.zig |
| hypot | 实现斜边计算函数 | runtime_lib_template.zig |
| pow | 实现幂运算函数 | runtime_lib_template.zig |
| min/max | 实现最小/最大值函数 | runtime_lib_template.zig |
| stripos | 实现不区分大小写的字符串位置查找 | runtime_lib_template.zig |
| strstr | 实现字符串查找函数 | runtime_lib_template.zig |
| str_split | 实现字符串分割函数 | runtime_lib_template.zig |
| implode/explode | 实现字符串连接和分割函数 | runtime_lib_template.zig |
| is_callable | 实现回调检查函数 | runtime_lib_template.zig |
| get_debug_type | 实现调试类型获取函数 | runtime_lib_template.zig |
| call_user_func | 实现回调函数调用 | runtime_lib_template.zig |
| call_user_func_array | 实现带数组参数的回调函数调用 | runtime_lib_template.zig |
| compact | 实现变量打包函数 | runtime_lib_template.zig |
| extract | 实现数组解包函数 | runtime_lib_template.zig |
| ord/chr | 实现字符编码转换函数 | runtime_lib_template.zig |
| md5/sha1 | 实现哈希函数 | runtime_lib_template.zig |
| crc32 | 实现CRC32校验函数 | runtime_lib_template.zig |
| strrev | 实现字符串反转函数 | runtime_lib_template.zig |
| ltrim/rtrim | 实现左侧/右侧空白去除函数 | runtime_lib_template.zig |
| addslashes/stripslashes | 实现字符串转义和反转义函数 | runtime_lib_template.zig |
| 常量继承 | 修复 parent::CONSTANT 和 self::CONSTANT 的常量访问 | ir_generator.zig |

### 待修复问题

| 问题 | 状态 | 复杂度 |
|------|------|--------|
| foreach引用语义 | 待修复 | 高 |
| array_keys/array_values顺序 | 待修复 | 中 |
| 继承中private属性作用域 | 待修复 | 高 |
| 字符串插值 | 待修复 | 中 |
| late static binding | 待修复 | 高 |
| clone浅拷贝 | 待修复 | 中 |
| property_exists静态调用 | 待修复 | 低 |
| 序列化长度差异 | 待修复 | 低 |
| 缺失内置函数 | 待修复 | 中 |
