<?php
// 极度混搭: ML简化 + 感知机 + K-means聚类 + 决策树桩 + 线性回归
echo "=== f055: ML + Perceptron + KMeans + DecisionStump ===\n";

class Perceptron {
    private array $weights;
    private float $bias = 0.0;

    public function __construct(private int $features, private float $lr = 0.1) {
        $this->weights = array_fill(0, $features, 0.0);
    }

    public function predict(array $x): int {
        $sum = $this->bias;
        for ($i = 0; $i < count($x); $i++) $sum += $this->weights[$i] * $x[$i];
        return $sum >= 0 ? 1 : 0;
    }

    public function train(array $X, array $y, int $epochs = 100): array {
        $history = [];
        for ($epoch = 0; $epoch < $epochs; $epoch++) {
            $errors = 0;
            for ($i = 0; $i < count($X); $i++) {
                $pred = $this->predict($X[$i]);
                $error = $y[$i] - $pred;
                if ($error !== 0) {
                    for ($j = 0; $j < $this->features; $j++) {
                        $this->weights[$j] += $this->lr * $error * $X[$i][$j];
                    }
                    $this->bias += $this->lr * $error;
                    $errors++;
                }
            }
            $history[] = ['epoch' => $epoch, 'errors' => $errors];
            if ($errors === 0) break;
        }
        return $history;
    }

    public function getWeights(): array { return array_merge($this->weights, [$this->bias]); }
}

class KMeans {
    private array $centroids = [];

    public function fit(array $data, int $k, int $maxIter = 100): array {
        // 初始化：随机选k个点
        $indices = array_rand($data, $k);
        if (!is_array($indices)) $indices = [$indices];
        $this->centroids = array_map(fn($i) => $data[$i], $indices);

        for ($iter = 0; $iter < $maxIter; $iter++) {
            // 分配
            $clusters = array_fill(0, $k, []);
            foreach ($data as $point) {
                $nearest = $this->nearestCentroid($point);
                $clusters[$nearest][] = $point;
            }
            // 更新
            $changed = false;
            for ($c = 0; $c < $k; $c++) {
                if (empty($clusters[$c])) continue;
                $newCentroid = $this->meanPoint($clusters[$c]);
                if ($newCentroid !== $this->centroids[$c]) {
                    $this->centroids[$c] = $newCentroid;
                    $changed = true;
                }
            }
            if (!$changed) break;
        }
        return $this->centroids;
    }

    private function nearestCentroid(array $point): int {
        $minDist = PHP_FLOAT_MAX;
        $nearest = 0;
        foreach ($this->centroids as $i => $centroid) {
            $dist = $this->distance($point, $centroid);
            if ($dist < $minDist) { $minDist = $dist; $nearest = $i; }
        }
        return $nearest;
    }

    private function distance(array $a, array $b): float {
        $sum = 0;
        for ($i = 0; $i < count($a); $i++) $sum += ($a[$i] - $b[$i]) ** 2;
        return sqrt($sum);
    }

    private function meanPoint(array $points): array {
        $n = count($points);
        $dim = count($points[0]);
        $mean = array_fill(0, $dim, 0.0);
        foreach ($points as $p) {
            for ($i = 0; $i < $dim; $i++) $mean[$i] += $p[$i];
        }
        return array_map(fn($v) => $v / $n, $mean);
    }

    public function predict(array $point): int {
        return $this->nearestCentroid($point);
    }

    public function getCentroids(): array { return $this->centroids; }
}

class LinearRegression {
    private float $slope = 0.0;
    private float $intercept = 0.0;

    public function fit(array $x, array $y): void {
        $n = count($x);
        $sumX = array_sum($x);
        $sumY = array_sum($y);
        $sumXY = 0; $sumX2 = 0;
        for ($i = 0; $i < $n; $i++) {
            $sumXY += $x[$i] * $y[$i];
            $sumX2 += $x[$i] * $x[$i];
        }
        $this->slope = ($n * $sumXY - $sumX * $sumY) / ($n * $sumX2 - $sumX * $sumX);
        $this->intercept = ($sumY - $this->slope * $sumX) / $n;
    }

    public function predict(float $x): float {
        return $this->slope * $x + $this->intercept;
    }

    public function r2Score(array $x, array $y): float {
        $meanY = array_sum($y) / count($y);
        $ssRes = 0; $ssTot = 0;
        for ($i = 0; $i < count($x); $i++) {
            $pred = $this->predict($x[$i]);
            $ssRes += ($y[$i] - $pred) ** 2;
            $ssTot += ($y[$i] - $meanY) ** 2;
        }
        return $ssTot == 0 ? 1 : 1 - $ssRes / $ssTot;
    }

    public function getSlope(): float { return $this->slope; }
    public function getIntercept(): float { return $this->intercept; }
}

// 测试
echo "--- Perceptron (AND gate) ---\n";
$perceptron = new Perceptron(2, 0.1);
$X = [[0,0], [0,1], [1,0], [1,1]];
$y = [0, 0, 0, 1];
$history = $perceptron->train($X, $y, 50);
echo "Training history (epochs=" . count($history) . "):\n";
foreach ($history as $h) echo "  Epoch {$h['epoch']}: errors={$h['errors']}\n";
echo "Weights: " . json_encode($perceptron->getWeights()) . "\n";
foreach ($X as $i => $x) {
    echo "  predict(" . json_encode($x) . ") = " . $perceptron->predict($x) . " (expected {$y[$i]})\n";
}

echo "\n--- Perceptron (OR gate) ---\n";
$p2 = new Perceptron(2, 0.1);
$y2 = [0, 1, 1, 1];
$p2->train($X, $y2, 50);
foreach ($X as $i => $x) {
    echo "  predict(" . json_encode($x) . ") = " . $p2->predict($x) . " (expected {$y2[$i]})\n";
}

echo "\n--- KMeans Clustering ---\n";
$data = [
    [1.0, 1.0], [1.5, 2.0], [1.2, 0.8], [0.8, 1.5],
    [8.0, 8.0], [8.5, 7.5], [9.0, 8.2], [7.8, 8.8],
    [4.0, 4.0], [4.5, 3.5], [3.8, 4.2], [4.2, 3.8],
];
$kmeans = new KMeans();
$centroids = $kmeans->fit($data, 3);
echo "Centroids:\n";
foreach ($centroids as $i => $c) echo "  Cluster $i: [" . number_format($c[0], 2) . ", " . number_format($c[1], 2) . "]\n";
echo "Predict [1,1]: cluster " . $kmeans->predict([1, 1]) . "\n";
echo "Predict [8,8]: cluster " . $kmeans->predict([8, 8]) . "\n";
echo "Predict [4,4]: cluster " . $kmeans->predict([4, 4]) . "\n";

echo "\n--- Linear Regression ---\n";
$reg = new LinearRegression();
$xData = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
$yData = [2.1, 3.9, 6.2, 7.8, 10.1, 11.9, 14.2, 15.8, 18.1, 19.9];
$reg->fit($xData, $yData);
echo "Slope: " . number_format($reg->getSlope(), 4) . "\n";
echo "Intercept: " . number_format($reg->getIntercept(), 4) . "\n";
echo "R² Score: " . number_format($reg->r2Score($xData, $yData), 6) . "\n";
echo "Predict(15): " . number_format($reg->predict(15), 2) . "\n";
echo "Predict(20): " . number_format($reg->predict(20), 2) . "\n";

echo "=== f055 Done ===\n";
