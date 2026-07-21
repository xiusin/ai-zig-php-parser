<?php
// 极度混搭: 物理引擎简化 + 碰撞检测 + 刚体 + 重力 + 弹性碰撞
echo "=== f092: Physics Engine + Collision + RigidBody ===\n";

class Vector2 {
    public function __construct(public float $x = 0, public float $y = 0) {}
    public function add(self $v): self { return new self($this->x + $v->x, $this->y + $v->y); }
    public function sub(self $v): self { return new self($this->x - $v->x, $this->y - $v->y); }
    public function scale(float $s): self { return new self($this->x * $s, $this->y * $s); }
    public function dot(self $v): float { return $this->x * $v->x + $this->y * $v->y; }
    public function length(): float { return sqrt($this->x ** 2 + $this->y ** 2); }
    public function normalize(): self { $l = $this->length(); return $l > 0 ? $this->scale(1/$l) : new self(); }
    public function __toString(): string { return "({$this->x},{$this->y})"; }
}

class RigidBody {
    public Vector2 $velocity;
    public Vector2 $force;
    public float $mass;
    public float $restitution = 0.8;

    public function __construct(
        public Vector2 $position,
        public float $radius,
        float $mass = 1.0
    ) {
        $this->velocity = new Vector2();
        $this->force = new Vector2();
        $this->mass = $mass;
    }

    public function applyForce(Vector2 $f): void { $this->force = $this->force->add($f); }
    public function applyImpulse(Vector2 $impulse): void { $this->velocity = $this->velocity->add($impulse->scale(1/$this->mass)); }
}

class PhysicsWorld {
    private array $bodies = [];
    private Vector2 $gravity;
    private float $dt;
    private array $collisions = [];

    public function __construct(float $dt = 0.016) {
        $this->gravity = new Vector2(0, -9.81);
        $this->dt = $dt;
    }

    public function addBody(RigidBody $body): void { $this->bodies[] = $body; }

    public function step(): array {
        $this->collisions = [];
        // 应用重力
        foreach ($this->bodies as $body) {
            $body->applyForce($this->gravity->scale($body->mass));
        }
        // 积分
        foreach ($this->bodies as $body) {
            $accel = $body->force->scale(1 / $body->mass);
            $body->velocity = $body->velocity->add($accel->scale($this->dt));
            $body->position = $body->position->add($body->velocity->scale($this->dt));
            $body->force = new Vector2();
        }
        // 碰撞检测
        $this->detectCollisions();
        // 地面碰撞
        foreach ($this->bodies as $body) {
            if ($body->position->y - $body->radius < 0) {
                $body->position->y = $body->radius;
                $body->velocity->y = -$body->velocity->y * $body->restitution;
                $this->collisions[] = ['type' => 'ground', 'body' => $body];
            }
        }
        return $this->collisions;
    }

    private function detectCollisions(): void {
        $n = count($this->bodies);
        for ($i = 0; $i < $n; $i++) {
            for ($j = $i + 1; $j < $n; $j++) {
                $a = $this->bodies[$i]; $b = $this->bodies[$j];
                $dist = $a->position->sub($b->position)->length();
                $minDist = $a->radius + $b->radius;
                if ($dist < $minDist) {
                    $this->resolveCollision($a, $b, $dist, $minDist);
                    $this->collisions[] = ['type' => 'body', 'a' => $a, 'b' => $b];
                }
            }
        }
    }

    private function resolveCollision(RigidBody $a, RigidBody $b, float $dist, float $minDist): void {
        if ($dist < 0.001) return;
        $normal = $a->position->sub($b->position)->scale(1 / $dist);
        // 分离
        $overlap = $minDist - $dist;
        $totalMass = $a->mass + $b->mass;
        $a->position = $a->position->add($normal->scale($overlap * ($b->mass / $totalMass)));
        $b->position = $b->position->sub($normal->scale($overlap * ($a->mass / $totalMass)));
        // 速度
        $relVel = $a->velocity->sub($b->velocity);
        $velAlongNormal = $relVel->dot($normal);
        if ($velAlongNormal > 0) return;
        $e = min($a->restitution, $b->restitution);
        $j = -(1 + $e) * $velAlongNormal / (1/$a->mass + 1/$b->mass);
        $impulse = $normal->scale($j);
        $a->velocity = $a->velocity->add($impulse->scale(1/$a->mass));
        $b->velocity = $b->velocity->sub($impulse->scale(1/$b->mass));
    }

    public function getBodies(): array { return $this->bodies; }
}

// 测试
echo "--- Free Fall ---\n";
$world = new PhysicsWorld(0.1);
$ball = new RigidBody(new Vector2(0, 10), 0.5, 1.0);
$world->addBody($ball);
echo "Initial: pos=$ball->position vel=$ball->velocity\n";
for ($i = 0; $i < 30; $i++) {
    $world->step();
    echo "t=" . number_format(($i+1)*0.1, 1) . " pos=$ball->position vel=$ball->velocity\n";
}

echo "\n--- Projectile Motion ---\n";
$world2 = new PhysicsWorld(0.1);
$projectile = new RigidBody(new Vector2(0, 0), 0.3, 2.0);
$projectile->velocity = new Vector2(10, 15);
$world2->addBody($projectile);
echo "Trajectory:\n";
for ($i = 0; $i < 35; $i++) {
    $world2->step();
    if ($projectile->position->y >= 0) {
        echo "  t=" . number_format(($i+1)*0.1, 1) . " pos=$projectile->position\n";
    }
}

echo "\n--- Elastic Collision ---\n";
$world3 = new PhysicsWorld(0.01);
$world3->gravity = new Vector2(0, 0); // 无重力
$ball1 = new RigidBody(new Vector2(0, 0), 1.0, 2.0);
$ball1->velocity = new Vector2(5, 0);
$ball2 = new RigidBody(new Vector2(5, 0), 1.0, 2.0);
$ball2->velocity = new Vector2(-2, 0);
$world3->addBody($ball1);
$world3->addBody($ball2);

echo "Before: ball1 vel=$ball1->velocity, ball2 vel=$ball2->velocity\n";
for ($i = 0; $i < 100; $i++) {
    $collisions = $world3->step();
    if (!empty($collisions)) {
        echo "Collision at t=" . number_format(($i+1)*0.01, 2) . "\n";
        echo "  ball1 pos=$ball1->position vel=$ball1->velocity\n";
        echo "  ball2 pos=$ball2->position vel=$ball2->velocity\n";
    }
}
echo "After: ball1 vel=$ball1->velocity, ball2 vel=$ball2->velocity\n";

echo "\n--- Multi-body ---\n";
$world4 = new PhysicsWorld(0.05);
$world4->gravity = new Vector2(0, -5);
$balls = [];
for ($i = 0; $i < 4; $i++) {
    $b = new RigidBody(new Vector2($i * 2, 10 - $i), 0.5, 1.0 + $i * 0.5);
    $b->velocity = new Vector2($i, 0);
    $world4->addBody($b);
    $balls[] = $b;
}
$totalCollisions = 0;
for ($i = 0; $i < 50; $i++) {
    $collisions = $world4->step();
    $totalCollisions += count($collisions);
}
echo "After 50 steps, $totalCollisions collisions\n";
foreach ($balls as $i => $b) echo "  Ball $i: pos=$b->position vel=$b->velocity\n";

echo "=== f092 Done ===\n";
