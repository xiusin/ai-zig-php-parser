<?php
// 命名空间测试

namespace Test\Namespace;

class MyClass {
    public function sayHello(): string {
        return "Hello from Test\\Namespace\\MyClass";
    }
}

function myFunction(): string {
    return "Function from Test\\Namespace";
}

const MY_CONST = "Constant from Test\\Namespace";

// 使用当前命名空间
$obj = new MyClass();
echo $obj->sayHello() . "\n";
echo myFunction() . "\n";
echo MY_CONST . "\n";

// 切换到全局命名空间
namespace {
    // 使用完整限定名
    $obj = new \Test\Namespace\MyClass();
    echo $obj->sayHello() . "\n";
    echo \Test\Namespace\myFunction() . "\n";
    echo \Test\Namespace\MY_CONST . "\n";
}

namespace Another\Namespace;

use Test\Namespace\MyClass;
use Test\Namespace\myFunction;
use const Test\Namespace\MY_CONST;
use function Test\Namespace\myFunction as importedFunc;

// 使用导入的类
$obj = new MyClass();
echo "Imported: " . $obj->sayHello() . "\n";

// 使用导入的函数
echo "Imported function: " . importedFunc() . "\n";

// 使用导入的常量
echo "Imported const: " . MY_CONST . "\n";

namespace {
    // 定义多个命名空间中的类
    class GlobalClass {
        public function identify(): string {
            return "GlobalClass";
        }
    }

    $global = new GlobalClass();
    echo $global->identify() . "\n";

    // 使用别名
    use Test\Namespace\MyClass as TNClass;
    use function Test\Namespace\myFunction as TNFunc;
    use const Test\Namespace\MY_CONST as TNCONST;

    $aliased = new TNClass();
    echo "Aliased: " . $aliased->sayHello() . "\n";
    echo "Aliased function: " . TNFunc() . "\n";
    echo "Aliased const: " . TNCONST . "\n";

    // __NAMESPACE__常量
    echo "Current namespace: " . (__NAMESPACE__ ?: 'global') . "\n";

    // 动态访问命名空间类
    $className = '\Test\Namespace\MyClass';
    $dynamicObj = new $className();
    echo "Dynamic: " . $dynamicObj->sayHello() . "\n";
}

// 命名空间分组
namespace Grouped\Namespace;

use Test\Namespace\{MyClass, myFunction};
use const Test\Namespace\{MY_CONST};

echo "Grouped import function: " . myFunction() . "\n";
echo "Grouped import const: " . MY_CONST . "\n";

// 回到全局命名空间
namespace {
    echo "Namespace tests completed\n";
}
