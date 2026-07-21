<?php
// 极度混搭: 桥接模式 + 形状+渲染器 + 跨维度组合 + 抽象与实现分离
echo "=== f039: Bridge + Shape + Renderer ===\n";

interface Renderer {
    public function renderCircle(float $x, float $y, float $r): string;
    public function renderRect(float $x, float $y, float $w, float $h): string;
    public function renderLine(float $x1, float $y1, float $x2, float $y2): string;
    public function renderText(float $x, float $y, string $text): string;
    public function getName(): string;
}

class SvgRenderer implements Renderer {
    public function renderCircle(float $x, float $y, float $r): string {
        return sprintf('<circle cx="%.1f" cy="%.1f" r="%.1f"/>', $x, $y, $r);
    }
    public function renderRect(float $x, float $y, float $w, float $h): string {
        return sprintf('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f"/>', $x, $y, $w, $h);
    }
    public function renderLine(float $x1, float $y1, float $x2, float $y2): string {
        return sprintf('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f"/>', $x1, $y1, $x2, $y2);
    }
    public function renderText(float $x, float $y, string $text): string {
        return sprintf('<text x="%.1f" y="%.1f">%s</text>', $x, $y, htmlspecialchars($text));
    }
    public function getName(): string { return 'SVG'; }
}

class AsciiRenderer implements Renderer {
    public function renderCircle(float $x, float $y, float $r): string {
        return sprintf('[O at (%.0f,%.0f) r=%.0f]', $x, $y, $r);
    }
    public function renderRect(float $x, float $y, float $w, float $h): string {
        return sprintf('[# at (%.0f,%.0f) %.0fx%.0f]', $x, $y, $w, $h);
    }
    public function renderLine(float $x1, float $y1, float $x2, float $y2): string {
        return sprintf('[- from (%.0f,%.0f) to (%.0f,%.0f)]', $x1, $y1, $x2, $y2);
    }
    public function renderText(float $x, float $y, string $text): string {
        return sprintf('[T:"%s" at (%.0f,%.0f)]', $text, $x, $y);
    }
    public function getName(): string { return 'ASCII'; }
}

class JsonRenderer implements Renderer {
    public function renderCircle(float $x, float $y, float $r): string {
        return json_encode(['type' => 'circle', 'x' => $x, 'y' => $y, 'r' => $r]);
    }
    public function renderRect(float $x, float $y, float $w, float $h): string {
        return json_encode(['type' => 'rect', 'x' => $x, 'y' => $y, 'w' => $w, 'h' => $h]);
    }
    public function renderLine(float $x1, float $y1, float $x2, float $y2): string {
        return json_encode(['type' => 'line', 'x1' => $x1, 'y1' => $y1, 'x2' => $x2, 'y2' => $y2]);
    }
    public function renderText(float $x, float $y, string $text): string {
        return json_encode(['type' => 'text', 'x' => $x, 'y' => $y, 'text' => $text]);
    }
    public function getName(): string { return 'JSON'; }
}

abstract class Shape {
    protected Renderer $renderer;

    public function __construct(Renderer $renderer) {
        $this->renderer = $renderer;
    }

    abstract public function draw(): string;
    public function getRendererName(): string { return $this->renderer->getName(); }
}

class Circle extends Shape {
    public function __construct(Renderer $r, private float $x, private float $y, private float $radius) {
        parent::__construct($r);
    }
    public function draw(): string { return $this->renderer->renderCircle($this->x, $this->y, $this->radius); }
}

class Rectangle extends Shape {
    public function __construct(Renderer $r, private float $x, private float $y, private float $w, private float $h) {
        parent::__construct($r);
    }
    public function draw(): string { return $this->renderer->renderRect($this->x, $this->y, $this->w, $this->h); }
}

class Line extends Shape {
    public function __construct(Renderer $r, private float $x1, private float $y1, private float $x2, private float $y2) {
        parent::__construct($r);
    }
    public function draw(): string { return $this->renderer->renderLine($this->x1, $this->y1, $this->x2, $this->y2); }
}

class TextShape extends Shape {
    public function __construct(Renderer $r, private float $x, private float $y, private string $text) {
        parent::__construct($r);
    }
    public function draw(): string { return $this->renderer->renderText($this->x, $this->y, $this->text); }
}

// 测试：不同形状 × 不同渲染器
$renderers = [new SvgRenderer(), new AsciiRenderer(), new JsonRenderer()];

foreach ($renderers as $renderer) {
    echo "--- {$renderer->getName()} Renderer ---\n";
    $shapes = [
        new Circle($renderer, 50, 50, 25),
        new Rectangle($renderer, 10, 10, 100, 50),
        new Line($renderer, 0, 0, 100, 100),
        new TextShape($renderer, 10, 20, 'Hello'),
    ];
    foreach ($shapes as $shape) {
        echo "  " . $shape->draw() . "\n";
    }
    echo "\n";
}

// 动态切换渲染器
echo "--- Dynamic Switch ---\n";
$circle = new Circle(new SvgRenderer(), 50, 50, 25);
echo "SVG: " . $circle->draw() . "\n";

echo "=== f039 Done ===\n";
