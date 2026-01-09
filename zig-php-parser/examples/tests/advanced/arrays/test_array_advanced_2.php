<?php
$data = array(
    array("name" => "Alice", "age" => 30, "city" => "New York"),
    array("name" => "Bob", "age" => 25, "city" => "Los Angeles"),
    array("name" => "Charlie", "age" => 35, "city" => "New York"),
    array("name" => "Diana", "age" => 28, "city" => "Chicago")
);

// 按年龄排序
usort($data, function($a, $b) { return $a["age"] - $b["age"]; });
echo "Sorted by age:\n";
print_r($data);

// 按城市分组
$grouped = array();
foreach ($data as $person) {
    $city = $person["city"];
    if (!isset($grouped[$city])) {
        $grouped[$city] = array();
    }
    $grouped[$city][] = $person;
}
echo "\nGrouped by city:\n";
print_r($grouped);

// 提取名称
$names = array_column($data, "name");
echo "\nNames: " . implode(", ", $names) . "\n";
?>