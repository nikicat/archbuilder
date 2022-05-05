#!/bin/sh -e

echo "MAKEFLAGS='$MAKEFLAGS'" | sudo tee -a /etc/makepkg.conf >/dev/null
sudo chown builduser /build
exec 3>&1 4>&2
TIMEFORMAT=%P
util=$({ time tr "\0" "\n" < /dev/zero | yay --answerclean A --answerdiff N -Sy --skipinstall --builddir /build "$@" 1>&3 2>&4 ; } 2>&1)
cores=$(nproc --all)
relutil=$(echo "scale=1;$util/$cores" | bc)
echo "CPU utilization: ${relutil}%"
sudo mkdir /packages
sudo cp -a /build/*/*.pkg.tar.zst /packages
