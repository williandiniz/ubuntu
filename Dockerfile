#@follow_tag(registry.redhat.io/ubi8/ubi)
FROM registry.redhat.io/ubi8/ubi:8.6-855 AS build-npm

# Copy upstream sources and bundled dependencies for all remote references in container.yaml
COPY $REMOTE_SOURCES $REMOTE_SOURCES_DIR

WORKDIR $REMOTE_SOURCES_DIR

# Install node and build npm packages
RUN INSTALL_PKGS="\
        nodejs \
    " && \
    yum -y --setopt=tsflags=nodocs --setopt=skip_missing_names_on_install=False install $INSTALL_PKGS

WORKDIR $REMOTE_SOURCES_DIR/config-tool/app

RUN cd pkg/lib/editor && \
    npm config list && \
    npm install --ignore-engines --loglevel verbose && \
    npm run build

WORKDIR $REMOTE_SOURCES_DIR/quay/app

RUN npm config list && \
    npm install --ignore-engines --loglevel verbose && \
    npm run build

# Build go packages
FROM registry-proxy.engineering.redhat.com/rh-osbs/openshift-golang-builder:1.16 AS build-gomod

COPY --from=build-npm $REMOTE_SOURCES_DIR $REMOTE_SOURCES_DIR

WORKDIR $REMOTE_SOURCES_DIR/jwtproxy/app
RUN source $REMOTE_SOURCES_DIR/jwtproxy/cachito.env && \
    go mod vendor && \
    go build ./cmd/jwtproxy

WORKDIR $REMOTE_SOURCES_DIR/pushgateway/app
RUN source $REMOTE_SOURCES_DIR/pushgateway/cachito.env && \
    go mod vendor && \
    go build

WORKDIR $REMOTE_SOURCES_DIR/config-tool/app
COPY --from=build-npm $REMOTE_SOURCES_DIR/config-tool/app/pkg/lib/editor/static/build $REMOTE_SOURCES_DIR/config-tool/app/pkg/lib/editor/static/build
RUN source $REMOTE_SOURCES_DIR/config-tool/cachito.env && \
    go mod vendor && \
    go build ./cmd/config-tool

#@follow_tag(registry.redhat.io/ubi8/ubi)
FROM registry.redhat.io/ubi8/ubi:8.6-855

LABEL com.redhat.component="quay-registry-container"
LABEL name="quay/quay-rhel8"
LABEL version=v3.7.3
LABEL io.k8s.display-name="Red Hat Quay"
LABEL io.k8s.description="Red Hat Quay"
LABEL summary="Red Hat Quay"
LABEL maintainer="support@redhat.com"
LABEL io.openshift.tags="quay"
ENV RED_HAT_QUAY=true

ENV PYTHON_VERSION=3.8 \
    PYTHON_ROOT=/usr/local/lib/python3.8 \
    PATH=$HOME/.local/bin/:$PATH \
    PYTHONUNBUFFERED=1 \
    PYTHONIOENCODING=UTF-8 \
    LANG=en_US.utf8 \
    PYTHONUSERBASE_SITE_PACKAGE=/usr/local/lib/python3.8/site-packages \
    QUAY_VERSION=v3.7.3

ENV QUAYDIR=/quay-registry \
    QUAYCONF=/quay-registry/conf \
    QUAYRUN=/quay-registry/conf \
    QUAYPATH="."

RUN mkdir $QUAYDIR
WORKDIR $QUAYDIR

ARG PIP_CERT
COPY --from=build-npm $REMOTE_SOURCES_DIR $REMOTE_SOURCES_DIR
COPY --from=build-npm $PIP_CERT $PIP_CERT
RUN cp -Rp $REMOTE_SOURCES_DIR/quay/app/* $QUAYDIR

COPY --from=build-gomod $REMOTE_SOURCES_DIR/config-tool/app/config-tool /usr/local/bin/config-tool
COPY --from=build-gomod $REMOTE_SOURCES_DIR/jwtproxy/app/jwtproxy /usr/local/bin/jwtproxy
COPY --from=build-gomod $REMOTE_SOURCES_DIR/config-tool/app/pkg/lib/editor $QUAYDIR/config_app
COPY --from=build-gomod $REMOTE_SOURCES_DIR/pushgateway/app/pushgateway /usr/local/bin/pushgateway

#RUN source $REMOTE_SOURCES_DIR/quay/cachito.env

RUN rm -Rf node_modules config_app/node_modules

RUN INSTALL_PKGS="\
        diffutils \
        file \
        make \
        python38 \
        nginx \
        libpq-devel \
        openldap \
        postgresql \
        gcc-c++ git \
        openldap-devel \
        dnsmasq \
        memcached \
        openssl \
        skopeo \
        python38-devel \
        libffi-devel \
        openssl-devel \
        postgresql-devel \
        libjpeg-devel \
        " && \
    yum -y --setopt=tsflags=nodocs --setopt=skip_missing_names_on_install=False install $INSTALL_PKGS && \
    yum -y update && \
    yum -y clean all

RUN source $REMOTE_SOURCES_DIR/quay/cachito.env && \
    alternatives --set python /usr/bin/python3 && \
    python -m pip install --no-cache-dir --upgrade setuptools pip && \
    python -m pip install --no-cache-dir wheel && \
    python -m pip install --no-cache-dir -r requirements.txt --no-cache && \
    python -m pip freeze

RUN ln -s $QUAYCONF /conf && \
    ln -sf /dev/stdout /var/log/nginx/access.log && \
    ln -sf /dev/stdout /var/log/nginx/error.log && \
    chmod -R a+rwx /var/log/nginx

# Cleanup
RUN UNINSTALL_PKGS="\
        gcc-c++ git \
        openldap-devel \
        python38-devel \
        libffi-devel \
        openssl-devel \
        postgresql-devel \
        libjpeg-devel \
        kernel-headers \
    " && \
    yum remove -y $UNINSTALL_PKGS && \
    yum clean all && \
    rm -rf /var/cache/yum /tmp/* /var/tmp/* /root/.cache && \
    rm -rf $REMOTE_SOURCES_DIR

EXPOSE 8080 8443 7443

RUN chgrp -R 0 $QUAYDIR && \
    chmod -R g=u $QUAYDIR

RUN mkdir /datastorage && chgrp 0 /datastorage && chmod g=u /datastorage && \
    mkdir -p /var/log/nginx && chgrp 0 /var/log/nginx && chmod g=u /var/log/nginx && \
    mkdir -p /conf/stack && chgrp 0 /conf/stack && chmod g=u /conf/stack && \
    mkdir -p /tmp && chgrp 0 /tmp && chmod g=u /tmp && \
    chmod g=u /etc/passwd

RUN chgrp 0 /var/log/nginx && \
    chmod g=u /var/log/nginx && \
    chgrp -R 0 /etc/pki/ca-trust/extracted && \
    chmod -R g=u /etc/pki/ca-trust/extracted && \
    chgrp -R 0 /etc/pki/ca-trust/source/anchors && \
    chmod -R g=u /etc/pki/ca-trust/source/anchors && \
    chgrp -R 0 /usr/local/lib/python3.8/site-packages/certifi && \
    chmod -R g=u /usr/local/lib/python3.8/site-packages/certifi

VOLUME ["/var/log", "/datastorage", "/tmp", "/conf/stack"]

USER 1001

ENTRYPOINT ["dumb-init", "--", "/quay-registry/quay-entrypoint.sh"]
CMD ["registry"]
