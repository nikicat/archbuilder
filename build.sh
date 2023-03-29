#!/bin/sh -e

echo "MAKEFLAGS='$MAKEFLAGS'" | sudo tee -a /etc/makepkg.conf >/dev/null
sudo chown builduser /build
exec 3>&1 4>&2
git config --global --add protocol.file.allow always
TIMEFORMAT=%P
yaycmd="yay --nodiffmenu --nocleanmenu --noeditmenu --noupgrademenu --noremovemake --sudoflags -E -Sy --builddir /build"
util=$({ time tr "\0" "\n" < /dev/zero | PKGNAME=$1 $yaycmd "$@" 1>&3 2>&4 ; } 2>&1)
cores=$(nproc --all)
relutil=$(echo "scale=1;$util/$cores" | bc)
echo "CPU utilization: ${relutil}%"
sudo mkdir /packages
sudo cp -a /build/*/*.pkg.tar.zst /packages
