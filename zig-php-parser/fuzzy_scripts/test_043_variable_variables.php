<?php
// 测试43: 变量变量与动态特性
$a = "hello";
$$a = "world";
echo "hello = $hello\n";

// 动态函数调用
$func = "strlen";
echo "Dynamic strlen: " . $func("test") . "\n";

// 动态方法调用
class Dynamic {
    public function method1(): string {
        return "method1 called";
    }
    
    public function method2(): string {
        return "method2 called";
    }
}

$obj = new Dynamic();
$method = "method1";
echo $obj->$method() . "\n";

// 动态类名
$class = "Dynamic";
$instance = new $class();
echo get_class($instance) . "\n";

// 可变变量嵌套
$x = "y";
$y = "z";
$z = "final value";
echo "$$$x = " . $$x . "\n";
// echo "$$$$x = " . ${${$x}} . "\n"; // Skip complex variable variable

// 动态属性
$prop = "dynamic";
$obj->$prop = "dynamic value";
echo "obj->dynamic = " . $obj->dynamic . "\n";

// call_user_func
echo call_user_func("strlen", "hello") . "\n";
echo call_user_func_array([$obj, "method1"], []) . "\n";

// 动态include (这里只模拟路径)
// $file = "config.php";
// include $file;

// compact与extract
$var1 = "value1";
$var2 = "value2";
$arr = compact("var1", "var2");
echo "Compacted: ";
print_r($arr);

extract(["newVar" => "extracted"]);
echo "Extracted: $newVar\n";

// 变量引用
$ref1 = "original";
$ref2 = &$ref1;
$ref2 = "modified";
echo "ref1 = $ref1, ref2 = $ref2\n";
?>
