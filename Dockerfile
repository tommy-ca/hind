FROM ubuntu:rolling

ENV DEBIAN_FRONTEND noninteractive
ENV TZ Etc/UTC
ENV TERM xterm
ENV ARCH "dpkg --print-architecture"
ENV HOST_HOSTNAME hostname-default
ENV HOST_UNAME Linux
ENV NOMAD_HCL  /etc/nomad.d/nomad.hcl
ENV CONSUL_HCL /etc/consul.d/consul.hcl

EXPOSE 80 443

RUN apt-get -yqq update  && \
    apt-get -yqq --no-install-recommends install  \
    zsh  sudo  rsync  dnsutils  supervisor  curl  wget  iproute2  \
    apt-transport-https  ca-certificates  software-properties-common  gpgv2  gpg-agent && \
    # install binaries and service files
    #   eg: /usr/bin/nomad  $NOMAD_HCL  /usr/lib/systemd/system/nomad.service
    curl -fsSL https://apt.releases.hashicorp.com/gpg | apt-key add -  && \
    apt-add-repository "deb [arch=$($ARCH)] https://apt.releases.hashicorp.com $(lsb_release -cs) main" && \
    apt-get -yqq update  && \
    apt-get -yqq install  nomad  consul  consul-template  && \
    wget -qO /usr/bin/caddy "https://caddyserver.com/api/download?os=linux&arch=$($ARCH)"  && \
    chmod +x /usr/bin/caddy

WORKDIR /app
COPY   bin/install-docker-ce.sh bin/
RUN  ./bin/install-docker-ce.sh

COPY . .

RUN cp etc/supervisord.conf /etc/supervisor/conf.d/  && \
    cp etc/Caddyfile.ctmpl  /etc/  && \
    cat etc/nomad.hcl  >> ${NOMAD_HCL}  && \
    cat etc/consul.hcl >> ${CONSUL_HCL}  && \
    # for persistent volumes
    mkdir -m777 /pv

CMD /app/bin/entrypoint.sh
