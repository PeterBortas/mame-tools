# **mame-tools** #

Tools used to build, benchmark and test [Mame](https://github.com/mamedev/mame)

**WARNING**: Do not use your development checkout pf Mame to run these
scripts. They will irrevocably delete any local changes. Make sure you
run these builds in a checkout dedicated for this purpose.

Compiling Mame (lots and lots of Mames)
=======================================

To compile a set of all tagged mame releases, check out Mame into a
directory named "mame" and run "build-all-tags.sh" from that
directory. Example:

```
cd /mametest
git clone https://github.com/PeterBortas/mame-tools.git
mkdir /mametest/arch/$(uname -m)-$(getconf LONG_BIT)
cd /mametest/arch/$(uname -m)-$(getconf LONG_BIT)
git clone https://github.com/mamedev/mame.git
cd mame
/mametest/mame-tools/build-all-tags.sh
```

With a modern computer you can go to bed and have this done by the
morning, but using a Raspberry Pi 4 expect 4-6h per build for a total
time of weeks.

Running benchmarks
==================
TODO: Describe
NOTE: Has a hard dependency on some dirs in /mametest existing

Producing a HTML report from a selection of benchmarks
======================================================
TODO: Describe

Coverity
========
TODO: Describe
