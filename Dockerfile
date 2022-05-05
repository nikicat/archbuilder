FROM archlinux:base-devel AS make-yay
RUN pacman -Sy --noconfirm --needed git go
RUN git clone https://github.com/nikicat/yay && cd yay && git checkout 63f1dcc917d269a44a3eec31ab6b4cd270d64eb0 && make

FROM archlinux:base-devel

RUN pacman -Sy --needed --noconfirm sudo git perl bc && echo -e 'y\ny' | pacman -Scc
RUN useradd builduser -m # Create the builduser
RUN passwd -d builduser # Delete the buildusers password
RUN printf 'builduser ALL=(ALL) ALL\n' | tee -a /etc/sudoers # Allow the builduser passwordless sudo
RUN ln -s /usr/bin/core_perl/pod2man /usr/bin/pod2man
COPY --from=make-yay /yay/yay /bin/
WORKDIR /home/builduser
USER builduser
COPY build.sh /bin
ENV MAKEFLAGS=-j4
VOLUME /build
ENTRYPOINT ["/bin/build.sh"]
