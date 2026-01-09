<?php
// 复杂嵌套测试
class ComplexObject {
    public $data = [];
    
    public function __construct() {
        $this->data = [
            "users" => [
                ["name" => "Alice", "age" => 30],
                ["name" => "Bob", "age" => 25]
            ],
            "settings" => [
                "theme" => "dark",
                "notifications" => true
            ]
        ];
    }
    
    public function process() {
        $result = [];
        foreach ($this->data["users"] as $user) {
            $result[] = [
                "name" => strtoupper($user["name"]),
                "age_group" => $user["age"] >= 30 ? "senior" : "junior"
            ];
        }
        return $result;
    }
}

$obj = new ComplexObject();
$processed = $obj->process();
echo "Processed data: ";
print_r($processed);
?>