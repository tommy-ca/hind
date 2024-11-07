# Proxy Server Integration Architecture

## Overview
HinD currently uses Caddy with consul-template for service routing. This document outlines the integration strategy for supporting multiple proxy implementations while maintaining HinD's simplicity and reliability.

## Current Architecture

### Key Components
1. **Caddy + Consul Template**
   - Consul-template watches service changes
   - Dynamic Caddyfile generation
   - Automatic reload via supervisor
   - Certificate management via `/pv/CERTS`

2. **Environment Configuration**
   ```bash
   # Current supported variables
   UNKNOWN_SERVICE_404="https://archive.org/about/404.html"
   TRUSTED_PROXIES="private_ranges"
   REVERSE_PROXY="hostname:port"
   ON_DEMAND_TLS_ASK="URL"
   HTTP_DISABLED=""
   ```

## Integration Strategy

### Phase 1: Proxy Selection Framework
1. **Environment Variables**
   ```bash
   # New proxy selection
   PROXY_SERVER="caddy"        # or "traefik"
   ```

2. **Configuration Files**
   ```
   /etc/
   ├── Caddyfile.ctmpl        # Current Caddy config
   └── traefik.toml           # New Traefik config
   ```

3. **Backward Compatibility**
   - Maintain current environment variables
   - Preserve existing service discovery patterns
   - Keep current certificate storage location

### Phase 2: Traefik Integration
1. **Direct Consul Integration**
   - Native service discovery without consul-template
   - Real-time configuration updates
   - Built-in service mesh support

2. **Configuration Management**
   - Dynamic provider configuration
   - Consul KV store integration
   - Automatic service registration

### Phase 3: Feature Parity
1. **Certificate Management**
   - Shared certificate storage
   - Automatic HTTPS support
   - Let's Encrypt integration

2. **Service Discovery**
   - Compatible service tags
   - Consistent routing rules
   - DNS integration

## Service Configuration

### Nomad Job Specifications
```hcl
service {
  name = "webapp"
  port = "http"
  
  tags = [
    # Current Caddy format
    "urlprefix-webapp.example.com/",
    
    # New Traefik format
    "traefik.enable=true",
    "traefik.http.routers.webapp.rule=Host(`webapp.example.com`)"
  ]
}
```

## Feature Comparison

| Feature | Caddy (Current) | Traefik (Proposed) |
|---------|----------------|-------------------|
| Auto HTTPS | Yes | Yes |
| Consul Integration | via template | Native |
| Service Discovery | Template based | Native |
| Certificate Storage | /pv/CERTS | /pv/CERTS |
| Metrics | Basic | Prometheus |
| Hot Reload | Yes | Yes |
| Rate Limiting | Yes | Yes |

## Migration Guide

### For Existing Users
1. No immediate action required
2. Current Caddy setups remain supported
3. Optional opt-in to Traefik via `PROXY_SERVER`

### For New Deployments
```bash
export PROXY_SERVER=traefik
curl -sS https://internetarchive.github.io/hind/install.sh | sudo sh
```

## Security Considerations

1. **TLS Management**
   - Consistent certificate storage
   - Automatic HTTPS handling
   - Modern TLS configurations

2. **Access Control**
   - Consul ACLs for service discovery
   - Proxy-specific security features
   - Service isolation

3. **Network Security**
   - Header security
   - Request filtering
   - Rate limiting

## Monitoring and Observability

### Metrics
- Proxy-specific metrics endpoints
- Service discovery metrics
- Certificate management metrics

### Health Checks
- Proxy service health
- Backend service health
- Certificate validity

## Testing Requirements

### Functional Testing
- [ ] Proxy selection mechanism
- [ ] Service discovery with both proxies
- [ ] TLS certificate management
- [ ] Environment variable support

### Integration Testing
- [ ] Existing Nomad jobs compatibility
- [ ] DNS wildcard support
- [ ] HTTPS automation
- [ ] Metrics collection

## Future Considerations

1. **Service Mesh Evolution**
   - Enhanced service discovery
   - Advanced routing capabilities
   - Additional security features

2. **Monitoring Improvements**
   - Extended metrics
   - Enhanced logging
   - Better debugging tools

3. **Configuration Management**
   - Simplified setup
   - Better defaults
   - Enhanced documentation

## Documentation Updates

1. **User Guide**
   - Proxy selection documentation
   - Migration tutorials
   - Configuration examples

2. **Operations Guide**
   - Monitoring documentation
   - Troubleshooting guides
   - Security best practices

3. **Developer Guide**
   - Service integration patterns
   - Tag specifications
   - Testing guidelines
