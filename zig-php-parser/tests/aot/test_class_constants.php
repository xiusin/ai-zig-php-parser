<?php

class Config {
    public const VERSION = "1.0.0";
    public const MAX_SIZE = 1024;
    public const DEBUG = true;
    
    private const SECRET = "secret_key";
    
    public static function getVersion(): string {
        return self::VERSION;
    }
    
    public static function getSecret(): string {
        return self::SECRET;
    }
}

// 测试 1: 直接访问公共常量
echo "Version: " . Config::VERSION . "\n";
echo "Max size: " . Config::MAX_SIZE . "\n";
echo "Debug: " . (Config::DEBUG ? "true" : "false") . "\n";

// 测试 2: 通过方法访问
echo "Version (method): " . Config::getVersion() . "\n";
echo "Secret (method): " . Config::getSecret() . "\n";

// 测试 3: 在类内部使用
class App {
    public const NAME = "MyApp";
    
    public function getName(): string {
        return self::NAME;
    }
}

$app = new App();
echo "App name: " . $app->getName() . "\n";
echo "App name (static): " . App::NAME . "\n";
