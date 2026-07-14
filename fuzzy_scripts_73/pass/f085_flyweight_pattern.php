<?php
// 享元模式：共享对象/内存优化
echo "=== Flyweight Pattern ===\n\n";

// 享元对象（内部状态共享）
class TreeType {
    public function __construct(
        public readonly string $name,
        public readonly string $color,
        public readonly string $texture,
        public readonly int $maxHeight
    ) {}

    public function draw(int $x, int $y, int $height): string {
        return sprintf("Drawing %s tree at (%d,%d) height=%dm color=%s",
            $this->name, $x, $y, $height, $this->color);
    }
}

// 享元工厂
class TreeFactory {
    private static array $types = [];

    public static function getTreeType(string $name, string $color, string $texture, int $maxHeight): TreeType {
        $key = "$name|$color|$texture|$maxHeight";
        if (!isset(self::$types[$key])) {
            self::$types[$key] = new TreeType($name, $color, $texture, $maxHeight);
            echo "  [Factory] Created new TreeType: $name\n";
        }
        return self::$types[$key];
    }

    public static function getTypeCount(): int { return count(self::$types); }
    public static function getTypes(): array { return self::$types; }
}

// 外部状态（不共享）
class Tree {
    private TreeType $type;
    public function __construct(
        int $x,
        int $y,
        int $height,
        string $name,
        string $color,
        string $texture,
        int $maxHeight
    ) {
        $this->type = TreeFactory::getTreeType($name, $color, $texture, $maxHeight);
        $this->x = $x;
        $this->y = $y;
        $this->height = $height;
    }

    public int $x;
    public int $y;
    public int $height;

    public function draw(): string {
        return $this->type->draw($this->x, $this->y, $this->height);
    }

    public function getType(): TreeType { return $this->type; }
}

// 森林
class Forest {
    private array $trees = [];

    public function plantTree(int $x, int $y, int $height, string $name, string $color, string $texture, int $maxHeight): void {
        $this->trees[] = new Tree($x, $y, $height, $name, $color, $texture, $maxHeight);
    }

    public function render(): array {
        return array_map(fn($tree) => $tree->draw(), $this->trees);
    }

    public function getTreeCount(): int { return count($this->trees); }
}

// === 测试 ===
echo "--- Planting Forest ---\n";
$forest = new Forest();

// 种植很多树，但只有少量类型
$treeConfigs = [
    ['Oak', 'green', 'rough', 30],
    ['Pine', 'dark_green', 'smooth', 25],
    ['Birch', 'light_green', 'peeling', 20],
    ['Maple', 'red_green', 'rough', 28],
];

$positions = [
    [10, 20, 15], [50, 60, 22], [100, 30, 18], [200, 150, 25],
    [15, 25, 12], [55, 65, 20], [105, 35, 16], [205, 155, 28],
    [10, 200, 14], [50, 250, 21], [100, 230, 17], [200, 350, 24],
    [12, 22, 16], [52, 62, 19], [102, 32, 15], [202, 152, 26],
];

foreach ($positions as $i => [$x, $y, $height]) {
    $config = $treeConfigs[$i % count($treeConfigs)];
    $forest->plantTree($x, $y, $height, $config[0], $config[1], $config[2], $config[3]);
}

echo "Trees planted: " . $forest->getTreeCount() . "\n";
echo "Unique types: " . TreeFactory::getTypeCount() . "\n";

echo "\n--- Rendering ---\n";
$rendered = $forest->render();
foreach (array_slice($rendered, 0, 5) as $line) {
    echo "  $line\n";
}
echo "  ... (" . count($rendered) . " total)\n";

echo "\n--- Shared Types ---\n";
foreach (TreeFactory::getTypes() as $key => $type) {
    $count = 0;
    foreach ($forest->render() as $line) {
        if (str_contains($line, $type->name)) $count++;
    }
    echo "  {$type->name} ({$type->color}): used $count times, shared=1 instance\n";
}

// === 字符享元 ===
echo "\n--- Character Flyweight ---\n";

class CharFlyweight {
    public function __construct(public readonly string $char) {}
    public function render(int $position, string $font = 'Arial', int $size = 12): string {
        return sprintf("'%s' at pos=%d font=%s size=%d", $this->char, $position, $font, $size);
    }
}

class CharFactory {
    private static array $pool = [];

    public static function get(string $char): CharFlyweight {
        if (!isset(self::$pool[$char])) {
            self::$pool[$char] = new CharFlyweight($char);
        }
        return self::$pool[$char];
    }

    public static function getPoolSize(): int { return count(self::$pool); }
}

$text = "Hello World";
echo "Text: '$text'\n";
$rendered = [];
foreach (str_split($text) as $pos => $char) {
    $flyweight = CharFactory::get($char);
    $rendered[] = $flyweight->render($pos);
}

foreach ($rendered as $line) {
    echo "  $line\n";
}

echo "Total chars: " . strlen($text) . "\n";
echo "Unique chars in pool: " . CharFactory::getPoolSize() . "\n";
echo "Memory saved: " . (strlen($text) - CharFactory::getPoolSize()) . " objects\n";

// === 格式化享元 ===
echo "\n--- Format Flyweight ---\n";

class FormatStyle {
    public function __construct(
        public readonly string $bold,
        public readonly string $italic,
        public readonly string $underline,
        public readonly string $color
    ) {}

    public function apply(string $text): string {
        $result = $text;
        if ($this->bold === 'yes') $result = "**$result**";
        if ($this->italic === 'yes') $result = "*$result*";
        if ($this->underline === 'yes') $result = "_{$result}_";
        if ($this->color !== 'none') $result = "[{$this->color}]{$result}[/{$this->color}]";
        return $result;
    }
}

class FormatFactory {
    private static array $pool = [];

    public static function get(string $bold, string $italic, string $underline, string $color): FormatStyle {
        $key = "$bold|$italic|$underline|$color";
        if (!isset(self::$pool[$key])) {
            self::$pool[$key] = new FormatStyle($bold, $italic, $underline, $color);
        }
        return self::$pool[$key];
    }

    public static function getPoolSize(): int { return count(self::$pool); }
}

$styles = [
    ['yes', 'no', 'no', 'red'],
    ['yes', 'no', 'no', 'red'],  // duplicate
    ['no', 'yes', 'no', 'blue'],
    ['yes', 'yes', 'yes', 'green'],
    ['no', 'no', 'no', 'none'],
    ['yes', 'no', 'no', 'red'],  // duplicate
];

foreach ($styles as [$bold, $italic, $underline, $color]) {
    $style = FormatFactory::get($bold, $italic, $underline, $color);
    echo "  " . $style->apply("text") . "\n";
}

echo "Total style requests: " . count($styles) . "\n";
echo "Unique styles in pool: " . FormatFactory::getPoolSize() . "\n";
