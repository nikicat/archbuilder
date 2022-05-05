# This is an example PKGBUILD file. Use this as a start to creating your own,
# and remove these comments. For more information, see 'man PKGBUILD'.
# NOTE: Please fill out the license field for your package! If it is unknown,
# then please put 'unknown'.

# The following guidelines are specific to BZR, GIT, HG and SVN packages.
# Other VCS sources are not natively supported by makepkg yet.

# Maintainer: Nikolay Bryskin <nbryskin@gmail.com>
pkgname=archbuilder-git
pkgver=r6.e0bc456
pkgrel=1
pkgdesc="Build AUR packages on EC2"
url="https://github.com/nikicat/archbuilder"
arch=('any')
license=('GPL')
depends=(aws-cli-v2 docker openssh)
source=('git+https://github.com/nikicat/archbuilder')
sha256sums=('SKIP')

pkgver() {
	cd "$srcdir/${pkgname%-git}"
	printf "r%s.%s" "$(git rev-list --count HEAD)" "$(git rev-parse --short HEAD)"
}

package() {
	cd "$srcdir/${pkgname%-git}"
        install -Dm755 run.sh "$pkgdir"/usr/bin/archbuild
        install -Dm644 spot-options.json "$pkgdir"/usr/share/archbuild/spot-options.json
}
