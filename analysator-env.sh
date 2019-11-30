case $COMP_CC in
gcc-9)
	source /home/zino/local/gcc/9.2.0/bin/setenv-for-gcc920.sh
	export PATH=$HOME/local/bin:$PATH
	;;
gcc-8)
	module load GCC/8.2.0-2.31.1
	export PATH=$HOME/mame-stuff/mame-tools/wabin:$HOME/local/bin:$PATH
	;;
*)
	echo "Unsupported compiler: $COMP_CC"
	return 1
esac
