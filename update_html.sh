#!/bin/bash

# usage

PREVIEW=1
COMMIT=0

IO=$HOME/patpatbear.github.io

find . -name '*.md' | xargs basename -s .md | xargs -I{} pandoc {}.md -s -o $IO/{}.html

if [ x"$PREVIEW" = x1 ]; then
    firefox $IO/index.html >/dev/null 2>&1 &
fi

if [ x"$COMMIT" = x1 ]; then
    cd $IO
    git add --all .
    git commit -m "update-`date +%F`"
    git push origin master
fi
