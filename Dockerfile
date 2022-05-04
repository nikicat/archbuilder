FROM archlinux:base-devel AS make-yay
RUN pacman -Sy --noconfirm --needed git go
RUN git clone https://github.com/nikicat/yay && cd yay && git checkout 9e325b55f025eed0e3b52257c7547a3844754fb0 && make

FROM archlinux:base-devel

RUN pacman -Sy --needed --noconfirm sudo git && echo -e 'y\ny' | pacman -Scc
RUN useradd builduser -m # Create the builduser
RUN passwd -d builduser # Delete the buildusers password
RUN printf 'builduser ALL=(ALL) ALL\n' | tee -a /etc/sudoers # Allow the builduser passwordless sudo
COPY --from=make-yay /yay/yay /bin/
WORKDIR /home/builduser
USER builduser
COPY build.sh /bin
ENV MAKEFLAGS=-j4
VOLUME /build
ENTRYPOINT ["/bin/build.sh"]
