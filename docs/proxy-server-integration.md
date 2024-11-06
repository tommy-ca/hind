# Proxy Server Integration Architecture

## Overview
HinD supports multiple reverse proxy implementations while maintaining backward compatibility with the existing Caddy server setup. This document outlines the architecture and implementation details.

## Feature Flags

### Environment Variables
```bash
# Primary proxy selection
PROXY_SERVER="caddy"        # Options: "caddy" (default), "traefik"

# Proxy-specific configurations
PROXY_OPTS=""              # Additional proxy-specific options
PROXY_DEBUG="0"           # Enable debug logging for proxy server
```

## Directory Structure
```
hind/
├── etc/
│   ├── proxy/
│   │   ├── common/           # Shared proxy configurations
│   │   │   ├── tls.conf      # Common TLS settings
│   │   │   └── headers.conf  # Common security headers
│   │   ├── caddy/           # Caddy-specific configs
│   │   │   ├── Caddyfile.ctmpl
│   │   │   └── snippets/
│   │   └── traefik/         # Traefik-specific configs
│   │       ├── traefik.toml.ctmpl
│   │       └── dynamic/
│   └── supervisord.d/       # Supervisor config fragments
│       ├── caddy.conf
│       └── traefik.conf
├── bin/
│   ├── proxy/
│   │   ├── start-proxy.sh    # Proxy server launcher
│   │   └── reload-proxy.sh   # Graceful config reload
│   └── lib/
│       └── proxy-utils.sh    # Common proxy utilities
└── docs/
    └── proxy/
        ├── caddy.md         # Caddy-specific documentation
        └── traefik.md       # Traefik-specific documentation
```

## Implementation Details

### 1. Proxy Server Interface
Create `bin/proxy/start-proxy.sh`:
```bash
#!/bin/bash
set -eu
source /app/bin/lib/proxy-utils.sh

# Load proxy-specific environment
load_proxy_env

case "$PROXY_SERVER" in
  "caddy")
    setup_caddy_environment
    exec /usr/bin/caddy run --config /etc/proxy/caddy/Caddyfile
    ;;
  "traefik")
    setup_traefik_environment
    exec /usr/bin/traefik --configfile=/etc/proxy/traefik/traefik.toml
    ;;
esac
```

### 2. Configuration Management
Create `bin/lib/proxy-utils.sh`:
```bash
#!/bin/bash

load_proxy_env() {
  # Load common settings
  source /etc/proxy/common/env

  # Load proxy-specific settings
  if [ -f "/etc/proxy/${PROXY_SERVER}/env" ]; then
    source "/etc/proxy/${PROXY_SERVER}/env"
  fi
}

setup_caddy_environment() {
  export CERTS_DIR="/pv/CERTS"
  mkdir -p "$CERTS_DIR"
  ln -sf "$CERTS_DIR" /root/.local/share/caddy
}

setup_traefik_environment() {
  export CERTS_DIR="/pv/CERTS"
  mkdir -p "$CERTS_DIR"
  touch "$CERTS_DIR/acme.json"
  chmod 600 "$CERTS_DIR/acme.json"
}
```

### 3. Supervisor Integration
Create `etc/supervisord.d/proxy-base.conf`:
```ini
[program:proxy]
command=/app/bin/proxy/start-proxy.sh
autorestart=true
startsecs=10
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:consul-template]
command=/app/bin/proxy/start-consul-template.sh
autorestart=true
startsecs=10
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
```

### 4. Consul Template Integration
Create `bin/proxy/start-consul-template.sh`:
```bash
#!/bin/bash
set -eu
source /app/bin/lib/proxy-utils.sh

load_proxy_env

TEMPLATE_SRC="/etc/proxy/${PROXY_SERVER}/template.ctmpl"
TEMPLATE_DEST="/etc/proxy/${PROXY_SERVER}/config"
RELOAD_CMD="/app/bin/proxy/reload-proxy.sh"

exec /usr/bin/consul-template \
  -template "$TEMPLATE_SRC:$TEMPLATE_DEST:$RELOAD_CMD"
```

### 5. Dockerfile Updates
```dockerfile
# Add to existing Dockerfile
ARG PROXY_SERVER=caddy

# Install base proxy utilities
COPY bin/proxy /app/bin/proxy/
COPY bin/lib   /app/bin/lib/
RUN chmod +x /app/bin/proxy/* /app/bin/lib/*

# Install selected proxy server
RUN case "$PROXY_SERVER" in \
      "caddy") \
        install_caddy \
        ;; \
      "traefik") \
        install_traefik \
        ;; \
    esac

# Copy proxy configurations
COPY etc/proxy /etc/proxy/
```

## Migration Guide

### For Existing Installations
1. No changes required for current Caddy users
2. Environment variables remain backward compatible
3. Existing Caddy configurations continue to work

### Switching to Traefik
```bash
# During installation
curl -sS https://internetarchive.github.io/hind/install.sh | \
  sudo sh -s -- -e PROXY_SERVER=traefik

# Or update existing installation
sudo podman stop hind
sudo podman rm hind
export PROXY_SERVER=traefik
./install.sh
```

## Feature Comparison

| Feature | Caddy | Traefik |
|---------|-------|---------|
| Auto HTTPS | ✓ | ✓ |
| Consul Integration | ✓ | ✓ |
| Dashboard | - | ✓ |
| Metrics | Basic | Prometheus |
| Config Format | Caddyfile | TOML/YAML |
| Hot Reload | ✓ | ✓ |
| Access Logs | ✓ | ✓ |
| Rate Limiting | ✓ | ✓ |
| Circuit Breaker | - | ✓ |
| Middleware | Limited | Extensive |

## Testing Requirements

### Functional Testing
- [ ] Basic HTTP/HTTPS serving
- [ ] TLS certificate generation
- [ ] Service discovery
- [ ] Configuration reloading
- [ ] Access logging
- [ ] Metrics collection

### Integration Testing
- [ ] Consul service registration
- [ ] Template rendering
- [ ] Health checks
- [ ] Proxy selection
- [ ] Environment variable handling

### Performance Testing
- [ ] Request latency
- [ ] Memory usage
- [ ] CPU utilization
- [ ] Connection handling
- [ ] TLS handshake performance

### Migration Testing
- [ ] Clean installation
- [ ] Configuration conversion
- [ ] Certificate migration
- [ ] Service continuity

## Security Considerations

1. Certificate Management
   - Secure storage location
   - Proper permissions
   - Automatic renewal

2. Access Control
   - Dashboard security
   - API endpoints
   - Metrics exposure

3. Network Security
   - Port exposure
   - TLS configuration
   - Header security

## Monitoring and Debugging

### Logs
Both proxy servers write logs to stdout/stderr, captured by supervisord:
```bash
# View proxy logs
sudo podman exec hind supervisorctl tail -f proxy

# View consul-template logs
sudo podman exec hind supervisorctl tail -f consul-template
```

### Metrics
- Caddy: Basic metrics at `/-/metrics`
- Traefik: Prometheus metrics at `/metrics`

### Health Checks
Both implementations provide health check endpoints:
- Caddy: `/-/health`
- Traefik: `/ping`
