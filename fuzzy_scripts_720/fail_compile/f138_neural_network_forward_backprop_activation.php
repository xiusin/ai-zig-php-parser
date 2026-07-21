<?php
// 极度混搭: 神经网络 + 前向传播 + 反向传播 + 激活函数 + 损失
echo "=== f138: Neural Network + Forward + Backprop + Activation ===\n";

class Matrix2D {
    public function __construct(public array $data) {}
    public function rows(): int { return count($this->data); }
    public function cols(): int { return count($this->data[0] ?? []); }

    public static function random(int $r, int $c, float $scale = 0.1): self {
        $data = [];
        for ($i = 0; $i < $r; $i++) {
            $row = [];
            for ($j = 0; $j < $c; $j++) $row[] = (mt_rand() / mt_getrandmax() - 0.5) * 2 * $scale;
            $data[] = $row;
        }
        return new self($data);
    }

    public function dot(Matrix2D $other): Matrix2D {
        $r = $this->rows(); $k = $this->cols(); $c = $other->cols();
        $result = array_fill(0, $r, array_fill(0, $c, 0.0));
        for ($i = 0; $i < $r; $i++)
            for ($j = 0; $j < $c; $j++) {
                $sum = 0;
                for ($m = 0; $m < $k; $m++) $sum += $this->data[$i][$m] * $other->data[$m][$j];
                $result[$i][$j] = $sum;
            }
        return new Matrix2D($result);
    }

    public function add(Matrix2D $other): Matrix2D {
        $result = [];
        for ($i = 0; $i < $this->rows(); $i++) {
            $row = [];
            for ($j = 0; $j < $this->cols(); $j++) $row[] = $this->data[$i][$j] + $other->data[$i][$j];
            $result[] = $row;
        }
        return new Matrix2D($result);
    }

    public function transpose(): Matrix2D {
        $result = [];
        for ($i = 0; $i < $this->cols(); $i++) {
            $row = [];
            for ($j = 0; $j < $this->rows(); $j++) $row[] = $this->data[$j][$i];
            $result[] = $row;
        }
        return new Matrix2D($result);
    }

    public function map(callable $fn): Matrix2D {
        $result = [];
        for ($i = 0; $i < $this->rows(); $i++) {
            $row = [];
            for ($j = 0; $j < $this->cols(); $j++) $row[] = $fn($this->data[$i][$j]);
            $result[] = $row;
        }
        return new Matrix2D($result);
    }

    public function multiply(Matrix2D $other): Matrix2D {
        $result = [];
        for ($i = 0; $i < $this->rows(); $i++) {
            $row = [];
            for ($j = 0; $j < $this->cols(); $j++) $row[] = $this->data[$i][$j] * $other->data[$i][$j];
            $result[] = $row;
        }
        return new Matrix2D($result);
    }

    public function scalarMul(float $s): Matrix2D { return $this->map(fn($v) => $v * $s); }
    public function scalarAdd(float $s): Matrix2D { return $this->map(fn($v) => $v + $s); }
}

class Activation {
    public static function sigmoid(float $x): float { return 1 / (1 + exp(-$x)); }
    public static function sigmoidDeriv(float $x): float { $s = self::sigmoid($x); return $s * (1 - $s); }
    public static function relu(float $x): float { return max(0, $x); }
    public static function reluDeriv(float $x): float { return $x > 0 ? 1 : 0; }
    public static function tanh(float $x): float { return tanh($x); }
    public static function tanhDeriv(float $x): float { $t = tanh($x); return 1 - $t * $t; }
    public static function softmax(array $arr): array {
        $max = max($arr);
        $exp = array_map(fn($x) => exp($x - $max), $arr);
        $sum = array_sum($exp);
        return array_map(fn($x) => $x / $sum, $exp);
    }
}

class NeuralLayer {
    public Matrix2D $weights;
    public Matrix2D $biases;
    public ?Matrix2D $lastInput = null;
    public ?Matrix2D $lastOutput = null;
    public ?Matrix2D $lastZ = null;

    public function __construct(public int $inputSize, public int $outputSize, public string $activation = 'sigmoid') {
        $this->weights = Matrix2D::random($inputSize, $outputSize, sqrt(2 / $inputSize));
        $this->biases = new Matrix2D(array_fill(0, 1, array_fill(0, $outputSize, 0.0)));
    }

    public function forward(Matrix2D $input): Matrix2D {
        $this->lastInput = $input;
        $z = $input->dot($this->weights)->add($this->biases->scalarMul(1));
        $this->lastZ = $z;
        $this->lastOutput = $z->map(match($this->activation) {
            'sigmoid' => [Activation::class, 'sigmoid'],
            'relu' => [Activation::class, 'relu'],
            'tanh' => [Activation::class, 'tanh'],
            default => fn($x) => $x,
        });
        return $this->lastOutput;
    }

    public function backward(Matrix2D $outputGrad, float $learningRate): Matrix2D {
        $activationDeriv = match($this->activation) {
            'sigmoid' => fn($z) => Activation::sigmoid($z) * (1 - Activation::sigmoid($z)),
            'relu' => fn($z) => $z > 0 ? 1.0 : 0.0,
            'tanh' => fn($z) => 1 - tanh($z) ** 2,
            default => fn($z) => 1.0,
        };
        $delta = $outputGrad->multiply($this->lastZ->map($activationDeriv));
        $inputGrad = $delta->dot($this->weights->transpose());
        $weightsGrad = $this->lastInput->transpose()->dot($delta);
        $this->weights = $this->weights->add($weightsGrad->scalarMul(-$learningRate));
        $biasGrad = new Matrix2D([array_fill(0, $this->outputSize, 0.0)]);
        for ($j = 0; $j < $this->outputSize; $j++) {
            $sum = 0;
            for ($i = 0; $i < $delta->rows(); $i++) $sum += $delta->data[$i][$j];
            $biasGrad->data[0][$j] = $sum;
        }
        $this->biases = $this->biases->add($biasGrad->scalarMul(-$learningRate));
        return $inputGrad;
    }
}

class NeuralNetwork {
    public array $layers = [];
    public array $lossHistory = [];

    public function __construct(array $layerSizes, array $activations = []) {
        for ($i = 0; $i < count($layerSizes) - 1; $i++) {
            $act = $activations[$i] ?? 'sigmoid';
            $this->layers[] = new NeuralLayer($layerSizes[$i], $layerSizes[$i + 1], $act);
        }
    }

    public function forward(Matrix2D $input): Matrix2D {
        $current = $input;
        foreach ($this->layers as $layer) $current = $layer->forward($current);
        return $current;
    }

    public function train(Matrix2D $input, Matrix2D $target, float $lr = 0.1, int $epochs = 100): void {
        for ($epoch = 0; $epoch < $epochs; $epoch++) {
            $output = $this->forward($input);
            // MSE loss: loss = (output - target)^2 / n
            $error = $output->add($target->scalarMul(-1));
            $loss = 0;
            for ($i = 0; $i < $error->rows(); $i++)
                for ($j = 0; $j < $error->cols(); $j++) $loss += $error->data[$i][$j] ** 2;
            $loss /= ($error->rows() * $error->cols());
            $this->lossHistory[] = $loss;
            // d(loss)/d(output) = 2 * (output - target) / n
            $outputGrad = $error->scalarMul(2 / ($error->rows() * $error->cols()));
            // Backpropagate
            $grad = $outputGrad;
            for ($i = count($this->layers) - 1; $i >= 0; $i--) {
                $grad = $this->layers[$i]->backward($grad, $lr);
            }
            if ($epoch % 20 === 0 || $epoch === $epochs - 1) {
                echo "  Epoch $epoch: loss=" . number_format($loss, 6) . "\n";
            }
        }
    }

    public function predict(Matrix2D $input): Matrix2D { return $this->forward($input); }

    public function accuracy(Matrix2D $input, Matrix2D $target): float {
        $output = $this->predict($input);
        $correct = 0;
        for ($i = 0; $i < $output->rows(); $i++) {
            $predicted = $output->data[$i][0] > 0.5 ? 1 : 0;
            $actual = $target->data[$i][0] > 0.5 ? 1 : 0;
            if ($predicted === $actual) $correct++;
        }
        return $correct / $output->rows();
    }
}

// 测试
echo "--- Activation Functions ---\n";
echo "sigmoid(0) = " . number_format(Activation::sigmoid(0), 4) . " (expected 0.5)\n";
echo "sigmoid(2) = " . number_format(Activation::sigmoid(2), 4) . "\n";
echo "relu(-1) = " . Activation::relu(-1) . ", relu(5) = " . Activation::relu(5) . "\n";
echo "tanh(0) = " . number_format(Activation::tanh(0), 4) . "\n";
echo "softmax([1,2,3]) = [" . implode(', ', array_map(fn($v) => number_format($v, 4), Activation::softmax([1, 2, 3]))) . "]\n";

echo "\n--- XOR Problem ---\n";
mt_srand(42);
$nn = new NeuralNetwork([2, 4, 1], ['sigmoid', 'sigmoid']);
$xorInput = new Matrix2D([[0, 0], [0, 1], [1, 0], [1, 1]]);
$xorTarget = new Matrix2D([[0], [1], [1], [0]]);
echo "Training XOR...\n";
$nn->train($xorInput, $xorTarget, 0.5, 500);
echo "Accuracy: " . number_format($nn->accuracy($xorInput, $xorTarget) * 100, 1) . "%\n";
echo "Predictions:\n";
$pred = $nn->predict($xorInput);
for ($i = 0; $i < 4; $i++) {
    $input = "[" . implode(',', $xorInput->data[$i]) . "]";
    echo "  $input → " . number_format($pred->data[$i][0], 4) . " (expected " . $xorTarget->data[$i][0] . ")\n";
}

echo "\n--- Loss History ---\n";
echo "Initial loss: " . number_format($nn->lossHistory[0] ?? 0, 6) . "\n";
echo "Final loss: " . number_format(end($nn->lossHistory), 6) . "\n";
echo "Loss decrease: " . number_format(($nn->lossHistory[0] - end($nn->lossHistory)) / $nn->lossHistory[0] * 100, 1) . "%\n";

echo "\n--- Binary Classification (OR) ---\n";
$nn2 = new NeuralNetwork([2, 3, 1], ['relu', 'sigmoid']);
$orInput = new Matrix2D([[0, 0], [0, 1], [1, 0], [1, 1]]);
$orTarget = new Matrix2D([[0], [1], [1], [1]]);
echo "Training OR...\n";
$nn2->train($orInput, $orTarget, 0.3, 300);
echo "Accuracy: " . number_format($nn2->accuracy($orInput, $orTarget) * 100, 1) . "%\n";

echo "\n--- AND Problem ---\n";
$nn3 = new NeuralNetwork([2, 3, 1], ['sigmoid', 'sigmoid']);
$andInput = new Matrix2D([[0, 0], [0, 1], [1, 0], [1, 1]]);
$andTarget = new Matrix2D([[0], [0], [0], [1]]);
echo "Training AND...\n";
$nn3->train($andInput, $andTarget, 0.5, 300);
echo "Accuracy: " . number_format($nn3->accuracy($andInput, $andTarget) * 100, 1) . "%\n";

echo "\n--- Regression (Linear) ---\n";
$nn4 = new NeuralNetwork([1, 1], ['linear']);
mt_srand(100);
$regInput = new Matrix2D([[1], [2], [3], [4], [5]]);
$regTarget = new Matrix2D([[2.1], [3.9], [6.1], [8.0], [9.9]]);
echo "Training y ≈ 2x...\n";
$nn4->train($regInput, $regTarget, 0.01, 500);
echo "Predictions:\n";
$regPred = $nn4->predict($regInput);
for ($i = 0; $i < 5; $i++) echo "  x={$regInput->data[$i][0]} → pred=" . number_format($regPred->data[$i][0], 2) . " (expected {$regTarget->data[$i][0]})\n";

echo "\n--- Matrix Operations ---\n";
$A = Matrix2D::random(2, 3, 1);
$B = Matrix2D::random(3, 2, 1);
echo "A (2x3):\n";
for ($i = 0; $i < 2; $i++) echo "  [" . implode(', ', array_map(fn($v) => number_format($v, 4), $A->data[$i])) . "]\n";
echo "B (3x2):\n";
for ($i = 0; $i < 3; $i++) echo "  [" . implode(', ', array_map(fn($v) => number_format($v, 4), $B->data[$i])) . "]\n";
$C = $A->dot($B);
echo "A·B (2x2):\n";
for ($i = 0; $i < 2; $i++) echo "  [" . implode(', ', array_map(fn($v) => number_format($v, 4), $C->data[$i])) . "]\n";
$At = $A->transpose();
echo "A^T (3x2):\n";
for ($i = 0; $i < 3; $i++) echo "  [" . implode(', ', array_map(fn($v) => number_format($v, 4), $At->data[$i])) . "]\n";

echo "=== f138 Done ===\n";
