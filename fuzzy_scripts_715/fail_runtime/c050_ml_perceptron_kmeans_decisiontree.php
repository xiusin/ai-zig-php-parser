<?php
// 极度混搭: 机器学习模拟 + 感知机 + K-Means聚类 + 决策树 + 混淆矩阵
echo "=== c050: ML Sim + Perceptron + KMeans + DecisionTree + ConfusionMatrix ===\n\n";

class Perceptron {
    private array $weights;
    private float $bias;
    private float $learningRate;

    public function __construct(int $features, float $lr = 0.1) {
        $this->weights = array_fill(0, $features, 0.0);
        $this->bias = 0.0;
        $this->learningRate = $lr;
    }

    public function predict(array $inputs): int {
        $sum = $this->bias;
        for ($i = 0; $i < count($inputs); $i++) {
            $sum += $inputs[$i] * $this->weights[$i];
        }
        return $sum >= 0 ? 1 : 0;
    }

    public function train(array $data, int $epochs = 100): array {
        $errors = [];
        for ($epoch = 0; $epoch < $epochs; $epoch++) {
            $epochErrors = 0;
            foreach ($data as $sample) {
                $inputs = $sample['features'];
                $label = $sample['label'];
                $prediction = $this->predict($inputs);
                $error = $label - $prediction;
                if ($error != 0) {
                    for ($i = 0; $i < count($inputs); $i++) {
                        $this->weights[$i] += $this->learningRate * $error * $inputs[$i];
                    }
                    $this->bias += $this->learningRate * $error;
                    $epochErrors++;
                }
            }
            $errors[] = $epochErrors;
            if ($epochErrors == 0) break;
        }
        return $errors;
    }

    public function getWeights(): array {
        return ['weights' => $this->weights, 'bias' => $this->bias];
    }
}

class KMeansCluster {
    private int $k;
    private array $centroids = [];

    public function __construct(int $k) {
        $this->k = $k;
    }

    public function fit(array $data, int $maxIter = 50): void {
        // Initialize centroids using first k data points
        $this->centroids = array_slice(array_map(fn($d) => $d, $data), 0, $this->k);

        for ($iter = 0; $iter < $maxIter; $iter++) {
            $clusters = array_fill(0, $this->k, []);
            $changed = false;

            foreach ($data as $point) {
                $nearest = $this->nearestCentroid($point);
                $clusters[$nearest][] = $point;
            }

            $newCentroids = [];
            for ($c = 0; $c < $this->k; $c++) {
                if (empty($clusters[$c])) {
                    $newCentroids[$c] = $this->centroids[$c];
                    continue;
                }
                $dim = count($clusters[$c][0]);
                $newCentroid = array_fill(0, $dim, 0.0);
                foreach ($clusters[$c] as $point) {
                    for ($d = 0; $d < $dim; $d++) {
                        $newCentroid[$d] += $point[$d];
                    }
                }
                for ($d = 0; $d < $dim; $d++) {
                    $newCentroid[$d] /= count($clusters[$c]);
                }
                $newCentroids[$c] = $newCentroid;
            }

            for ($c = 0; $c < $this->k; $c++) {
                for ($d = 0; $d < count($newCentroids[$c]); $d++) {
                    if (abs($newCentroids[$c][$d] - $this->centroids[$c][$d]) > 0.001) {
                        $changed = true;
                    }
                }
            }
            $this->centroids = $newCentroids;
            if (!$changed) break;
        }
    }

    private function nearestCentroid(array $point): int {
        $minDist = PHP_FLOAT_MAX;
        $nearest = 0;
        for ($c = 0; $c < $this->k; $c++) {
            $dist = $this->distance($point, $this->centroids[$c]);
            if ($dist < $minDist) {
                $minDist = $dist;
                $nearest = $c;
            }
        }
        return $nearest;
    }

    private function distance(array $a, array $b): float {
        $sum = 0;
        for ($i = 0; $i < count($a); $i++) {
            $sum += ($a[$i] - $b[$i]) ** 2;
        }
        return sqrt($sum);
    }

    public function predict(array $point): int {
        return $this->nearestCentroid($point);
    }

    public function getCentroids(): array {
        return $this->centroids;
    }
}

class DecisionTreeNode {
    public ?int $feature = null;
    public ?float $threshold = null;
    public ?DecisionTreeNode $left = null;
    public ?DecisionTreeNode $right = null;
    public ?string $label = null;
    public bool $isLeaf = false;

    public function predict(array $features): string {
        if ($this->isLeaf) return $this->label;
        if ($features[$this->feature] <= $this->threshold) {
            return $this->left->predict($features);
        }
        return $this->right->predict($features);
    }
}

class SimpleDecisionTree {
    private ?DecisionTreeNode $root = null;

    public function build(array $data, array $labels, array $featureIndices): void {
        $this->root = $this->buildNode($data, $labels, $featureIndices, 0);
    }

    private function buildNode(array $data, array $labels, array $features, int $depth): DecisionTreeNode {
        $node = new DecisionTreeNode();

        // Check if all same label
        $uniqueLabels = array_unique($labels);
        if (count($uniqueLabels) == 1) {
            $node->isLeaf = true;
            $node->label = $uniqueLabels[0];
            return $node;
        }

        if ($depth >= 3 || empty($features)) {
            $node->isLeaf = true;
            $counts = array_count_values($labels);
            arsort($counts);
            $node->label = array_key_first($counts);
            return $node;
        }

        // Find best split
        $bestFeature = $features[0];
        $bestThreshold = 0;
        $bestGini = 1.0;

        foreach ($features as $feat) {
            $values = array_unique(array_column($data, $feat));
            sort($values);
            for ($i = 0; $i < count($values) - 1; $i++) {
                $threshold = ($values[$i] + $values[$i + 1]) / 2;
                $gini = $this->giniImpurity($data, $labels, $feat, $threshold);
                if ($gini < $bestGini) {
                    $bestGini = $gini;
                    $bestFeature = $feat;
                    $bestThreshold = $threshold;
                }
            }
        }

        $node->feature = $bestFeature;
        $node->threshold = $bestThreshold;

        $leftData = []; $leftLabels = [];
        $rightData = []; $rightLabels = [];
        for ($i = 0; $i < count($data); $i++) {
            if ($data[$i][$bestFeature] <= $bestThreshold) {
                $leftData[] = $data[$i];
                $leftLabels[] = $labels[$i];
            } else {
                $rightData[] = $data[$i];
                $rightLabels[] = $labels[$i];
            }
        }

        $remainingFeatures = array_values(array_filter($features, fn($f) => $f !== $bestFeature));
        $node->left = $this->buildNode($leftData, $leftLabels, $remainingFeatures, $depth + 1);
        $node->right = $this->buildNode($rightData, $rightLabels, $remainingFeatures, $depth + 1);
        return $node;
    }

    private function giniImpurity(array $data, array $labels, int $feat, float $threshold): float {
        $leftLabels = []; $rightLabels = [];
        for ($i = 0; $i < count($data); $i++) {
            if ($data[$i][$feat] <= $threshold) {
                $leftLabels[] = $labels[$i];
            } else {
                $rightLabels[] = $labels[$i];
            }
        }
        $giniLeft = $this->calcGini($leftLabels);
        $giniRight = $this->calcGini($rightLabels);
        $total = count($leftLabels) + count($rightLabels);
        $leftWeight = count($leftLabels) / $total;
        $rightWeight = count($rightLabels) / $total;
        return $leftWeight * $giniLeft + $rightWeight * $giniRight;
    }

    private function calcGini(array $labels): float {
        if (empty($labels)) return 0;
        $counts = array_count_values($labels);
        $sum = 0;
        $total = count($labels);
        foreach ($counts as $count) {
            $p = $count / $total;
            $sum += $p * $p;
        }
        return 1 - $sum;
    }

    public function predict(array $features): string {
        return $this->root->predict($features);
    }
}

class ConfusionMatrix {
    private array $matrix = [];
    private array $labels;

    public function __construct(array $labels) {
        $this->labels = array_values($labels);
        foreach ($this->labels as $actual) {
            foreach ($this->labels as $predicted) {
                $this->matrix[$actual][$predicted] = 0;
            }
        }
    }

    public function record(string $actual, string $predicted): void {
        $this->matrix[$actual][$predicted]++;
    }

    public function getAccuracy(): float {
        $correct = 0;
        $total = 0;
        foreach ($this->matrix as $actual => $row) {
            foreach ($row as $predicted => $count) {
                $total += $count;
                if ($actual === $predicted) $correct += $count;
            }
        }
        return $total > 0 ? $correct / $total : 0;
    }

    public function getPrecision(string $label): float {
        $tp = $this->matrix[$label][$label] ?? 0;
        $fp = 0;
        foreach ($this->matrix as $actual => $row) {
            if ($actual !== $label) {
                $fp += $row[$label] ?? 0;
            }
        }
        return ($tp + $fp) > 0 ? $tp / ($tp + $fp) : 0;
    }

    public function getRecall(string $label): float {
        $tp = $this->matrix[$label][$label] ?? 0;
        $fn = 0;
        foreach ($this->matrix[$label] as $predicted => $count) {
            if ($predicted !== $label) {
                $fn += $count;
            }
        }
        return ($tp + $fn) > 0 ? $tp / ($tp + $fn) : 0;
    }

    public function getF1(string $label): float {
        $precision = $this->getPrecision($label);
        $recall = $this->getRecall($label);
        return ($precision + $recall) > 0 ? 2 * $precision * $recall / ($precision + $recall) : 0;
    }

    public function getMatrix(): array {
        return $this->matrix;
    }
}

// === 测试 ===

echo "--- Perceptron (Binary Classification) ---\n";
$perceptron = new Perceptron(2);
$trainingData = [
    ['features' => [0, 0], 'label' => 0],
    ['features' => [0, 1], 'label' => 0],
    ['features' => [1, 0], 'label' => 0],
    ['features' => [1, 1], 'label' => 1],
];
$errors = $perceptron->train($trainingData, 50);
echo "Training errors per epoch: " . implode(", ", $errors) . "\n";
echo "Weights: " . json_encode($perceptron->getWeights()) . "\n";
foreach ($trainingData as $d) {
    $pred = $perceptron->predict($d['features']);
    echo "  predict(" . implode(",", $d['features']) . ") = $pred (expected {$d['label']})\n";
}

echo "\n--- K-Means Clustering ---\n";
$kmeans = new KMeansCluster(3);
$clusterData = [
    [1, 1], [1.5, 2], [1.2, 0.8], [0.9, 1.1],
    [8, 8], [8.5, 8.2], [9, 9], [7.8, 8.5],
    [15, 3], [14, 3.5], [16, 2.8], [15.5, 3.2],
];
$kmeans->fit($clusterData);
echo "Centroids: " . json_encode($kmeans->getCentroids()) . "\n";
foreach ($clusterData as $i => $point) {
    $cluster = $kmeans->predict($point);
    echo "  point[" . implode(",", $point) . "] -> cluster $cluster\n";
}

echo "\n--- Decision Tree ---\n";
$dt = new SimpleDecisionTree();
$dtData = [
    [25, 50000], [35, 80000], [45, 120000], [22, 30000],
    [50, 150000], [30, 60000], [40, 90000], [28, 45000],
];
$dtLabels = ['junior', 'mid', 'senior', 'junior', 'senior', 'mid', 'senior', 'junior'];
$dt->build($dtData, $dtLabels, [0, 1]);

foreach ($dtData as $i => $features) {
    $pred = $dt->predict($features);
    echo "  age={$features[0]} salary={$features[1]} -> $pred (actual: {$dtLabels[$i]})\n";
}

echo "\n--- Confusion Matrix ---\n";
$cm = new ConfusionMatrix(['A', 'B', 'C']);
$actual = ['A', 'A', 'A', 'A', 'B', 'B', 'B', 'C', 'C', 'C'];
$predicted = ['A', 'A', 'B', 'A', 'B', 'B', 'C', 'C', 'C', 'A'];
for ($i = 0; $i < count($actual); $i++) {
    $cm->record($actual[$i], $predicted[$i]);
}
echo "Matrix: " . json_encode($cm->getMatrix()) . "\n";
echo "Accuracy: " . round($cm->getAccuracy() * 100, 1) . "%\n";
echo "Precision A: " . round($cm->getPrecision('A') * 100, 1) . "%\n";
echo "Recall A: " . round($cm->getRecall('A') * 100, 1) . "%\n";
echo "F1 A: " . round($cm->getF1('A'), 3) . "\n";
echo "Precision B: " . round($cm->getPrecision('B') * 100, 1) . "%\n";
echo "Recall C: " . round($cm->getRecall('C') * 100, 1) . "%\n";

echo "\n=== c050 Done ===\n";
