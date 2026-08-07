# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /
COPY system_files /system_files

# Base Image: Bluefin DX (GNOME, developer edition), stable stream
FROM ghcr.io/ublue-os/bluefin-dx:stable

### IMMUTABLE /opt
## TUXEDO Control Center installs into /opt/tuxedo-control-center. On ostree/bootc
## images /opt is normally a symlink to /var/opt (mutable, NOT part of the image),
## which would wipe TCC on deployment. Making /opt a real directory bakes TCC into
## the image. See the note in ublue-os/image-template.
RUN rm /opt && mkdir /opt

### MODIFICATIONS
## All package installs and customizations happen in build_files/build.sh
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

### LINTING
## Verify final image and contents are correct.
RUN bootc container lint
