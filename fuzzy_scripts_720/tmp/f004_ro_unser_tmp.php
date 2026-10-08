<?php
// 永久探针（任务 #114，2026-10-07）：语料 f004_oop_deep_inheritance_magic.php 因 PHP 8.3+ 的 readonly 违规
// （__unserialize 里重写 readonly 属性）在真值侧 exit=255 ⇒ 官方回归把整枚脚本 SKIP，其下半段
// （深继承链 __serialize/__unserialize 回填、final 方法、按类 static 计数的晚期静态绑定、__toString/sprintf/json_encode）
// 在 68 语料里零 AOT 覆盖。本探针按宪法 §七-8 第二条「保持原测试意图，仅移除导致失败的语法」回收覆盖，
// 并把「移除的那一处」单独隔离成第三形，逐形只改一个变量：
//   valid —— 移除 readonly（唯一违规点），其余与 f004 同构：链式 parent::__serialize/__unserialize + final + static 计数 + __toString
//   ro_ok —— 保留 readonly，但 __unserialize 不写 readonly 属性 ⇒ 测 readonly 正向语义不被误伤
//   fatal —— 复刻 f004 的违规写法 ⇒ 测 AOT 与 PHP 在 readonly 强制上的错误归属（声明类 vs 实例类）
$shape = isset($argv[1]) ? $argv[1] : 'valid';

// ---- shape=valid：无 readonly 的同构链 ----
class VBase {
    protected static int $entityCount = 0;
    protected array $meta = [];

    public function __construct(public string $uuid) {
        static::$entityCount++;
    }

    public function setMeta(string $key, mixed $value): void {
        $this->meta[$key] = $value;
    }

    public function getMeta(string $key, mixed $default = null): mixed {
        return $this->meta[$key] ?? $default;
    }

    public function __serialize(): array {
        return ['uuid' => $this->uuid, 'meta' => $this->meta];
    }

    public function __unserialize(array $data): void {
        $this->uuid = $data['uuid'];
        $this->meta = $data['meta'];
    }

    final public function getUuid(): string {
        return $this->uuid;
    }

    public static function getEntityCount(): int {
        return static::$entityCount;
    }
}

class VUser extends VBase {
    protected static int $entityCount = 0;

    public function __construct(string $uuid, public string $name, public array $roles = []) {
        parent::__construct($uuid);
    }

    public function __serialize(): array {
        return array_merge(parent::__serialize(), ['name' => $this->name, 'roles' => $this->roles]);
    }

    public function __unserialize(array $data): void {
        parent::__unserialize($data);
        $this->name = $data['name'];
        $this->roles = $data['roles'];
    }

    public function hasRole(string $role): bool {
        return in_array($role, $this->roles);
    }

    public function __toString(): string {
        return sprintf("VUser[%s]{%s, roles=[%s]}", $this->uuid, $this->name, implode(',', $this->roles));
    }
}

// ---- shape=ro_ok：保留 readonly，反序列化不写 readonly ----
class RBase {
    protected static int $entityCount = 0;
    protected array $meta = [];

    public function __construct(public readonly string $uuid) {
        static::$entityCount++;
    }

    public function __serialize(): array {
        return ['uuid' => $this->uuid, 'meta' => $this->meta];
    }

    public function __unserialize(array $data): void {
        $this->meta = $data['meta'];
    }

    final public function getUuid(): string {
        return $this->uuid;
    }

    public static function getEntityCount(): int {
        return static::$entityCount;
    }
}

class RUser extends RBase {
    protected static int $entityCount = 0;

    public function __construct(string $uuid, public string $name, public array $roles = []) {
        parent::__construct($uuid);
    }

    public function __serialize(): array {
        return array_merge(parent::__serialize(), ['name' => $this->name, 'roles' => $this->roles]);
    }

    public function __unserialize(array $data): void {
        parent::__unserialize($data);
        $this->name = $data['name'];
        $this->roles = $data['roles'];
    }

    public function __toString(): string {
        return sprintf("RUser[%s]{%s, roles=[%s]}", $this->uuid, $this->name, implode(',', $this->roles));
    }
}

// ---- shape=fatal：复刻 f004 违规（__unserialize 写 readonly）----
class BBase {
    protected array $meta = [];

    public function __construct(public readonly string $uuid) {
    }

    public function __unserialize(array $data): void {
        $this->uuid = $data['uuid'];
    }

    final public function getUuid(): string {
        return $this->uuid;
    }
}

class BUser extends BBase {
    public function __unserialize(array $data): void {
        parent::__unserialize($data);
    }
}

// ---- 消息归属同族面：继承来的 private / typed 属性 + 动态写 readonly ----
class MBase {
    private string $secret = 'S';
    protected int $limit = 1;
    public int $total = 0;

    public function __construct(public readonly string $uuid) {
    }
}

class MChild extends MBase {
    public int $count = 0;

    public function scopeNames(): string {
        return 'self=' . self::class . ' static=' . static::class . ' parent=' . parent::class;
    }
}

echo "SHAPE=$shape\n";

if ($shape === 'valid') {
    $u = new VUser("U001", "Alice", ['user', 'editor']);
    $u->setMeta('created', '2025-01-01');
    $u->setMeta('ip', '192.168.1.1');
    echo "before=$u\n";
    echo "hasEditor=" . var_export($u->hasRole('editor'), true) . "\n";
    echo "metaCreated=" . $u->getMeta('created') . "\n";
    echo "metaMissing=" . var_export($u->getMeta('missing', 'D'), true) . "\n";
    $ser = $u->__serialize();
    echo "serialized=" . json_encode($ser) . "\n";
    $u2 = new VUser("TEMP", "TEMP");
    $u2->__unserialize($ser);
    echo "after=$u2\n";
    echo "finalUuid=" . $u2->getUuid() . "\n";
    echo "countBase=" . VBase::getEntityCount() . " countUser=" . VUser::getEntityCount() . "\n";
    echo "DONE\n";
} elseif ($shape === 'ro_ok') {
    $u = new RUser("U001", "Alice", ['user', 'editor']);
    echo "before=$u\n";
    echo "uuid=" . $u->getUuid() . "\n";
    $ser = $u->__serialize();
    echo "serialized=" . json_encode($ser) . "\n";
    $u2 = new RUser("TEMP", "TEMP");
    $u2->__unserialize($ser);
    echo "after=$u2\n";
    echo "finalUuid=" . $u2->getUuid() . "\n";
    echo "countBase=" . RBase::getEntityCount() . " countUser=" . RUser::getEntityCount() . "\n";
    echo "DONE\n";
} elseif ($shape === 'fatal') {
    $b = new BUser("U001");
    echo "constructed=" . $b->getUuid() . "\n";
    $b->__unserialize(['uuid' => 'U002']);
    echo "unreached=" . $b->getUuid() . "\n";
    echo "DONE\n";
} elseif ($shape === 'priv_read' || $shape === 'priv_write' || $shape === 'prot_read'
        || $shape === 'type_inherit' || $shape === 'type_self' || $shape === 'dyn_ro'
        || $shape === 'class_const' || $shape === 'val_self' || $shape === 'val_dyn') {
    $show = static function (callable $f): void {
        try {
            $f();
            echo "NO_ERROR\n";
        } catch (Throwable $e) {
            echo get_class($e) . ": " . $e->getMessage() . "\n";
        }
    };
    $c = new MChild("U001");
    echo "obj=" . get_class($c) . " uuid=" . $c->uuid . "\n";
    if ($shape === 'class_const') {
        echo "lit=" . MChild::class . "\n";
        echo "var=" . $c::class . "\n";
        echo "scope=" . $c->scopeNames() . "\n";
    } elseif ($shape === 'priv_read') {
        $show(static function () use ($c): void { $x = $c->secret; echo isset($x) ? "read=$x" : "read=null"; });
    } elseif ($shape === 'priv_write') {
        $show(static function () use ($c): void { $c->secret = "X"; });
    } elseif ($shape === 'prot_read') {
        $show(static function () use ($c): void { $x = $c->limit; echo isset($x) ? "read=$x" : "read=null"; });
    } elseif ($shape === 'type_inherit') {
        $show(static function () use ($c): void { $c->total = "str"; });
    } elseif ($shape === 'type_self') {
        $show(static function () use ($c): void { $c->count = "str"; });
    } elseif ($shape === 'dyn_ro') {
        $show(static function () use ($c): void { $k = "uuid"; $c->$k = "X2"; });
    }
    if ($shape === 'val_self') {
        $show(static function () use ($c): void { $c->count = "str"; });
        echo "slot=" . var_export($c->count, true) . " type=" . gettype($c->count) . "\n";
    } elseif ($shape === 'val_dyn') {
        $show(static function () use ($c): void { $k = "uuid"; $c->$k = "X2"; });
        echo "slot=" . var_export($c->uuid, true) . " type=" . gettype($c->uuid) . "\n";
    }
    echo "DONE\n";
} else {
    echo "UNKNOWN_SHAPE\n";
}
