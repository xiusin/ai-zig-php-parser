<?php
// PHP 8.x 特性：match 表达式、枚举、命名参数、属性、构造器属性提升
echo "=== f154: Match + Enums + Named Args + Attributes ===\n";

// 枚举
enum Suit: string {
    case Hearts = 'hearts';
    case Diamonds = 'diamonds';
    case Clubs = 'clubs';
    case Spades = 'spades';

    public function color(): string {
        return match($this) {
            Suit::Hearts, Suit::Diamonds => 'red',
            Suit::Clubs, Suit::Spades => 'black',
        };
    }

    public function symbol(): string {
        return match($this) {
            Suit::Hearts => '♥',
            Suit::Diamonds => '♦',
            Suit::Clubs => '♣',
            Suit::Spades => '♠',
        };
    }
}

enum HttpStatus: int {
    case Ok = 200;
    case Created = 201;
    case NoContent = 204;
    case BadRequest = 400;
    case Unauthorized = 401;
    case Forbidden = 403;
    case NotFound = 404;
    case ServerError = 500;

    public function text(): string {
        return match($this) {
            HttpStatus::Ok => 'OK',
            HttpStatus::Created => 'Created',
            HttpStatus::NoContent => 'No Content',
            HttpStatus::BadRequest => 'Bad Request',
            HttpStatus::Unauthorized => 'Unauthorized',
            HttpStatus::Forbidden => 'Forbidden',
            HttpStatus::NotFound => 'Not Found',
            HttpStatus::ServerError => 'Internal Server Error',
        };
    }

    public function isError(): bool {
        return $this->value >= 400;
    }

    public function isClientError(): bool {
        return $this->value >= 400 && $this->value < 500;
    }

    public function isServerError(): bool {
        return $this->value >= 500;
    }
}

// 枚举实现接口
interface Action {
    public function execute(): string;
}

enum Command: string implements Action {
    case Run = 'run';
    case Stop = 'stop';
    case Pause = 'pause';
    case Resume = 'resume';

    public function execute(): string {
        return match($this) {
            Command::Run => 'Starting process...',
            Command::Stop => 'Stopping process...',
            Command::Pause => 'Pausing process...',
            Command::Resume => 'Resuming process...',
        };
    }
}

// 构造器属性提升
class Point {
    public function __construct(
        public float $x,
        public float $y,
        public float $z = 0.0,
    ) {}

    public function distance(Point $other): float {
        $dx = $this->x - $other->x;
        $dy = $this->y - $other->y;
        $dz = $this->z - $other->z;
        return sqrt($dx * $dx + $dy * $dy + $dz * $dz);
    }

    public function __toString(): string {
        return "({$this->x}, {$this->y}, {$this->z})";
    }
}

class Rectangle {
    public function __construct(
        public float $width,
        public float $height,
        public string $color = 'white',
        public bool $filled = true,
    ) {}

    public function area(): float { return $this->width * $this->height; }
    public function perimeter(): float { return 2 * ($this->width + $this->height); }

    public function describe(): string {
        return sprintf('%.1fx%.1f %s %s', $this->width, $this->height, $this->color, $this->filled ? 'filled' : 'outline');
    }
}

// 命名参数
function createRect(float $w, float $h, string $color = 'white', bool $filled = true): Rectangle {
    return new Rectangle($w, $h, $color, $filled);
}

// 测试
echo "--- Enums (Suit) ---\n";
foreach (Suit::cases() as $suit) {
    echo "  {$suit->value} ({$suit->symbol()}): {$suit->color()}\n";
}

echo "\n--- Enums (HttpStatus) ---\n";
$statuses = [HttpStatus::Ok, HttpStatus::NotFound, HttpStatus::ServerError, HttpStatus::BadRequest];
foreach ($statuses as $status) {
    $type = $status->isClientError() ? 'Client Error' : ($status->isServerError() ? 'Server Error' : 'Success');
    echo "  {$status->value} {$status->text()} ($type)\n";
}

echo "\n--- Enums (Command with Interface) ---\n";
foreach (Command::cases() as $cmd) {
    echo "  {$cmd->value}: " . $cmd->execute() . "\n";
}

echo "\n--- Constructor Promotion (Point) ---\n";
$p1 = new Point(0, 0, 0);
$p2 = new Point(3, 4, 0);
$p3 = new Point(1, 2, 3);
echo "  p1 = $p1\n";
echo "  p2 = $p2\n";
echo "  distance(p1, p2) = " . $p1->distance($p2) . "\n";
echo "  distance(p1, p3) = " . $p1->distance($p3) . "\n";

echo "\n--- Named Arguments ---\n";
$r1 = createRect(10, 20);
$r2 = createRect(w: 5, h: 10, color: 'red');
$r3 = createRect(color: 'blue', filled: false, w: 8, h: 3);
echo "  r1: {$r1->describe()} (area: {$r1->area()})\n";
echo "  r2: {$r2->describe()} (area: {$r2->area()})\n";
echo "  r3: {$r3->describe()} (perimeter: {$r3->perimeter()})\n";

echo "\n--- Match Expression ---\n";
$values = [1, 2, 3, 4, 5, 10, 100, 'hello', null, true];
foreach ($values as $val) {
    $result = match(true) {
        $val === null => 'null',
        is_bool($val) => $val ? 'true' : 'false',
        is_int($val) && $val < 5 => "small int: $val",
        is_int($val) && $val < 50 => "medium int: $val",
        is_int($val) => "large int: $val",
        is_string($val) => "string: '$val'",
        default => 'unknown',
    };
    echo "  " . var_export($val, true) . " → $result\n";
}

echo "\n--- Match with Conditions ---\n";
$temps = [-10, 0, 15, 25, 35, 45];
foreach ($temps as $t) {
    $desc = match(true) {
        $t < 0 => 'freezing',
        $t < 10 => 'cold',
        $t < 20 => 'cool',
        $t < 30 => 'warm',
        $t < 40 => 'hot',
        default => 'extreme',
    };
    echo "  {$t}°C: $desc\n";
}

echo "=== f154 Done ===\n";
