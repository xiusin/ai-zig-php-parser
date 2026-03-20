<?php
function metersToFeet(float $meters): float {
    return $meters * 3.28084;
}

function feetToMeters(float $feet): float {
    return $feet / 3.28084;
}

function kilogramsToPounds(float $kg): float {
    return $kg * 2.20462;
}

function poundsToKilograms(float $lb): float {
    return $lb / 2.20462;
}

function litersToGallons(float $liters): float {
    return $liters * 0.264172;
}

function gallonsToLiters(float $gallons): float {
    return $gallons / 0.264172;
}

function kmToMiles(float $km): float {
    return $km * 0.621371;
}

function milesToKm(float $miles): float {
    return $miles / 0.621371;
}

echo sprintf("%.2f\n", metersToFeet(1));
echo sprintf("%.2f\n", kilogramsToPounds(70));
echo sprintf("%.2f\n", litersToGallons(10));
echo sprintf("%.2f\n", kmToMiles(100));
echo "OK\n";
