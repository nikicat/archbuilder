FROM archlinux:base-devel AS make-yay
RUN pacman -Sy --noconfirm --needed git go
RUN useradd builduser -m # Create the builduser
RUN passwd -d builduser # Delete the buildusers password
RUN printf 'builduser ALL=(ALL) ALL\n' | tee -a /etc/sudoers # Allow the builduser passwordless sudo
USER builduser
WORKDIR /home/builduser
RUN git clone https://aur.archlinux.org/yay.git && cd yay && echo Y | makepkg -si

FROM archlinux:base-devel

RUN pacman -Syy --needed --noconfirm sudo git perl bc archlinux-keyring && echo -e 'y\ny' | pacman -Scc
RUN useradd builduser -m # Create the builduser
RUN passwd -d builduser # Delete the buildusers password
RUN printf 'builduser ALL=(ALL) ALL\n' | tee -a /etc/sudoers # Allow the builduser passwordless sudo
RUN ln -s /usr/bin/core_perl/pod2man /usr/bin/pod2man
COPY --from=make-yay /usr/bin/yay /usr/local/bin/
WORKDIR /home/builduser
USER builduser
COPY build.sh pacman /usr/local/bin/
ENV MAKEFLAGS=-j4
VOLUME /build
ENTRYPOINT ["/usr/local/bin/build.sh"]
