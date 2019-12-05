#!/bin/bash

# 0.{156..160} {167..201}
# 0.203+ can run without an OpenGL context
for ver in 0.{216..203}; do
    sbatch -J bch$ver clusterbench.sh $ver
done
