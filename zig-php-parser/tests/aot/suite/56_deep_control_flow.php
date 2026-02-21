<?php
$sum = 0;
for ($i = 0; $i < 6; $i++) {
    if ($i == 1) {
        continue;
    } elseif ($i == 4) {
        break;
    } else {
        $j = 0;
        while ($j < 2) {
            if (($i + $j) % 2 == 0) {
                $sum += $i + $j;
            } else {
                $sum += 1;
            }
            $j++;
        }
    }
}
echo "DeepCF: $sum (expect 9)\n";
