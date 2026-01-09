<?php
$people = [
    ["name" => "Alice", "age" => 25, "city" => "NYC"],
    ["name" => "Bob", "age" => 30, "city" => "LA"],
    ["name" => "Charlie", "age" => 25, "city" => "NYC"],
    ["name" => "Diana", "age" => 30, "city" => "LA"],
    ["name" => "Eve", "age" => 35, "city" => "NYC"],
];

// Group by age
$byAge = [];
foreach ($people as $person) {
    $age = $person["age"];
    if (!isset($byAge[$age])) {
        $byAge[$age] = [];
    }
    $byAge[$age][] = $person["name"];
}

echo "By age:\n";
foreach ($byAge as $age => $names) {
    echo "  Age $age: " . implode(", ", $names) . "\n";
}
