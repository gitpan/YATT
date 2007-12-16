#!/bin/zsh

set -e

cd $0:h

if ((ARGC)); then
    files=("$@")
else
    files=(*.t(N))
fi

perl -MTest::Harness -e 'runtests(@ARGV)' $files
