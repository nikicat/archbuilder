#!/bin/bash -exv

echo "MAKEFLAGS='$MAKEFLAGS'" | sudo tee -a /etc/makepkg.conf
sudo chown builduser /build
tr "\0" "\n" < /dev/zero | yay --answerclean A --answerdiff N -S --skipinstall --builddir /build $*
sudo mkdir /packages
sudo cp -a /build/*/*.pkg.tar.zst /packages
