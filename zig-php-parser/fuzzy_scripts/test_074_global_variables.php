<?php
// 测试74: global关键字与$GLOBALS数组
$global_var = "initial";

function modify_global() {
    global $global_var;
    $global_var = "modified";
}

function modify_globals_array() {
    $GLOBALS['global_var'] = "modified_via_globals";
}

modify_global();
echo "After modify_global: $global_var
";

modify_globals_array();
echo "After modify_globals_array: $global_var
";

// 函数中的global
function create_counter() {
    global $counter;
    static $initialized = false;
    if (!$initialized) {
        $counter = 0;
        $initialized = true;
    }
    return ++$counter;
}

echo "Counter: " . create_counter() . "
";
echo "Counter: " . create_counter() . "
";

// 超全局变量
echo "Request method: " . ($_SERVER['REQUEST_METHOD'] ?? 'CLI') . "
";

// 动态global变量
$var_name = 'dynamic_var';
$$var_name = "dynamic_value";
echo "Dynamic var: $dynamic_var
";
?>