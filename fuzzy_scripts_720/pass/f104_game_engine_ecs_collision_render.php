<?php
// 极度混搭: 游戏引擎简化 + ECS架构 + 碰撞 + 渲染
echo "=== f104: Game Engine + ECS + Collision + Render ===\n";

class Entity {
    public array $components = [];
    public function __construct(public int $id) {}
    public function addComponent(string $type, object $comp): self { $this->components[$type] = $comp; return $this; }
    public function getComponent(string $type): ?object { return $this->components[$type] ?? null; }
    public function hasComponent(string $type): bool { return isset($this->components[$type]); }
}

class Position { public function __construct(public float $x, public float $y) {} }
class Velocity { public function __construct(public float $vx, public float $vy) {} }
class Health { public function __construct(public int $current, public int $max) {} }
class Collider { public function __construct(public float $radius) {} }
class Renderable { public function __construct(public string $sprite, public string $color = '#fff') {} }
class Tag { public function __construct(public string $name) {} }

class ECSWorld {
    private array $entities = [];
    private int $nextId = 1;
    private array $systems = [];

    public function createEntity(): Entity {
        $e = new Entity($this->nextId++);
        $this->entities[$e->id] = $e;
        return $e;
    }

    public function removeEntity(int $id): void { unset($this->entities[$id]); }

    public function addSystem(string $name, callable $system): void { $this->systems[$name] = $system; }

    public function getEntitiesWith(string ...$componentTypes): array {
        return array_filter($this->entities, fn($e) => array_reduce($componentTypes, fn($carry, $t) => $carry && $e->hasComponent($t), true));
    }

    public function update(float $dt): array {
        $events = [];
        foreach ($this->systems as $name => $system) {
            $events = array_merge($events, $system($this, $dt));
        }
        return $events;
    }

    public function getEntityCount(): int { return count($this->entities); }
    public function getEntities(): array { return $this->entities; }
}

class GameSystems {
    public static function movementSystem(ECSWorld $world, float $dt): array {
        $events = [];
        foreach ($world->getEntitiesWith(Position::class, Velocity::class) as $entity) {
            $pos = $entity->getComponent(Position::class);
            $vel = $entity->getComponent(Velocity::class);
            $oldX = $pos->x; $oldY = $pos->y;
            $pos->x += $vel->vx * $dt;
            $pos->y += $vel->vy * $dt;
            if ($pos->x != $oldX || $pos->y != $oldY) {
                $events[] = ['type' => 'moved', 'entity' => $entity->id, 'from' => [$oldX, $oldY], 'to' => [$pos->x, $pos->y]];
            }
        }
        return $events;
    }

    public static function collisionSystem(ECSWorld $world, float $dt): array {
        $events = [];
        $entities = array_values($world->getEntitiesWith(Position::class, Collider::class));
        $n = count($entities);
        for ($i = 0; $i < $n; $i++) {
            for ($j = $i + 1; $j < $n; $j++) {
                $a = $entities[$i]; $b = $entities[$j];
                $pa = $a->getComponent(Position::class); $pb = $b->getComponent(Position::class);
                $ca = $a->getComponent(Collider::class); $cb = $b->getComponent(Collider::class);
                $dist = sqrt(($pa->x - $pb->x) ** 2 + ($pa->y - $pb->y) ** 2);
                if ($dist < $ca->radius + $cb->radius) {
                    $events[] = ['type' => 'collision', 'a' => $a->id, 'b' => $b->id, 'dist' => round($dist, 2)];
                }
            }
        }
        return $events;
    }

    public static function healthSystem(ECSWorld $world, float $dt): array {
        $events = [];
        foreach ($world->getEntitiesWith(Health::class) as $entity) {
            $health = $entity->getComponent(Health::class);
            if ($health->current <= 0) {
                $events[] = ['type' => 'death', 'entity' => $entity->id];
                $world->removeEntity($entity->id);
            }
        }
        return $events;
    }

    public static function boundarySystem(ECSWorld $world, float $dt): array {
        $events = [];
        $width = 800; $height = 600;
        foreach ($world->getEntitiesWith(Position::class, Velocity::class) as $entity) {
            $pos = $entity->getComponent(Position::class);
            $vel = $entity->getComponent(Velocity::class);
            if ($pos->x < 0) { $pos->x = 0; $vel->vx = abs($vel->vx); $events[] = ['type' => 'bounce', 'entity' => $entity->id, 'wall' => 'left']; }
            if ($pos->x > $width) { $pos->x = $width; $vel->vx = -abs($vel->vx); $events[] = ['type' => 'bounce', 'entity' => $entity->id, 'wall' => 'right']; }
            if ($pos->y < 0) { $pos->y = 0; $vel->vy = abs($vel->vy); $events[] = ['type' => 'bounce', 'entity' => $entity->id, 'wall' => 'top']; }
            if ($pos->y > $height) { $pos->y = $height; $vel->vy = -abs($vel->vy); $events[] = ['type' => 'bounce', 'entity' => $entity->id, 'wall' => 'bottom']; }
        }
        return $events;
    }
}

class GameRenderer {
    public static function render(ECSWorld $world): string {
        $grid = array_fill(0, 12, array_fill(0, 16, '.'));
        foreach ($world->getEntitiesWith(Position::class, Renderable::class) as $entity) {
            $pos = $entity->getComponent(Position::class);
            $rend = $entity->getComponent(Renderable::class);
            $gx = (int)($pos->x / 50); $gy = (int)($pos->y / 50);
            if ($gx >= 0 && $gx < 16 && $gy >= 0 && $gy < 12) {
                $grid[$gy][$gx] = $rend->sprite[0];
            }
        }
        $output = '';
        foreach ($grid as $row) $output .= implode('', $row) . "\n";
        return $output;
    }
}

// 测试
echo "--- Setup Game World ---\n";
$world = new ECSWorld();
$world->addSystem('movement', [GameSystems::class, 'movementSystem']);
$world->addSystem('collision', [GameSystems::class, 'collisionSystem']);
$world->addSystem('boundary', [GameSystems::class, 'boundarySystem']);
$world->addSystem('health', [GameSystems::class, 'healthSystem']);

// 创建玩家
$player = $world->createEntity();
$player->addComponent(Position::class, new Position(100, 300))
       ->addComponent(Velocity::class, new Velocity(50, 0))
       ->addComponent(Health::class, new Health(100, 100))
       ->addComponent(Collider::class, new Collider(20))
       ->addComponent(Renderable::class, new Renderable('Player', '#0f0'));

// 创建敌人
$enemy1 = $world->createEntity();
$enemy1->addComponent(Position::class, new Position(400, 300))
       ->addComponent(Velocity::class, new Velocity(-30, 10))
       ->addComponent(Health::class, new Health(50, 50))
       ->addComponent(Collider::class, new Collider(15))
       ->addComponent(Renderable::class, new Renderable('Enemy', '#f00'));

$enemy2 = $world->createEntity();
$enemy2->addComponent(Position::class, new Position(600, 200))
       ->addComponent(Velocity::class, new Velocity(-40, -5))
       ->addComponent(Health::class, new Health(30, 30))
       ->addComponent(Collider::class, new Collider(10))
       ->addComponent(Renderable::class, new Renderable('Enemy', '#f00'));

// 创建墙壁（静态）
$wall = $world->createEntity();
$wall->addComponent(Position::class, new Position(300, 400))
     ->addComponent(Collider::class, new Collider(30))
     ->addComponent(Renderable::class, new Renderable('Wall', '#888'));

echo "Entities: " . $world->getEntityCount() . "\n";

echo "\n--- Initial Render ---\n";
echo GameRenderer::render($world);

echo "\n--- Game Loop (5 frames) ---\n";
for ($frame = 1; $frame <= 5; $frame++) {
    $events = $world->update(1.0);
    echo "\nFrame $frame:\n";
    foreach ($events as $e) {
        echo "  " . json_encode($e) . "\n";
    }
}

echo "\n--- Render After 5 Frames ---\n";
echo GameRenderer::render($world);

echo "\n--- Combat Simulation ---\n";
// 给敌人造成伤害
$enemy1->getComponent(Health::class)->current = 0;
$events = $world->update(0.1);
echo "After killing enemy1:\n";
foreach ($events as $e) echo "  " . json_encode($e) . "\n";
echo "Entities remaining: " . $world->getEntityCount() . "\n";

echo "\n--- Entity States ---\n";
foreach ($world->getEntities() as $entity) {
    $pos = $entity->getComponent(Position::class);
    $health = $entity->getComponent(Health::class);
    $tag = $entity->getComponent(Renderable::class);
    echo "  Entity {$entity->id}: pos=({$pos->x},{$pos->y})" . ($health ? " hp={$health->current}/{$health->max}" : "") . " sprite=" . ($tag?->sprite ?? 'none') . "\n";
}

echo "=== f104 Done ===\n";
