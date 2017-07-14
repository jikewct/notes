#!/bin/python
import yaml

stream = file('/home/srzhao/work/clogs/test/server/plugin/data/8583-cups.yml', 'r')

for event in yaml.parse(stream):
    print event
