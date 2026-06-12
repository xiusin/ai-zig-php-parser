<?php
// DNF类型测试 (PHP 8.2+)

// 定义接口
interface Serializable {
    public function serialize(): string;
}

interface Cacheable {
    public function cacheKey(): string;
}

interface Loggable {
    public function log(): string;
}

// 实现多个接口
class SerializableCache implements Serializable, Cacheable {
    private string $data;

    public function __construct(string $data) {
        $this->data = $data;
    }

    public function serialize(): string {
        return serialize($this->data);
    }

    public function cacheKey(): string {
        return md5($this->data);
    }
}

class CacheableLoggable implements Cacheable, Loggable {
    public function cacheKey(): string {
        return 'cache_' . uniqid();
    }

    public function log(): string {
        return 'Logged action';
    }
}

class FullImplementation implements Serializable, Cacheable, Loggable {
    public function serialize(): string {
        return 'serialized';
    }

    public function cacheKey(): string {
        return 'cache_key';
    }

    public function log(): string {
        return 'logged';
    }
}

// DNF类型：(A&B)|null 或 (A&B)|(C&D)
function processCacheable(?Cacheable&Loggable $handler): ?string {
    return $handler?->cacheKey();
}

$cl1 = new CacheableLoggable();
echo "CacheableLoggable key: " . processCacheable($cl1) . "\n";
echo "Null handler: " . var_export(processCacheable(null), true) . "\n";

// 复杂DNF类型
function handle(
    (Serializable&Cacheable)|(Cacheable&Loggable) $handler
): string {
    if ($handler instanceof Serializable) {
        return "Can serialize: " . $handler->serialize();
    }
    return "Can cache and log: " . $handler->cacheKey();
}

$sc = new SerializableCache('test data');
echo "Handle SC: " . handle($sc) . "\n";

$cl = new CacheableLoggable();
echo "Handle CL: " . handle($cl) . "\n";

// 三接口组合
function fullHandler(
    Serializable&Cacheable&Loggable $handler
): string {
    return implode(', ', [
        $handler->serialize(),
        $handler->cacheKey(),
        $handler->log()
    ]);
}

$full = new FullImplementation();
echo "Full handler: " . fullHandler($full) . "\n";

// DNF类型作为返回值
function createHandler(bool $type): (Serializable&Cacheable)|null {
    if ($type) {
        return new SerializableCache('created');
    }
    return null;
}

$created = createHandler(true);
echo "Created handler: " . ($created?->serialize() ?? 'null') . "\n";

// 类属性DNF类型
class HandlerContainer {
    private ?Cacheable&Loggable $handler = null;

    public function set(?Cacheable&Loggable $handler): void {
        $this->handler = $handler;
    }

    public function get(): ?string {
        return $this->handler?->cacheKey();
    }
}

$container = new HandlerContainer();
echo "Empty container: " . var_export($container->get(), true) . "\n";

$container->set(new CacheableLoggable());
echo "Set container: " . $container->get() . "\n";

// DNF与联合类型结合
function mixedHandler(
    (Serializable&Cacheable)|string|array $input
): string {
    if ($input instanceof Serializable) {
        return $input->serialize();
    }
    if (is_string($input)) {
        return $input;
    }
    return serialize($input);
}

echo "String input: " . mixedHandler('direct string') . "\n";
echo "Array input: " . mixedHandler(['a', 'b']) . "\n";
echo "Object input: " . mixedHandler(new SerializableCache('obj data')) . "\n";

// 类型检查
$check = new SerializableCache('check');
echo "Instanceof Serializable: " . var_export($check instanceof Serializable, true) . "\n";
echo "Instanceof Cacheable: " . var_export($check instanceof Cacheable, true) . "\n";
echo "Instanceof Loggable: " . var_export($check instanceof Loggable, true) . "\n";

echo "DNF types tests completed\n";
