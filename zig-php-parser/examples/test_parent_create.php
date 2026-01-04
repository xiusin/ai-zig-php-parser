<?php
class Base {
    private string $name;
    
    public function __construct(string $name) {
        $this->name = $name;
    }
}

class Child extends Base {
    private string $job;
    private string $city;
    
    public function __construct(string $name, string $job, string $city) {
        parent::__construct($name);
        $this->job = $job;
        $this->city = $city;
    }
}

echo "Before creating object\n";
$c = new Child("Charlie", "Engineer", "NYC");
echo "Object created\n";
?>
