<?php
// OOP接口测试

// 接口定义
interface Flyable {
    public function fly(): string;
}

interface Swimmable {
    public function swim(): string;
}

interface Speakable {
    public function speak(): string;
}

// 实现多个接口
class Duck implements Flyable, Swimmable, Speakable {
    private string $name;

    public function __construct(string $name) {
        $this->name = $name;
    }

    public function fly(): string {
        return "{$this->name} is flying";
    }

    public function swim(): string {
        return "{$this->name} is swimming";
    }

    public function speak(): string {
        return "Quack!";
    }
}

$duck = new Duck('Donald');
echo $duck->fly() . "\n";
echo $duck->swim() . "\n";
echo $duck->speak() . "\n";

// 接口继承
interface Animal {
    public function getName(): string;
}

interface Bird extends Animal {
    public function fly(): string;
}

class Sparrow implements Bird {
    public function __construct(private string $name) {}

    public function getName(): string {
        return $this->name;
    }

    public function fly(): string {
        return "{$this->name} is flying";
    }
}

$sparrow = new Sparrow('Jack');
echo "Name: " . $sparrow->getName() . "\n";
echo $sparrow->fly() . "\n";

// 接口中的常量
interface Status {
    const ACTIVE = 'active';
    const INACTIVE = 'inactive';
    const PENDING = 'pending';

    public function getStatus(): string;
}

class User implements Status {
    private string $status;

    public function __construct(string $status = Status::PENDING) {
        $this->status = $status;
    }

    public function getStatus(): string {
        return $this->status;
    }
}

$user = new User(Status::ACTIVE);
echo "Status: " . $user->getStatus() . "\n";
echo "Constant: " . Status::ACTIVE . "\n";

// 接口类型提示
function makeItFly(Flyable $flying): string {
    return $flying->fly();
}

class Plane implements Flyable {
    public function fly(): string {
        return "Plane is flying";
    }
}

echo makeItFly(new Duck('Daffy')) . "\n";
echo makeItFly(new Plane()) . "\n";

// 接口instanceof
$duck = new Duck('Daisy');
echo "duck instanceof Flyable: " . var_export($duck instanceof Flyable, true) . "\n";
echo "duck instanceof Swimmable: " . var_export($duck instanceof Swimmable, true) . "\n";
echo "duck instanceof Speakable: " . var_export($duck instanceof Speakable, true) . "\n";

// 抽象类实现接口
interface Logger {
    public function log(string $message): void;
}

abstract class BaseLogger implements Logger {
    protected string $prefix;

    public function __construct(string $prefix = '') {
        $this->prefix = $prefix;
    }

    abstract public function log(string $message): void;

    protected function format(string $message): string {
        return "{$this->prefix}$message";
    }
}

class FileLogger extends BaseLogger {
    public function log(string $message): void {
        echo "File: " . $this->format($message) . "\n";
    }
}

$logger = new FileLogger('[INFO] ');
$logger->log('Application started');

// 接口多态
function processAnimal(Speakable $animal): void {
    echo "Animal says: " . $animal->speak() . "\n";
}

processAnimal(new Duck('Howard'));
