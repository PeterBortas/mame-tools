#!/bin/bash

i=0
for x in benchresult/xeon_e5_2660/*result*; do
    i=$(( i+1 ))
    echo -ne "$i\r"
    if egrep -q 'GLIBCXX_3.4|CXXABI_1.3|libSDL2-2.0.so.0' $x; then
	rm -v $x
    fi
done
echo
