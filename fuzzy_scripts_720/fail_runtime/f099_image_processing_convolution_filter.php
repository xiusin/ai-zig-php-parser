<?php
// 极度混搭: 图像处理简化 + 卷积 + 滤镜 + 直方图 + 缩放
echo "=== f099: Image Processing + Convolution + Filter ===\n";

class Image {
    public function __construct(public array $pixels, public int $width, public int $height) {}

    public static function random(int $w, int $h, int $seed = 42): self {
        mt_srand($seed);
        $pixels = [];
        for ($y = 0; $y < $h; $y++) {
            $row = [];
            for ($x = 0; $x < $w; $x++) $row[] = mt_rand(0, 255);
            $pixels[] = $row;
        }
        return new self($pixels, $w, $h);
    }

    public static function gradient(int $w, int $h): self {
        $pixels = [];
        for ($y = 0; $y < $h; $y++) {
            $row = [];
            for ($x = 0; $x < $w; $x++) $row[] = (int)(($x + $y) / ($w + $h - 2) * 255);
            $pixels[] = $row;
        }
        return new self($pixels, $w, $h);
    }

    public function get(int $x, int $y): int {
        $x = max(0, min($this->width - 1, $x));
        $y = max(0, min($this->height - 1, $y));
        return $this->pixels[$y][$x];
    }

    public function convolve(array $kernel): self {
        $kSize = count($kernel);
        $kHalf = (int)($kSize / 2);
        $result = [];
        for ($y = 0; $y < $this->height; $y++) {
            $row = [];
            for ($x = 0; $x < $this->width; $x++) {
                $sum = 0;
                for ($ky = 0; $ky < $kSize; $ky++) {
                    for ($kx = 0; $kx < $kSize; $kx++) {
                        $px = $x + $kx - $kHalf;
                        $py = $y + $ky - $kHalf;
                        $sum += $this->get($px, $py) * $kernel[$ky][$kx];
                    }
                }
                $row[] = max(0, min(255, (int)$sum));
            }
            $result[] = $row;
        }
        return new self($result, $this->width, $this->height);
    }

    public function brightness(float $factor): self {
        $result = [];
        foreach ($this->pixels as $row) {
            $result[] = array_map(fn($p) => max(0, min(255, (int)($p * $factor))), $row);
        }
        return new self($result, $this->width, $this->height);
    }

    public function invert(): self {
        $result = [];
        foreach ($this->pixels as $row) {
            $result[] = array_map(fn($p) => 255 - $p, $row);
        }
        return new self($result, $this->width, $this->height);
    }

    public function threshold(int $thresh): self {
        $result = [];
        foreach ($this->pixels as $row) {
            $result[] = array_map(fn($p) => $p >= $thresh ? 255 : 0, $row);
        }
        return new self($result, $this->width, $this->height);
    }

    public function histogram(): array {
        $hist = array_fill(0, 256, 0);
        foreach ($this->pixels as $row) {
            foreach ($row as $p) $hist[$p]++;
        }
        return $hist;
    }

    public function histogramEqualization(): self {
        $hist = $this->histogram();
        $cdf = []; $sum = 0;
        $total = $this->width * $this->height;
        for ($i = 0; $i < 256; $i++) {
            $sum += $hist[$i];
            $cdf[$i] = (int)(($sum / $total) * 255);
        }
        $result = [];
        foreach ($this->pixels as $row) {
            $result[] = array_map(fn($p) => $cdf[$p], $row);
        }
        return new self($result, $this->width, $this->height);
    }

    public function resize(int $newW, int $newH): self {
        $result = [];
        $xRatio = $this->width / $newW;
        $yRatio = $this->height / $newH;
        for ($y = 0; $y < $newH; $y++) {
            $row = [];
            for ($x = 0; $x < $newW; $x++) {
                $srcX = (int)($x * $xRatio);
                $srcY = (int)($y * $yRatio);
                $row[] = $this->get($srcX, $srcY);
            }
            $result[] = $row;
        }
        return new self($result, $newW, $newH);
    }

    public function stats(): array {
        $all = [];
        foreach ($this->pixels as $row) $all = array_merge($all, $row);
        return ['min' => min($all), 'max' => max($all), 'avg' => array_sum($all) / count($all), 'count' => count($all)];
    }

    public function preview(int $maxW = 20): string {
        $chars = ' .:-=+*#%@';
        $lines = [];
        for ($y = 0; $y < min($this->height, 10); $y++) {
            $line = '';
            for ($x = 0; $x < min($this->width, $maxW); $x++) {
                $idx = (int)($this->pixels[$y][$x] / 256 * strlen($chars));
                $line .= $chars[min($idx, strlen($chars) - 1)];
            }
            $lines[] = $line;
        }
        return implode("\n", $lines);
    }
}

// 测试
echo "--- Generate Image ---\n";
$img = Image::gradient(8, 8);
echo "Gradient 8x8:\n" . $img->preview() . "\n";
echo "Stats: " . json_encode($img->stats()) . "\n";

echo "\n--- Brightness ---\n";
$bright = $img->brightness(1.5);
echo "Brightened:\n" . $bright->preview() . "\n";

$dark = $img->brightness(0.5);
echo "Darkened:\n" . $dark->preview() . "\n";

echo "\n--- Invert ---\n";
$inverted = $img->invert();
echo "Inverted:\n" . $inverted->preview() . "\n";

echo "\n--- Threshold ---\n";
$thresh = $img->threshold(128);
echo "Threshold 128:\n" . $thresh->preview() . "\n";

echo "\n--- Convolution: Blur ---\n";
$blurKernel = [[1/9, 1/9, 1/9], [1/9, 1/9, 1/9], [1/9, 1/9, 1/9]];
$blurred = $img->convolve($blurKernel);
echo "Blurred:\n" . $blurred->preview() . "\n";

echo "\n--- Convolution: Sharpen ---\n";
$sharpenKernel = [[0, -1, 0], [-1, 5, -1], [0, -1, 0]];
$sharpened = $img->convolve($sharpenKernel);
echo "Sharpened:\n" . $sharpened->preview() . "\n";

echo "\n--- Convolution: Edge (Sobel X) ---\n";
$sobelX = [[-1, 0, 1], [-2, 0, 2], [-1, 0, 1]];
$edges = $img->convolve($sobelX);
echo "Sobel X:\n" . $edges->preview() . "\n";

echo "\n--- Histogram ---\n";
$hist = $img->histogram();
echo "Histogram (non-zero bins): ";
for ($i = 0; $i < 256; $i++) {
    if ($hist[$i] > 0) echo "$i:$hist[$i] ";
}
echo "\n";

echo "\n--- Histogram Equalization ---\n";
$eqImg = $img->histogramEqualization();
echo "Equalized:\n" . $eqImg->preview() . "\n";
echo "Equalized stats: " . json_encode($eqImg->stats()) . "\n";

echo "\n--- Resize ---\n";
$small = $img->resize(4, 4);
echo "Resized to 4x4:\n" . $small->preview() . "\n";
$large = $img->resize(16, 8);
echo "Resized to 16x8:\n" . $large->preview(16) . "\n";

echo "\n--- Random Image Processing ---\n";
$rnd = Image::random(10, 6, 99);
echo "Original random:\n" . $rnd->preview(10) . "\n";
echo "Blurred:\n" . $rnd->convolve($blurKernel)->preview(10) . "\n";
echo "Edge detected:\n" . $rnd->convolve($sobelX)->preview(10) . "\n";

echo "=== f099 Done ===\n";
