<?php
// 极度混搭: 物理引擎 + 刚体 + 碰撞检测 + 重力 + 弹簧
echo "=== f131: Physics + RigidBody + Collision + Gravity + Spring ===\n";

class Vector2 {
    public function __construct(public float $x, public float $y) {}
    public function add(Vector2 $v): Vector2 { return new Vector2($this->x + $v->x, $this->y + $v->y); }
    public function subtract(Vector2 $v): Vector2 { return new Vector2($this->x - $v->x, $this->y - $v->y); }
    public function multiply(float $s): Vector2 { return new Vector2($this->x * $s, $this->y * $s); }
    public function dot(Vector2 $v): float { return $this->x * $v->x + $this->y * $v->y; }
    public function length(): float { return sqrt($this->x * $this->x + $this->y * $this->y); }
    public function normalize(): Vector2 { $l = $this->length(); return $l > 0 ? new Vector2($this->x / $l, $this->y / $l) : new Vector2(0, 0); }
    public function perpendicular(): Vector2 { return new Vector2(-$this->y, $this->x); }
    public function __toString(): string { return sprintf("(%.2f,%.2f)", $this->x, $this->y); }
}

class RigidBody {
    public Vector2 $velocity;
    public Vector2 $force;
    public float $angularVelocity = 0;
    public float $torque = 0;
    public bool $isStatic = false;

    public function __construct(
        public int $id,
        public Vector2 $position,
        public float $mass = 1.0,
        public float $radius = 1.0,
        public float $restitution = 0.8
    ) {
        $this->velocity = new Vector2(0, 0);
        $this->force = new Vector2(0, 0);
    }

    public function applyForce(Vector2 $f): void { if (!$this->isStatic) $this->force = $this->force->add($f); }
    public function applyImpulse(Vector2 $impulse): void { if (!$this->isStatic) $this->velocity = $this->velocity->add($impulse->multiply(1 / $this->mass)); }
    public function applyGravity(Vector2 $g): void { $this->applyForce($g->multiply($this->mass)); }

    public function integrate(float $dt): void {
        if ($this->isStatic) return;
        $acceleration = $this->force->multiply(1 / $this->mass);
        $this->velocity = $this->velocity->add($acceleration->multiply($dt));
        $this->position = $this->position->add($this->velocity->multiply($dt));
        $this->force = new Vector2(0, 0);
    }
}

class PhysicsWorld {
    private array $bodies = [];
    private Vector2 $gravity;
    private array $constraints = [];
    private array $collisions = [];

    public function __construct(float $gx = 0, float $gy = -9.81) { $this->gravity = new Vector2($gx, $gy); }

    public function addBody(RigidBody $body): void { $this->bodies[$body->id] = $body; }
    public function removeBody(int $id): void { unset($this->bodies[$id]); }
    public function getBodies(): array { return $this->bodies; }

    public function step(float $dt): array {
        $this->collisions = [];
        // 应用重力
        foreach ($this->bodies as $body) $body->applyGravity($this->gravity);
        // 应用约束
        foreach ($this->constraints as $constraint) $constraint->apply($dt);
        // 积分
        foreach ($this->bodies as $body) $body->integrate($dt);
        // 碰撞检测和响应
        $this->detectCollisions();
        $this->resolveCollisions();
        return $this->collisions;
    }

    private function detectCollisions(): void {
        $bodies = array_values($this->bodies);
        for ($i = 0; $i < count($bodies); $i++) {
            for ($j = $i + 1; $j < count($bodies); $j++) {
                $a = $bodies[$i]; $b = $bodies[$j];
                $dist = $a->position->subtract($b->position)->length();
                $minDist = $a->radius + $b->radius;
                if ($dist < $minDist) {
                    $this->collisions[] = ['a' => $a->id, 'b' => $b->id, 'penetration' => $minDist - $dist, 'normal' => $a->position->subtract($b->position)->normalize()];
                }
            }
        }
    }

    private function resolveCollisions(): void {
        foreach ($this->collisions as $col) {
            $a = $this->bodies[$col['a']]; $b = $this->bodies[$col['b']];
            $normal = $col['normal'];
            $penetration = $col['penetration'];

            // 位置修正
            if (!$a->isStatic && !$b->isStatic) {
                $correction = $normal->multiply($penetration / 2);
                $a->position = $a->position->add($correction);
                $b->position = $b->position->subtract($correction);
            } elseif (!$a->isStatic) {
                $a->position = $a->position->add($normal->multiply($penetration));
            } elseif (!$b->isStatic) {
                $b->position = $b->position->subtract($normal->multiply($penetration));
            }

            // 速度修正 (弹性碰撞)
            $relVel = $a->velocity->subtract($b->velocity);
            $velAlongNormal = $relVel->dot($normal);
            if ($velAlongNormal > 0) continue;

            $e = min($a->restitution, $b->restitution);
            $invMassA = $a->isStatic ? 0 : 1 / $a->mass;
            $invMassB = $b->isStatic ? 0 : 1 / $b->mass;
            $j = -(1 + $e) * $velAlongNormal / ($invMassA + $invMassB);
            $impulse = $normal->multiply($j);
            if (!$a->isStatic) $a->applyImpulse($impulse);
            if (!$b->isStatic) $b->applyImpulse($impulse->multiply(-1));
        }
    }

    public function addBoundary(float $width, float $height): void {
        $floor = new RigidBody(9000, new Vector2($width / 2, 0), 0, $width / 2, 0.5);
        $floor->isStatic = true; $this->addBody($floor);
        $ceil = new RigidBody(9001, new Vector2($width / 2, $height), 0, $width / 2, 0.5);
        $ceil->isStatic = true; $this->addBody($ceil);
        $left = new RigidBody(9002, new Vector2(0, $height / 2), 0, $height / 2, 0.5);
        $left->isStatic = true; $this->addBody($left);
        $right = new RigidBody(9003, new Vector2($width, $height / 2), 0, $height / 2, 0.5);
        $right->isStatic = true; $this->addBody($right);
    }

    public function addConstraint(Constraint $c): void { $this->constraints[] = $c; }
}

abstract class Constraint {
    abstract public function apply(float $dt): void;
}

class SpringConstraint extends Constraint {
    public function __construct(private RigidBody $a, private RigidBody $b, private float $restLength, private float $stiffness = 50) {}

    public function apply(float $dt): void {
        $diff = $this->b->position->subtract($this->a->position);
        $dist = $diff->length();
        if ($dist < 0.001) return;
        $displacement = $dist - $this->restLength;
        $force = $diff->normalize()->multiply($displacement * $this->stiffness);
        $this->a->applyForce($force);
        $this->b->applyForce($force->multiply(-1));
    }
}

class DistanceConstraint extends Constraint {
    public function __construct(private RigidBody $a, private RigidBody $b, private float $distance) {}

    public function apply(float $dt): void {
        $diff = $this->b->position->subtract($this->a->position);
        $dist = $diff->length();
        if ($dist < 0.001) return;
        $error = ($dist - $this->distance) / $dist;
        $correction = $diff->multiply(0.5 * $error);
        if (!$this->a->isStatic) $this->a->position = $this->a->position->add($correction);
        if (!$this->b->isStatic) $this->b->position = $this->b->position->subtract($correction);
    }
}

// 测试
echo "--- Free Fall ---\n";
$world = new PhysicsWorld(0, -9.81);
$ball = new RigidBody(1, new Vector2(50, 100), 1.0, 5);
$world->addBody($ball);

echo "t=0: pos={$ball->position} vel={$ball->velocity}\n";
for ($t = 1; $t <= 5; $t++) {
    $world->step(0.1);
    if ($t % 1 === 0) echo "t=$t: pos={$ball->position} vel={$ball->velocity}\n";
    for ($i = 0; $i < 9; $i++) $world->step(0.1);
}

echo "\n--- Collision (two balls) ---\n";
$world2 = new PhysicsWorld(0, 0);
$a = new RigidBody(1, new Vector2(0, 0), 1.0, 1, 0.9);
$b = new RigidBody(2, new Vector2(5, 0), 1.0, 1, 0.9);
$a->velocity = new Vector2(3, 0);
$b->velocity = new Vector2(-2, 0);
$world2->addBody($a);
$world2->addBody($b);

for ($step = 0; $step < 20; $step++) {
    $collisions = $world2->step(0.1);
    if (!empty($collisions)) {
        echo "Step $step: COLLISION! a={$a->position} v={$a->velocity}  b={$b->position} v={$b->velocity}\n";
    }
}
echo "Final: a={$a->position} v={$a->velocity}  b={$b->position} v={$b->velocity}\n";
$totalMomentum = $a->velocity->multiply($a->mass)->add($b->velocity->multiply($b->mass));
echo "Total momentum: {$totalMomentum} (conserved=" . var_export(abs($totalMomentum->x - 1) < 0.1, true) . ")\n";

echo "\n--- Ball Drop with Floor ---\n";
$world3 = new PhysicsWorld(0, -9.81);
$world3->addBoundary(100, 100);
$ball3 = new RigidBody(1, new Vector2(50, 90), 1.0, 5, 0.7);
$world3->addBody($ball3);

echo "Ball drop simulation:\n";
for ($step = 0; $step < 50; $step++) {
    $collisions = $world3->step(0.1);
    if (!empty($collisions) && $step % 5 === 0) {
        echo "  Step $step: BOUNCE! pos={$ball3->position} vel_y=" . number_format($ball3->velocity->y, 2) . "\n";
    }
}
echo "Final: pos={$ball3->position} vel={$ball3->velocity}\n";

echo "\n--- Spring System ---\n";
$world4 = new PhysicsWorld(0, -2);
$anchor = new RigidBody(0, new Vector2(50, 100), 0, 1, 0);
$anchor->isStatic = true;
$weight = new RigidBody(1, new Vector2(50, 70), 1.0, 3, 0.3);
$world4->addBody($anchor);
$world4->addBody($weight);
$world4->addConstraint(new SpringConstraint($anchor, $weight, 20, 30));

echo "Spring oscillation:\n";
for ($step = 0; $step < 30; $step++) {
    $world4->step(0.1);
    if ($step % 5 === 0) {
        $dist = $anchor->position->subtract($weight->position)->length();
        echo "  Step $step: dist=" . number_format($dist, 2) . " pos={$weight->position}\n";
    }
}

echo "\n--- Multi-body Simulation ---\n";
$world5 = new PhysicsWorld(0, -5);
for ($i = 0; $i < 5; $i++) {
    $body = new RigidBody($i + 1, new Vector2(20 + $i * 15, 80 + $i * 3), 1.0, 4, 0.6);
    $body->velocity = new Vector2(mt_rand(-5, 5) / 10, 0);
    $world5->addBody($body);
}

echo "5 bodies simulation:\n";
for ($step = 0; $step < 20; $step++) {
    $collisions = $world5->step(0.1);
    if (!empty($collisions) && $step % 5 === 0) {
        echo "  Step $step: " . count($collisions) . " collisions\n";
    }
}
echo "Final positions:\n";
foreach ($world5->getBodies() as $body) {
    if ($body->id < 100) echo "  Body {$body->id}: {$body->position} vel={$body->velocity}\n";
}

echo "=== f131 Done ===\n";
