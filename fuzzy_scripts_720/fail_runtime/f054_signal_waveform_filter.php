<?php
// 极度混搭: 信号处理 + 波形生成 + 简易FFT + 频率分析 + 数字滤波
echo "=== f054: Signal Processing + Waveform + FFT ===\n";

class Waveform {
    public static function sine(float $freq, float $duration, int $sampleRate = 100): array {
        $samples = [];
        $n = (int)($duration * $sampleRate);
        for ($i = 0; $i < $n; $i++) {
            $t = $i / $sampleRate;
            $samples[] = sin(2 * M_PI * $freq * $t);
        }
        return $samples;
    }

    public static function square(float $freq, float $duration, int $sr = 100): array {
        $samples = [];
        $n = (int)($duration * $sr);
        for ($i = 0; $i < $n; $i++) {
            $t = $i / $sr;
            $phase = 2 * M_PI * $freq * $t;
            $samples[] = sin($phase) >= 0 ? 1.0 : -1.0;
        }
        return $samples;
    }

    public static function sawtooth(float $freq, float $duration, int $sr = 100): array {
        $samples = [];
        $n = (int)($duration * $sr);
        for ($i = 0; $i < $n; $i++) {
            $t = $i / $sr;
            $period = 1 / $freq;
            $samples[] = 2 * ($t / $period - floor($t / $period + 0.5));
        }
        return $samples;
    }

    public static function noise(float $duration, int $sr = 100, int $seed = 42): array {
        mt_srand($seed);
        $samples = [];
        $n = (int)($duration * $sr);
        for ($i = 0; $i < $n; $i++) {
            $samples[] = (mt_rand() / mt_getrandmax()) * 2 - 1;
        }
        return $samples;
    }

    public static function mix(array ...$signals): array {
        $maxLen = max(array_map('count', $signals));
        $result = array_fill(0, $maxLen, 0.0);
        foreach ($signals as $sig) {
            for ($i = 0; $i < count($sig); $i++) {
                $result[$i] += $sig[$i];
            }
        }
        return array_map(fn($v) => $v / count($signals), $result);
    }
}

class DigitalFilter {
    public static function movingAverage(array $signal, int $window = 3): array {
        $result = [];
        $n = count($signal);
        for ($i = 0; $i < $n; $i++) {
            $sum = 0; $count = 0;
            for ($j = max(0, $i - $window + 1); $j <= $i; $j++) {
                $sum += $signal[$j];
                $count++;
            }
            $result[] = $sum / $count;
        }
        return $result;
    }

    public static function lowPass(array $signal, float $alpha = 0.5): array {
        $result = [$signal[0]];
        for ($i = 1; $i < count($signal); $i++) {
            $result[] = $alpha * $signal[$i] + (1 - $alpha) * $result[$i - 1];
        }
        return $result;
    }

    public static function highPass(array $signal, float $alpha = 0.5): array {
        $result = [0.0];
        for ($i = 1; $i < count($signal); $i++) {
            $result[] = $alpha * ($result[$i - 1] + $signal[$i] - $signal[$i - 1]);
        }
        return $result;
    }

    public static function medianFilter(array $signal, int $window = 3): array {
        $result = [];
        $n = count($signal);
        for ($i = 0; $i < $n; $i++) {
            $windowData = array_slice($signal, max(0, $i - (int)($window/2)), $window);
            if (count($windowData) < $window && $i < (int)($window/2)) {
                $pad = array_fill(0, $window - count($windowData), 0.0);
                $windowData = array_merge($pad, $windowData);
            }
            sort($windowData);
            $result[] = $windowData[(int)(count($windowData) / 2)];
        }
        return $result;
    }
}

class SignalAnalysis {
    public static function mean(array $sig): float {
        return array_sum($sig) / count($sig);
    }

    public static function rms(array $sig): float {
        return sqrt(array_sum(array_map(fn($x) => $x * $x, $sig)) / count($sig));
    }

    public static function peak(array $sig): float {
        $max = max($sig); $min = min($sig);
        return max(abs($max), abs($min));
    }

    public static function zeroCrossings(array $sig): int {
        $count = 0;
        for ($i = 1; $i < count($sig); $i++) {
            if (($sig[$i-1] >= 0) !== ($sig[$i] >= 0)) $count++;
        }
        return $count;
    }

    public static function autocorrelation(array $sig, int $lag = 0): float {
        $mean = self::mean($sig);
        $n = count($sig);
        $num = 0; $den = 0;
        for ($i = 0; $i < $n - $lag; $i++) {
            $num += ($sig[$i] - $mean) * ($sig[$i + $lag] - $mean);
        }
        for ($i = 0; $i < $n; $i++) {
            $den += ($sig[$i] - $mean) ** 2;
        }
        return $den == 0 ? 0 : $num / $den;
    }

    public static function formatSamples(array $sig, int $max = 20): string {
        $slice = array_slice($sig, 0, min($max, count($sig)));
        return "[" . implode(', ', array_map(fn($v) => number_format($v, 3), $slice)) . "]";
    }
}

// 测试
echo "--- Waveform Generation ---\n";
$sine = Waveform::sine(5, 0.2, 50);
$square = Waveform::square(5, 0.2, 50);
$saw = Waveform::sawtooth(5, 0.2, 50);
echo "Sine (5Hz, 0.2s, 10 samples): " . SignalAnalysis::formatSamples(array_slice($sine, 0, 10)) . "\n";
echo "Square (5Hz, 0.2s, 10 samples): " . SignalAnalysis::formatSamples(array_slice($square, 0, 10)) . "\n";
echo "Sawtooth (5Hz, 0.2s, 10 samples): " . SignalAnalysis::formatSamples(array_slice($saw, 0, 10)) . "\n";

$mixed = Waveform::mix($sine, $square);
echo "Mixed (sine+square, 10 samples): " . SignalAnalysis::formatSamples(array_slice($mixed, 0, 10)) . "\n";

echo "\n--- Analysis ---\n";
echo "Sine mean: " . number_format(SignalAnalysis::mean($sine), 4) . "\n";
echo "Sine RMS: " . number_format(SignalAnalysis::rms($sine), 4) . "\n";
echo "Sine peak: " . number_format(SignalAnalysis::peak($sine), 4) . "\n";
echo "Sine zero crossings: " . SignalAnalysis::zeroCrossings($sine) . "\n";
echo "Sine autocorr(lag=0): " . number_format(SignalAnalysis::autocorrelation($sine, 0), 4) . "\n";
echo "Sine autocorr(lag=5): " . number_format(SignalAnalysis::autocorrelation($sine, 5), 4) . "\n";

echo "\n--- Digital Filters ---\n";
$noisy = Waveform::mix($sine, Waveform::noise(0.2, 50, 123));
echo "Noisy (10 samples): " . SignalAnalysis::formatSamples(array_slice($noisy, 0, 10)) . "\n";

$avg = DigitalFilter::movingAverage($noisy, 5);
echo "Moving avg (window=5): " . SignalAnalysis::formatSamples(array_slice($avg, 0, 10)) . "\n";

$lp = DigitalFilter::lowPass($noisy, 0.3);
echo "Low pass (alpha=0.3): " . SignalAnalysis::formatSamples(array_slice($lp, 0, 10)) . "\n";

$hp = DigitalFilter::highPass($noisy, 0.5);
echo "High pass (alpha=0.5): " . SignalAnalysis::formatSamples(array_slice($hp, 0, 10)) . "\n";

$med = DigitalFilter::medianFilter($noisy, 5);
echo "Median (window=5): " . SignalAnalysis::formatSamples(array_slice($med, 0, 10)) . "\n";

echo "\n--- Filter Comparison (RMS) ---\n";
echo "Original sine RMS: " . number_format(SignalAnalysis::rms($sine), 4) . "\n";
echo "Noisy RMS: " . number_format(SignalAnalysis::rms($noisy), 4) . "\n";
echo "Avg filter RMS: " . number_format(SignalAnalysis::rms($avg), 4) . "\n";
echo "LowPass RMS: " . number_format(SignalAnalysis::rms($lp), 4) . "\n";
echo "HighPass RMS: " . number_format(SignalAnalysis::rms($hp), 4) . "\n";
echo "Median RMS: " . number_format(SignalAnalysis::rms($med), 4) . "\n";

echo "=== f054 Done ===\n";
