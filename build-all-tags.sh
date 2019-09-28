#!/bin/bash

# NOTE: This script will permanently murder local changes in the mame
#       checkout it's run

# Checks out all tagged Mame releases one by one, builds them and
# stores the resulting dist. Alternatively call with a specific tag to
# build and store that.

shopt -s nullglob  # Do not return the glob itself if no files matches

ZTOOLDIR="$(dirname $0)"
source ${ZTOOLDIR}/functions.sh

# Bail if CWD isn't a mame git checkout
verify_mame_checkout 

# drop any diffs caused by applying patches
function cleanup_patches {
    if git diff-index --quiet HEAD --; then
	echo "NOTE: No git state to clean up"
    else
	echo "NOTE: Removing applied patches"
	git stash
	git stash drop
    fi
}

if [ -z "$1" ]; then
    # List all tags but remove the "u" versions
    # TODO: Either build them all or maybe just the last u-version?
    tags="$(git tag | grep -v u | sort -r)" 
else
    # Allow specific tag to be build
    tags="$1"
fi

for tag in $tags; do
    verify_free_disk 4000000 # Require some minimum free space on the disk
    echo -e "\033[0;32mChecking out and building tag $tag\033[0m"
    git checkout $tag || exit 1
    git clean -dfqx # this will murder local changes
    make clean # not needed with the above, but...
    if [ ! -f dist.mak ]; then
	echo "WARNING: No dist.mak, using one based on mame0211"
	cp -v "$ZTOOLDIR/missing/dist.mak" .
    fi
    "$ZTOOLDIR/one-build-and-store.sh"
    cleanup_patches
done
