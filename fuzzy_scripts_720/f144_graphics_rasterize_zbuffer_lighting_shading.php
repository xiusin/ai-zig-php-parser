<?php
// 极度混搭: 图形渲染 + 光栅化 + Z-Buffer + 光照 + 着色
echo "=== f144: Graphics + Rasterize + ZBuffer + Lighting + Shading ===\n";

class Vec3 {
    public function __construct(public float $x, public float $y, public float $z) {}
    public function add(Vec3 $v): Vec3 { return new Vec3($this->x + $v->x, $this->y + $v->y, $this->z + $v->z); }
    public function sub(Vec3 $v): Vec3 { return new Vec3($this->x - $v->x, $this->y - $v->y, $this->z - $v->z); }
    public function mul(float $s): Vec3 { return new Vec3($this->x * $s, $this->y * $s, $this->z * $s); }
    public function dot(Vec3 $v): float { return $this->x * $v->x + $this->y * $v->y + $this->z * $v->z; }
    public function cross(Vec3 $v): Vec3 { return new Vec3($this->y * $v->z - $this->z * $v->y, $this->z * $v->x - $this->x * $v->z, $this->x * $v->y - $this->y * $v->x); }
    public function length(): float { return sqrt($this->x ** 2 + $this->y ** 2 + $this->z ** 2); }
    public function normalize(): Vec3 { $l = $this->length(); return $l > 0 ? new Vec3($this->x / $l, $this->y / $l, $this->z / $l) : new Vec3(0, 0, 0); }
    public function __toString(): string { return sprintf("(%.2f,%.2f,%.2f)", $this->x, $this->y, $this->z); }
}

class Color {
    public function __construct(public int $r, public int $g, public int $b) {}
    public static function black(): self { return new self(0, 0, 0); }
    public static function white(): self { return new self(255, 255, 255); }
    public static function red(): self { return new self(255, 0, 0); }
    public static function green(): self { return new self(0, 255, 0); }
    public static function blue(): self { return new self(0, 0, 255); }
    public function mul(float $s): self { return new self(min(255, (int)($this->r * $s)), min(255, (int)($this->g * $s)), min(255, (int)($this->b * $s))); }
    public function add(Color $c): self { return new self(min(255, $this->r + $c->r), min(255, $this->g + $c->g), min(255, $this->b + $c->b)); }
    public function toHex(): string { return sprintf("#%02X%02X%02X", $this->r, $this->g, $this->b); }
    public function __toString(): string { return $this->toHex(); }
}

class Triangle {
    public Vec3 $normal;
    public function __construct(public Vec3 $v0, public Vec3 $v1, public Vec3 $v2, public Color $color) {
        $this->normal = $this->computeNormal();
    }
    private function computeNormal(): Vec3 {
        return $v1->sub($v0)->cross($v2->sub($v0))->normalize();
    }
}

class Light {
    public function __construct(public Vec3 $position, public Color $color, public float $intensity = 1.0) {}
}

class Material {
    public function __construct(public Color $diffuse, public float $ambient = 0.1, public float $diffuseCoeff = 0.7, public float $specularCoeff = 0.3, public float $shininess = 32) {}
}

class ZBuffer {
    private array $buffer;
    private array $colorBuffer;

    public function __construct(public int $width, public int $height) {
        $this->buffer = array_fill(0, $height, array_fill(0, $width, INF));
        $this->colorBuffer = array_fill(0, $height, array_fill(0, $width, Color::black()));
    }

    public function setPixel(int $x, int $y, float $z, Color $color): bool {
        if ($x < 0 || $x >= $this->width || $y < 0 || $y >= $this->height) return false;
        if ($z < $this->buffer[$y][$x]) {
            $this->buffer[$y][$x] = $z;
            $this->colorBuffer[$y][$x] = $color;
            return true;
        }
        return false;
    }

    public function clear(): void {
        for ($y = 0; $y < $this->height; $y++) {
            for ($x = 0; $x < $this->width; $x++) {
                $this->buffer[$y][$x] = INF;
                $this->colorBuffer[$y][$x] = Color::black();
            }
        }
    }

    public function render(): string {
        $chars = ' .:-=+*#%@';
        $output = '';
        for ($y = 0; $y < $this->height; $y++) {
            for ($x = 0; $x < $this->width; $x++) {
                $c = $this->colorBuffer[$y][$x];
                $brightness = ($c->r + $c->g + $c->b) / 765;
                $idx = (int)($brightness * (strlen($chars) - 1));
                $output .= $chars[$idx];
            }
            $output .= "\n";
        }
        return $output;
    }

    public function renderColored(): array { return $this->colorBuffer; }
}

class Rasterizer {
    private ZBuffer $zbuffer;

    public function __construct(int $width, int $height) { $this->zbuffer = new ZBuffer($width, $height); }

    public function drawTriangle(Triangle $tri, Material $material, array $lights, Vec3 $camera): void {
        // 简化: 不做透视投影, 直接用屏幕坐标
        $minX = max(0, (int)min($tri->v0->x, $tri->v1->x, $tri->v2->x));
        $maxX = min($this->zbuffer->width - 1, (int)max($tri->v0->x, $tri->v1->x, $tri->v2->x));
        $minY = max(0, (int)min($tri->v0->y, $tri->v1->y, $tri->v2->y));
        $maxY = min($this->zbuffer->height - 1, (int)max($tri->v0->y, $tri->v1->y, $tri->v2->y));

        for ($y = $minY; $y <= $maxY; $y++) {
            for ($x = $minX; $x <= $maxX; $x++) {
                $px = $x + 0.5; $py = $y + 0.5;
                $bary = $this->barycentric($tri, new Vec3($px, $py, 0));
                if ($bary['a'] >= 0 && $bary['b'] >= 0 && $bary['c'] >= 0) {
                    $z = $tri->v0->z * $bary['a'] + $tri->v1->z * $bary['b'] + $tri->v2->z * $bary['c'];
                    $color = $this->shade($tri, $material, $lights, $camera, new Vec3($px, $py, $z));
                    $this->zbuffer->setPixel($x, $y, $z, $color);
                }
            }
        }
    }

    private function barycentric(Triangle $tri, Vec3 $p): array {
        $v0 = $tri->v1->sub($tri->v0); $v1 = $tri->v2->sub($tri->v0); $v2 = $p->sub($tri->v0);
        $d00 = $v0->dot($v0); $d01 = $v0->dot($v1); $d11 = $v1->dot($v1); $d20 = $v2->dot($v0); $d21 = $v2->dot($v1);
        $denom = $d00 * $d11 - $d01 * $d01;
        if (abs($denom) < 1e-10) return ['a' => 0, 'b' => 0, 'c' => 0];
        $v = ($d11 * $d20 - $d01 * $d21) / $denom;
        $w = ($d00 * $d21 - $d01 * $d20) / $denom;
        $u = 1 - $v - $w;
        return ['a' => $u, 'b' => $v, 'c' => $w];
    }

    private function shade(Triangle $tri, Material $mat, array $lights, Vec3 $camera, Vec3 $point): Color {
        $ambient = $mat->diffuse->mul($mat->ambient);
        $normal = $tri->normal;
        $viewDir = $camera->sub($point)->normalize();
        $result = $ambient;

        foreach ($lights as $light) {
            $lightDir = $light->position->sub($point)->normalize();
            $diffuseFactor = max(0, $normal->dot($lightDir));
            $diffuse = $mat->diffuse->mul($diffuseFactor * $mat->diffuseCoeff * $light->intensity);
            // Specular (Phong)
            $reflectDir = $normal->mul(2 * $normal->dot($lightDir))->sub($lightDir)->normalize();
            $specularFactor = pow(max(0, $viewDir->dot($reflectDir)), $mat->shininess);
            $specular = $light->color->mul($specularFactor * $mat->specularCoeff * $light->intensity);
            $result = $result->add($diffuse)->add($specular);
        }
        return $result;
    }

    public function getBuffer(): ZBuffer { return $this->zbuffer; }
}

class Mesh {
    public array $triangles = [];
    public function addTriangle(Triangle $t): self { $this->triangles[] = $t; return $this; }
    public static function cube(float $size, Color $color): self {
        $s = $size / 2;
        $mesh = new self();
        $verts = [
            new Vec3(-$s, -$s, -$s), new Vec3($s, -$s, -$s), new Vec3($s, $s, -$s), new Vec3(-$s, $s, -$s),
            new Vec3(-$s, -$s, $s), new Vec3($s, -$s, $s), new Vec3($s, $s, $s), new Vec3(-$s, $s, $s),
        ];
        $faces = [[0,1,2],[0,2,3], [4,6,5],[4,7,6], [0,4,5],[0,5,1], [2,6,7],[2,7,3], [0,3,7],[0,7,4], [1,5,6],[1,6,2]];
        foreach ($faces as $f) $mesh->addTriangle(new Triangle($verts[$f[0]], $verts[$f[1]], $verts[$f[2]], $color));
        return $mesh;
    }
}

// 测试
echo "--- Basic Graphics Setup ---\n";
$rasterizer = new Rasterizer(60, 20);
echo "Canvas: 60x20\n";

echo "\n--- Render Simple Triangle ---\n";
$rasterizer->getBuffer()->clear();
$tri = new Triangle(
    new Vec3(10, 2, 5), new Vec3(50, 2, 5), new Vec3(30, 18, 5),
    Color::white()
);
$mat = new Material(Color::white(), 0.2, 0.6, 0.2, 16);
$lights = [new Light(new Vec3(30, 20, 10), Color::white(), 1.0)];
$camera = new Vec3(30, 10, 20);
$rasterizer->drawTriangle($tri, $mat, $lights, $camera);
echo $rasterizer->getBuffer()->render();

echo "\n--- Render Cube ---\n";
$rasterizer2 = new Rasterizer(60, 20);
$rasterizer2->getBuffer()->clear();
$cube = Mesh::cube(15, Color::white());
$mat2 = new Material(Color::white(), 0.15, 0.7, 0.15, 32);
$lights2 = [new Light(new Vec3(30, 20, 15), Color::white(), 1.0)];
$camera2 = new Vec3(30, 10, 25);
// 平移立方体到画布中心
foreach ($cube->triangles as $t) {
    $t2 = new Triangle(
        new Vec3($t->v0->x + 30, $t->v0->y + 10, $t->v0->z + 10),
        new Vec3($t->v1->x + 30, $t->v1->y + 10, $t->v1->z + 10),
        new Vec3($t->v2->x + 30, $t->v2->y + 10, $t->v2->z + 10),
        $t->color
    );
    $rasterizer2->drawTriangle($t2, $mat2, $lights2, $camera2);
}
echo $rasterizer2->getBuffer()->render();

echo "\n--- Lighting Effects ---\n";
$rasterizer3 = new Rasterizer(60, 20);
$rasterizer3->getBuffer()->clear();
$triangles = [
    new Triangle(new Vec3(5, 5, 5), new Vec3(25, 5, 5), new Vec3(15, 18, 5), Color::red()),
    new Triangle(new Vec3(35, 5, 5), new Vec3(55, 5, 5), new Vec3(45, 18, 5), Color::green()),
];
$mat3 = new Material(Color::white(), 0.1, 0.8, 0.1, 8);
$lightLeft = [new Light(new Vec3(0, 10, 10), Color::white(), 0.8)];
$lightRight = [new Light(new Vec3(60, 10, 10), Color::white(), 0.8)];
$rasterizer3->drawTriangle($triangles[0], $mat3, $lightLeft, new Vec3(15, 10, 20));
$rasterizer3->drawTriangle($triangles[1], $mat3, $lightRight, new Vec3(45, 10, 20));
echo $rasterizer3->getBuffer()->render();

echo "\n--- Multiple Triangles with Z-Buffer ---\n";
$rasterizer4 = new Rasterizer(60, 20);
$rasterizer4->getBuffer()->clear();
$overlapping = [
    new Triangle(new Vec3(10, 5, 8), new Vec3(40, 5, 8), new Vec3(25, 18, 8), Color::red()),
    new Triangle(new Vec3(20, 3, 5), new Vec3(50, 3, 5), new Vec3(35, 18, 5), Color::green()),
    new Triangle(new Vec3(15, 7, 3), new Vec3(45, 7, 3), new Vec3(30, 18, 3), Color::blue()),
];
$mat4 = new Material(Color::white(), 0.2, 0.6, 0.2, 16);
$light4 = [new Light(new Vec3(30, 20, 15), Color::white(), 1.0)];
foreach ($overlapping as $t) $rasterizer4->drawTriangle($t, $mat4, $light4, new Vec3(30, 10, 20));
echo $rasterizer4->getBuffer()->render();

echo "\n--- Color Information ---\n";
$buffer = $rasterizer4->getBuffer();
$coloredPixels = 0;
$colorSum = ['r' => 0, 'g' => 0, 'b' => 0];
for ($y = 0; $y < 20; $y++) {
    for ($x = 0; $x < 60; $x++) {
        $c = $buffer->colorBuffer[$y][$x];
        if ($c->r + $c->g + $c->b > 0) {
            $coloredPixels++;
            $colorSum['r'] += $c->r; $colorSum['g'] += $c->g; $colorSum['b'] += $c->b;
        }
    }
}
echo "Colored pixels: $coloredPixels\n";
echo "Average color: R=" . (int)($colorSum['r'] / max(1, $coloredPixels)) . " G=" . (int)($colorSum['g'] / max(1, $coloredPixels)) . " B=" . (int)($colorSum['b'] / max(1, $coloredPixels)) . "\n";

echo "=== f144 Done ===\n";
