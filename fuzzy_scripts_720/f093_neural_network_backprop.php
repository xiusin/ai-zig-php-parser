<?php
// 极度混搭: 神经网络简化 + 前向传播 + 反向传播 + 激活函数
echo "=== f093: Neural Network + Forward + Backprop ===\n";

class Matrix {
    public array $data;
    public function __construct(array $data) { $this->data = $data; }
    public function rows(): int { return count($this->data); }
    public function cols(): int { return count($this->data[0]); }

    public static function random(int $rows, int $cols, float $scale = 1.0): self {
        $data = [];
        for ($i = 0; $i < $rows; $i++) {
            $row = [];
            for ($j = 0; $j < $cols; $j++) $row[] = (mt_rand() / mt_getrandmax() - 0.5) * 2 * $scale;
            $data[] = $row;
        }
        return new self($data);
    }

    public static function zeros(int $rows, int $cols): self {
        return new self(array_fill(0, $rows, array_fill(0, $cols, 0.0)));
    }

    public function dot(self $other): self {
        $r = $this->rows(); $c = $other->cols(); $k = $this->cols();
        $result = array_fill(0, $r, array_fill(0, $c, 0.0));
        for ($i = 0; $i < $r; $i++)
            for ($j = 0; $j < $c; $j++) {
                $sum = 0;
                for ($x = 0; $x < $k; $x++) $sum += $this->data[$i][$x] * $other->data[$x][$j];
                $result[$i][$j] = $sum;
            }
        return new self($result);
    }

    public function add(self $other): self {
        $result = [];
        for ($i = 0; $i < $this->rows(); $i++)
            for ($j = 0; $j < $this->cols(); $j++)
                $result[$i][$j] = $this->data[$i][$j] + $other->data[$i][$j];
        return new self($result);
    }

    public function transpose(): self {
        $result = [];
        for ($i = 0; $i < $this->cols(); $i++)
            for ($j = 0; $j < $this->rows(); $j++)
                $result[$i][$j] = $this->data[$j][$i];
        return new self($result);
    }

    public function map(callable $fn): self {
        $result = [];
        for ($i = 0; $i < $this->rows(); $i++)
            for ($j = 0; $j < $this->cols(); $j++)
                $result[$i][$j] = $fn($this->data[$i][$j], $i, $j);
        return new self($result);
    }

    public function scale(float $s): self { return $this->map(fn($v) => $v * $s); }
}

class Activation {
    public static function sigmoid(float $x): float { return 1 / (1 + exp(-$x)); }
    public static function sigmoidDeriv(float $x): float { $s = self::sigmoid($x); return $s * (1 - $s); }
    public static function relu(float $x): float { return max(0, $x); }
    public static function reluDeriv(float $x): float { return $x > 0 ? 1 : 0; }
    public static function tanh(float $x): float { return tanh($x); }
    public static function tanhDeriv(float $x): float { $t = tanh($x); return 1 - $t * $t; }
}

class NeuralLayer {
    public Matrix $weights;
    public Matrix $biases;
    public ?Matrix $lastInput = null;
    public ?Matrix $lastZ = null;
    public ?Matrix $lastActivation = null;

    public function __construct(int $inputSize, int $outputSize, private string $activation = 'sigmoid') {
        $this->weights = Matrix::random($inputSize, $outputSize, 0.5);
        $this->biases = Matrix::zeros(1, $outputSize);
    }

    public function forward(Matrix $input): Matrix {
        $this->lastInput = $input;
        $this->lastZ = $input->dot($this->weights)->add($this->biases);
        $fn = match($this->activation) { 'sigmoid' => [Activation::class, 'sigmoid'], 'relu' => [Activation::class, 'relu'], 'tanh' => [Activation::class, 'tanh'] };
        $this->lastActivation = $this->lastZ->map($fn[0]);
        return $this->lastActivation;
    }

    public function backward(Matrix $delta, float $lr): Matrix {
        $derivFn = match($this->activation) {
            'sigmoid' => fn($z) => Activation::sigmoid($z) * (1 - Activation::sigmoid($z)),
            'relu' => fn($z) => $z > 0 ? 1.0 : 0.0,
            'tanh' => fn($z) => 1 - tanh($z) ** 2,
        };
        $deriv = $this->lastZ->map($derivFn);
        // delta = delta * deriv (element-wise)
        $newDelta = Matrix::zeros($deriv->rows(), $deriv->cols());
        for ($i = 0; $i < $deriv->rows(); $i++)
            for ($j = 0; $j < $deriv->cols(); $j++)
                $newDelta->data[$i][$j] = $delta->data[$i][$j] * $deriv->data[$i][$j];

        $gradWeights = $this->lastInput->transpose()->dot($newDelta)->scale($lr);
        $gradBiases = $newDelta->scale($lr);
        $prevDelta = $newDelta->dot($this->weights->transpose());

        for ($i = 0; $i < $this->weights->rows(); $i++)
            for ($j = 0; $j < $this->weights->cols(); $j++)
                $this->weights->data[$i][$j] += $gradWeights->data[$i][$j];
        for ($j = 0; $j < $this->biases->cols(); $j++)
            $this->biases->data[0][$j] += $gradBiases->data[0][$j];

        return $prevDelta;
    }
}

class NeuralNetwork {
    private array $layers = [];
    private array $lossHistory = [];

    public function addLayer(NeuralLayer $layer): void { $this->layers[] = $layer; }

    public function forward(Matrix $input): Matrix {
        $current = $input;
        foreach ($this->layers as $layer) $current = $layer->forward($current);
        return $current;
    }

    public function train(Matrix $X, Matrix $y, int $epochs, float $lr): array {
        for ($epoch = 0; $epoch < $epochs; $epoch++) {
            $output = $this->forward($X);
            // MSE loss: delta = (y - output) * 2/n
            $n = $y->rows();
            $delta = Matrix::zeros($y->rows(), $y->cols());
            $loss = 0;
            for ($i = 0; $i < $n; $i++) {
                for ($j = 0; $j < $y->cols(); $j++) {
                    $diff = $y->data[$i][$j] - $output->data[$i][$j];
                    $delta->data[$i][$j] = $diff * 2 / $n;
                    $loss += $diff * $diff;
                }
            }
            $loss /= $n;
            $this->lossHistory[] = $loss;
            // 反向传播
            for ($i = count($this->layers) - 1; $i >= 0; $i--) {
                $delta = $this->layers[$i]->backward($delta, $lr);
            }
            if ($epoch % max(1, (int)($epochs / 5)) === 0) {
                echo "  Epoch $epoch: loss=" . number_format($loss, 6) . "\n";
            }
        }
        return $this->lossHistory;
    }

    public function predict(Matrix $input): Matrix { return $this->forward($input); }
    public function getLossHistory(): array { return $this->lossHistory; }
}

// 测试
echo "--- XOR Problem ---\n";
$nn = new NeuralNetwork();
$nn->addLayer(new NeuralLayer(2, 4, 'sigmoid'));
$nn->addLayer(new NeuralLayer(4, 1, 'sigmoid'));

$X = new Matrix([[0, 0], [0, 1], [1, 0], [1, 1]]);
$y = new Matrix([[0], [1], [1], [0]]);

echo "Training (1000 epochs):\n";
$nn->train($X, $y, 1000, 1.0);

echo "\nPredictions:\n";
$pred = $nn->predict($X);
for ($i = 0; $i < 4; $i++) {
    echo "  [" . $X->data[$i][0] . "," . $X->data[$i][1] . "] → " . number_format($pred->data[$i][0], 4) . "\n";
}

echo "\n--- Linear Approximation ---\n";
$nn2 = new NeuralNetwork();
$nn2->addLayer(new NeuralLayer(1, 3, 'sigmoid'));
$nn2->addLayer(new NeuralLayer(3, 1, 'sigmoid'));

$X2 = new Matrix([[0.1], [0.3], [0.5], [0.7], [0.9]]);
$y2 = new Matrix([[0.2], [0.4], [0.6], [0.8], [1.0]]);

echo "Training (500 epochs):\n";
$nn2->train($X2, $y2, 500, 0.5);

echo "\nPredictions:\n";
$pred2 = $nn2->predict($X2);
for ($i = 0; $i < 5; $i++) {
    echo "  x=" . $X2->data[$i][0] . " → pred=" . number_format($pred2->data[$i][0], 4) . " (target=" . $y2->data[$i][0] . ")\n";
}

echo "\n--- Activation Functions ---\n";
$values = [-2, -1, 0, 1, 2];
echo "x\tsigmoid\trelu\ttanh\n";
foreach ($values as $x) {
    echo "$x\t" . number_format(Activation::sigmoid($x), 4) . "\t" . Activation::relu($x) . "\t" . number_format(Activation::tanh($x), 4) . "\n";
}

echo "\n--- Loss History (last 5) ---\n";
$hist = $nn->getLossHistory();
foreach (array_slice($hist, -5) as $i => $loss) {
    echo "  Epoch " . (count($hist) - 5 + $i) . ": $loss\n";
}

echo "=== f093 Done ===\n";
