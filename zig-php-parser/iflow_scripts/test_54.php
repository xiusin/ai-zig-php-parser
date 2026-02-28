<?php

class Person {
    public \$name;
    public function __construct(\$name) {
        \$this->name = \$name;
    }
}
\$p = new Person("John");
echo \$p->name;

?>
