FROM alpine:latest
LABEL maintainer="binhex"
LABEL org.opencontainers.image.source="https://github.com/binhex/arch-base"

ARG APPNAME=alpine-base
ARG RELEASETAG=latest
ARG TARGETARCH=amd64

ENV HOME=/home/nobody \
    TERM=xterm \
    LANG=en_GB.UTF-8 \
    PATH=/usr/local/bin/system/scripts/docker:/usr/local/bin/run:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apk add --no-cache \
        bash \
        ca-certificates \
        curl \
        jq \
        tzdata \
        moreutils \
        shadow \
        supervisor \
        dumb-init

COPY build/common/root/install.sh /tmp/install.sh
COPY build/common/root/supervisord.conf /etc/supervisord.conf
COPY build/common/root/init.sh /usr/bin/init.sh
COPY build/common/root/utils.sh /usr/local/bin/system/scripts/docker/utils.sh

RUN chmod +x /tmp/install.sh && /tmp/install.sh; rm -f /tmp/install.sh; \
    chmod +x /usr/bin/init.sh && \
    chmod +x /usr/local/bin/system/scripts/docker/utils.sh && \
    mkdir -p /config /data /config/run && \
    chmod 775 /config /data /config/run

RUN echo "export BASE_RELEASE_TAG=${RELEASETAG}" > /etc/image-build-info && \
    echo "export TARGETARCH=${TARGETARCH}" >> /etc/image-build-info

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["/usr/bin/init.sh"]
