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

If any romsets are available, put them in /mametest/<mame version>.
```
$ ls -d /mametest/roms/0.2*
/mametest/roms/0.212  /mametest/roms/0.213
```

Run setup to create //games.lst// and download roms if needed:
```
cd /mametest/mame-tools/bench
./prepare_games.sh
```

For games that need preparation before they can be started
run //make_initial_state.sh <game>// and do whatever steps are
needed. For some games those steps are documented in bench/README.txt.

This can be done on a different system/architechture than the
benchmarks are run on. This state can later be cloned and tested by
running //test_game.sh <mame version> <game>// and will automatically
be picked up and cloned when running benchmarks.
```
./make_initial_state.sh sfiii
./test_game.sh 0.212 sfiii
```

For running on Raspberry Pi, first make an initial run and check that
it work and produces results. The initial run will install a crontab
that tries to resume the benchmark if it's ever stopped halfway. When
you are satisfied things are working you can ^C the interactive
benchmark and let the Pi take care of the rest in the background. Note
that the benchmark will reboot the Pi any time it is throttled in any
way to clear the throttling flags. Any future benchmarks can be
started by setting up a queue:

```
./pi_resumable_benchmark.sh 0.212
^C
for x in 0.{176..213}; do
    echo $x >> runstate/queue
done
echo 0.175 > runstate/CURRENT_VERSION
```

When running on other (much faster) platforms no special tricks are
used; no crontab, no reboots, no runtime monitoring of temperature and
throttling, and there is no queue. Just run the benchmark with the
version to test:

```
./resumable_benchmark.sh 0.212
./resumable_benchmark.sh 0.213
```

The benchmark is still resumable if it's aborted for some reason.

Producing a HTML report from a selection of benchmarks
======================================================

Requirement: Pike 7.8+

```
cd /mametest/mame-tools/bench/graph
./create_graph.pike
```

The result found in output/ can be viewed in a web browser either from
the local filesystem or when uploaded to a web-server.

Coverity
========
The coverity/ directory contains helper scripts for building and
analyzing Mame with Coverity Scan.
