<?php
function celsiusToFahrenheit(float $celsius): float {
    return ($celsius * 9 / 5) + 32;
}

function fahrenheitToCelsius(float $fahrenheit): float {
    return ($fahrenheit - 32) * 5 / 9;
}

function celsiusToKelvin(float $celsius): float {
    return $celsius + 273.15;
}

function kelvinToCelsius(float $kelvin): float {
    return $kelvin - 273.15;
}

function fahrenheitToKelvin(float $fahrenheit): float {
    return celsiusToKelvin(fahrenheitToCelsius($fahrenheit));
}

function kelvinToFahrenheit(float $kelvin): float {
    return celsiusToFahrenheit(kelvinToCelsius($kelvin));
}

echo sprintf("%.2f\n", celsiusToFahrenheit(0));
echo sprintf("%.2f\n", fahrenheitToCelsius(32));
echo sprintf("%.2f\n", celsiusToKelvin(100));
echo sprintf("%.2f\n", kelvinToFahrenheit(300));
echo "OK\n";
