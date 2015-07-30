#!/bin/bash

arr=(
[KEY]=value
)

. ./utils/parse_options.sh

echo ${arr[KEY]}
