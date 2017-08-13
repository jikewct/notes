#!/bin/bash

find . -name '*.md' | xargs basename -s .md | xargs -I{} pandoc {}.md -s -o $HOME/notes_html/{}.html
