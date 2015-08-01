#!/bin/bash

ctags -R --langmap=c++:+.cu --c++-kinds=+p --fields=+iaS --extra=+q .

