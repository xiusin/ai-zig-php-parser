<?php
// 极度混搭: 数字信号处理 + FFT + 滤波 + 卷积 + 频谱分析
echo "=== f148: DSP + FFT + Filter + Convolution + Spectrum ===\n";

class DSP {
    public static function fft(array $data): array {
        $n = count($data);
        if ($n <= 1) return $data;
        // 确保2的幂
        if (($n & ($n - 1)) !== 0) {
            $nextPow = 1;
            while ($nextPow < $n) $nextPow *= 2;
            while (count($data) < $nextPow) $data[] = 0;
            $n = $nextPow;
        }
        return self::cooleyTukey($data);
    }

    private static function cooleyTukey(array $data): array {
        $n = count($data);
        if ($n <= 1) return $data;
        $even = []; $odd = [];
        for ($i = 0; $i < $n; $i += 2) { $even[] = $data[$i]; $odd[] = $data[$i + 1]; }
        $evenFFT = self::cooleyTukey($even);
        $oddFFT = self::cooleyTukey($odd);
        $result = array_fill(0, $n, ['re' => 0, 'im' => 0]);
        for ($k = 0; $k < $n / 2; $k++) {
            $angle = -2 * M_PI * $k / $n;
            $tRe = cos($angle) * $oddFFT[$k]['re'] - sin($angle) * $oddFFT[$k]['im'];
            $tIm = cos($angle) * $oddFFT[$k]['im'] + sin($angle) * $oddFFT[$k]['re'];
            $result[$k] = ['re' => $evenFFT[$k]['re'] + $tRe, 'im' => $evenFFT[$k]['im'] + $tIm];
            $result[$k + $n / 2] = ['re' => $evenFFT[$k]['re'] - $tRe, 'im' => $evenFFT[$k]['im'] - $tIm];
        }
        return $result;
    }

    public static function magnitude(array $fftResult): array {
        return array_map(fn($c) => sqrt($c['re'] ** 2 + $c['im'] ** 2), $fftResult);
    }

    public static function phase(array $fftResult): array {
        return array_map(fn($c) => atan2($c['im'], $c['re']), $fftResult);
    }

    public static function convolution(array $signal, array $kernel): array {
        $n = count($signal); $m = count($kernel);
        $result = array_fill(0, $n + $m - 1, 0);
        for ($i = 0; $i < $n; $i++) {
            for ($j = 0; $j < $m; $j++) {
                $result[$i + $j] += $signal[$i] * $kernel[$j];
            }
        }
        return $result;
    }

    public static function lowPassFilter(array $signal, float $cutoff, float $sampleRate = 44100): array {
        $rc = 1 / (2 * M_PI * $cutoff);
        $dt = 1 / $sampleRate;
        $alpha = $dt / ($rc + $dt);
        $result = [$signal[0]];
        for ($i = 1; $i < count($signal); $i++) {
            $result[] = $result[$i - 1] + $alpha * ($signal[$i] - $result[$i - 1]);
        }
        return $result;
    }

    public static function highPassFilter(array $signal, float $cutoff, float $sampleRate = 44100): array {
        $rc = 1 / (2 * M_PI * $cutoff);
        $dt = 1 / $sampleRate;
        $alpha = $rc / ($rc + $dt);
        $result = [$signal[0]];
        for ($i = 1; $i < count($signal); $i++) {
            $result[] = $alpha * ($result[$i - 1] + $signal[$i] - $signal[$i - 1]);
        }
        return $result;
    }

    public static function movingAverage(array $signal, int $window): array {
        $result = [];
        for ($i = 0; $i < count($signal); $i++) {
            $sum = 0; $count = 0;
            for ($j = max(0, $i - (int)($window / 2)); $j <= min(count($signal) - 1, $i + (int)($window / 2)); $j++) {
                $sum += $signal[$j]; $count++;
            }
            $result[] = $sum / $count;
        }
        return $result;
    }

    public static function generateSineWave(float $freq, float $duration, float $sampleRate = 44100, float $amplitude = 1.0): array {
        $samples = (int)($duration * $sampleRate);
        $signal = [];
        for ($i = 0; $i < $samples; $i++) {
            $signal[] = $amplitude * sin(2 * M_PI * $freq * $i / $sampleRate);
        }
        return $signal;
    }

    public static function generateSineWaveShort(float $freq, int $samples, float $amplitude = 1.0): array {
        $signal = [];
        for ($i = 0; $i < $samples; $i++) $signal[] = $amplitude * sin(2 * M_PI * $freq * $i / 100);
        return $signal;
    }

    public static function mixSignals(array ...$signals): array {
        $maxLen = max(array_map('count', $signals));
        $result = array_fill(0, $maxLen, 0);
        foreach ($signals as $signal) {
            for ($i = 0; $i < count($signal); $i++) $result[$i] += $signal[$i];
        }
        return $result;
    }

    public static function rms(array $signal): float {
        if (empty($signal)) return 0;
        return sqrt(array_sum(array_map(fn($s) => $s * $s, $signal)) / count($signal));
    }

    public static function peak(array $signal): float { return empty($signal) ? 0 : max(array_map('abs', $signal)); }
    public static function mean(array $signal): float { return empty($signal) ? 0 : array_sum($signal) / count($signal); }

    public static function autoCorrelate(array $signal): array {
        $n = count($signal);
        $result = array_fill(0, $n, 0);
        for ($lag = 0; $lag < $n; $lag++) {
            $sum = 0;
            for ($i = 0; $i < $n - $lag; $i++) $sum += $signal[$i] * $signal[$i + $lag];
            $result[$lag] = $sum / $n;
        }
        return $result;
    }

    public static function powerSpectrum(array $signal): array {
        $fft = self::fft($signal);
        $mag = self::magnitude($fft);
        return array_map(fn($m) => $m * $m / count($signal), $mag);
    }
}

// 测试
echo "--- Sine Wave Generation ---\n";
$sine440 = DSP::generateSineWaveShort(440, 256);
echo "440Hz sine wave: " . count($sine440) . " samples\n";
echo "RMS: " . number_format(DSP::rms($sine440), 4) . " (expected ~0.707)\n";
echo "Peak: " . number_format(DSP::peak($sine440), 4) . "\n";
echo "Mean: " . number_format(DSP::mean($sine440), 6) . " (expected ~0)\n";

echo "\n--- FFT ---\n";
$sine8 = DSP::generateSineWaveShort(8, 64);
$fft = DSP::fft($sine8);
$mags = DSP::magnitude($fft);
echo "FFT of 8Hz sine (64 samples):\n";
echo "Top 5 magnitudes: " . implode(', ', array_map(fn($i, $m) => "bin$i=" . number_format($m, 2), array_keys(array_slice($mags, 0, 5, true)), array_slice($mags, 0, 5))) . "\n";
$peakBin = array_search(max($mags), $mags);
echo "Peak at bin: $peakBin (frequency: " . ($peakBin * 100 / 64) . "Hz)\n";

echo "\n--- Power Spectrum ---\n";
$spectrum = DSP::powerSpectrum($sine8);
echo "Power spectrum (first 8 bins):\n";
for ($i = 0; $i < 8; $i++) {
    $bar = str_repeat('█', (int)($spectrum[$i] * 100));
    echo "  bin $i: " . number_format($spectrum[$i], 4) . " $bar\n";
}

echo "\n--- Convolution ---\n";
$signal = [1, 2, 3, 4, 5, 6, 7, 8];
$kernel = [0.25, 0.5, 0.25]; // Smoothing kernel
$conv = DSP::convolution($signal, $kernel);
echo "Signal: [" . implode(', ', $signal) . "]\n";
echo "Kernel: [" . implode(', ', $kernel) . "]\n";
echo "Convolution: [" . implode(', ', array_map(fn($v) => number_format($v, 2), $conv)) . "]\n";

echo "\n--- Low-Pass Filter ---\n";
$noise = [];
mt_srand(42);
for ($i = 0; $i < 50; $i++) $noise[] = sin(2 * M_PI * 5 * $i / 50) + (mt_rand() / mt_getrandmax() - 0.5) * 0.5;
$filtered = DSP::lowPassFilter($noise, 10, 50);
echo "Noisy signal RMS: " . number_format(DSP::rms($noise), 4) . "\n";
echo "Filtered signal RMS: " . number_format(DSP::rms($filtered), 4) . "\n";
echo "Noise reduction: " . number_format((1 - DSP::rms($filtered) / DSP::rms($noise)) * 100, 1) . "%\n";

echo "\n--- High-Pass Filter ---\n";
$hpFiltered = DSP::highPassFilter($noise, 5, 50);
echo "High-pass RMS: " . number_format(DSP::rms($hpFiltered), 4) . "\n";

echo "\n--- Moving Average ---\n";
$data = [1, 3, 2, 4, 3, 5, 4, 6, 5, 7];
$smoothed = DSP::movingAverage($data, 3);
echo "Original: [" . implode(', ', $data) . "]\n";
echo "Smoothed: [" . implode(', ', array_map(fn($v) => number_format($v, 1), $smoothed)) . "]\n";

echo "\n--- Signal Mixing ---\n";
$sig1 = DSP::generateSineWaveShort(4, 64, 0.5);
$sig2 = DSP::generateSineWaveShort(8, 64, 0.3);
$mixed = DSP::mixSignals($sig1, $sig2);
echo "Signal 1 RMS: " . number_format(DSP::rms($sig1), 4) . "\n";
echo "Signal 2 RMS: " . number_format(DSP::rms($sig2), 4) . "\n";
echo "Mixed RMS: " . number_format(DSP::rms($mixed), 4) . "\n";
$mixedSpectrum = DSP::powerSpectrum($mixed);
$topBins = $mixedSpectrum;
arsort($topBins);
echo "Top frequency bins:\n";
$i = 0;
foreach ($topBins as $bin => $power) {
    if ($i++ >= 5) break;
    echo "  bin $bin: " . number_format($power, 4) . " (freq: " . ($bin * 100 / 64) . "Hz)\n";
}

echo "\n--- Auto-Correlation ---\n";
$periodic = DSP::generateSineWaveShort(4, 64);
$autocorr = DSP::autoCorrelate($periodic);
echo "Auto-correlation peaks (first 16 lags):\n";
for ($i = 0; $i < 16; $i++) {
    $bar = str_repeat('█', max(0, (int)($autocorr[$i] * 20)));
    echo "  lag $i: " . number_format($autocorr[$i], 4) . " $bar\n";
}

echo "\n--- Phase Analysis ---\n";
$phases = DSP::phase($fft);
echo "Phase (first 8 bins):\n";
for ($i = 0; $i < 8; $i++) echo "  bin $i: " . number_format($phases[$i], 4) . " rad (" . number_format(rad2deg($phases[$i]), 1) . "°)\n";

echo "=== f148 Done ===\n";
