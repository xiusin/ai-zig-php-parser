<?php
function areaOfCircle(float $radius): float {
    return M_PI * $radius * $radius;
}

function circumference(float $radius): float {
    return 2 * M_PI * $radius;
}

function areaOfRectangle(float $width, float $height): float {
    return $width * $height;
}

function perimeterOfRectangle(float $width, float $height): float {
    return 2 * ($width + $height);
}

function areaOfTriangle(float $base, float $height): float {
    return 0.5 * $base * $height;
}

function volumeOfSphere(float $radius): float {
    return (4/3) * M_PI * pow($radius, 3);
}

function volumeOfCube(float $side): float {
    return pow($side, 3);
}

echo sprintf("%.2f\n", areaOfCircle(5));
echo sprintf("%.2f\n", circumference(5));
echo areaOfRectangle(4, 6) . "\n";
echo perimeterOfRectangle(4, 6) . "\n";
echo areaOfTriangle(6, 4) . "\n";
echo sprintf("%.2f\n", volumeOfSphere(3));
echo volumeOfCube(3) . "\n";
echo "OK\n";
