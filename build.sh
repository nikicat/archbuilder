#!/bin/sh -e

echo "MAKEFLAGS='$MAKEFLAGS'" | sudo tee -a /etc/makepkg.conf >/dev/null
sudo chown builduser /build
exec 3>&1 4>&2
TIMEFORMAT=%P%%
time=$({ time tr "\0" "\n" < /dev/zero | yay --answerclean A --answerdiff N -S --skipinstall --builddir /build "$@" 1>&3 2>&4 ; } 2>&1)
echo "CPU utilization: $time"
sudo mkdir /packages
sudo cp -a /build/*/*.pkg.tar.zst /packages
