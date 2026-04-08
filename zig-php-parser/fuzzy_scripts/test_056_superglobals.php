<?php
// 超全局变量测试

// $GLOBALS
$testVar = 'global value';
echo "GLOBALS testVar: " . $GLOBALS['testVar'] . "\n";

$GLOBALS['newGlobal'] = 'new value';
echo "newGlobal: $newGlobal\n";

// $_SERVER 测试
echo "PHP_VERSION: " . PHP_VERSION . "\n";
echo "PHP_OS: " . PHP_OS . "\n";
echo "PHP_SAPI: " . PHP_SAPI . "\n";
echo "PHP_INT_MAX: " . PHP_INT_MAX . "\n";

// 定义自定义常量
define('APP_NAME', 'TestApp');
define('APP_VERSION', '1.0.0');
echo "APP_NAME: " . APP_NAME . "\n";
echo "APP_VERSION: " . APP_VERSION . "\n";

// 魔术常量
echo "__LINE__: " . __LINE__ . "\n";
echo "__FILE__: " . basename(__FILE__) . "\n";
echo "__DIR__: " . basename(__DIR__) . "\n";

// 在函数中
function testMagicConstants() {
    echo "__FUNCTION__: " . __FUNCTION__ . "\n";
    echo "__NAMESPACE__: " . (__NAMESPACE__ ?: 'global') . "\n";
}
testMagicConstants();

// 在类中
class MagicTest {
    public function show() {
        echo "__CLASS__: " . __CLASS__ . "\n";
        echo "__METHOD__: " . __METHOD__ . "\n";
    }
}
$magic = new MagicTest();
$magic->show();

// 预定义常量
echo "PHP_EOL exists: " . var_export(defined('PHP_EOL'), true) . "\n";
echo "PHP_INT_SIZE: " . PHP_INT_SIZE . "\n";

// 布尔常量
echo "TRUE: " . var_export(TRUE, true) . "\n";
echo "FALSE: " . var_export(FALSE, true) . "\n";
echo "NULL: " . var_export(NULL, true) . "\n";

// 运行时获取常量
$userConstants = array_filter(
    get_defined_constants(true)['user'] ?? [],
    fn($k) => strpos($k, 'APP_') === 0,
    ARRAY_FILTER_USE_KEY
);
echo "User constants: " . count($userConstants) . "\n";

// getenv
$home = getenv('HOME');
echo "HOME env: " . ($home ? basename($home) : 'not set') . "\n";

// $_ENV (可能为空取决于配置)
if (!empty($_ENV)) {
    echo "ENV count: " . count($_ENV) . "\n";
} else {
    echo "ENV is empty\n";
}

// argc/argv (CLI模式)
if (defined('STDIN')) {
    echo "Running in CLI mode\n";
}

// 超全局变量存在检查
$superglobals = ['GLOBALS', '_SERVER', '_GET', '_POST', '_FILES', '_COOKIE', '_SESSION', '_REQUEST', '_ENV'];
foreach ($superglobals as $sg) {
    echo "$sg exists: " . var_export(isset($GLOBALS[$sg]), true) . "\n";
}

echo "Superglobals tests completed\n";
