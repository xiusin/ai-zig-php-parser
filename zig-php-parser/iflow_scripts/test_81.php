<?php

\$x = 10;
\$add = function(\$y) use (\$x) {
    return \$x + \$y;
};
echo \$add(5);

?>
