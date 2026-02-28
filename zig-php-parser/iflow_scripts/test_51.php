<?php

class Foo {
    public \$x = 10;
    public function getX() {
        return \$this->x;
    }
}
\$obj = new Foo();
echo \$obj->getX();

?>
