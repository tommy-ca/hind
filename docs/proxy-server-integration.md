# Proxy Server Integration Architecture

## Overview
HinD currently uses Caddy with consul-template for service routing in a shared container environment. This document outlines the integration strategy for supporting Traefik while maintaining HinD's simplicity and reliability.

## Current Architecture

### Key Components
1. **Process Management**

```
consul
  └── consul-template
      └── caddy
nomad
```

2. **Caddy + Consul Template**
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

### Phase 1: Traefik Integration

1. **Configuration Files**
```yaml
# /etc/traefik/traefik.yaml
global:
  checkNewVersion: false
  sendAnonymousUsage: false

entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"
```

2. **S6-Overlay Service Definition**
```sh
# /etc/s6-overlay/s6-rc.d/traefik/run
#!/command/execlineb -P
traefik --configfile=/etc/traefik/traefik.yaml
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

## Performance Characteristics

### Resource Requirements
- Minimum Memory: 256MB per proxy instance
- Recommended CPU: 1-2 cores
- File Descriptors: min 65535
- Network Buffers: min 256MB receive/transmit

### Performance Comparison Matrix
| Metric | Caddy (Current) | Traefik (Proposed) |
|--------|----------------|-------------------|
| Memory Footprint | ~50MB idle | ~60MB idle |
| Requests/sec | 10K+ | 15K+ |
| P95 Latency | <20ms | <15ms |
| Max Connections | 10K default | 10K default |
| Hot Reload Time | <1s | <1s |
| Config Parse | Template based | Native watch |

### Feature Comparison
| Feature | Caddy (Current) | Traefik (Proposed) |
|---------|----------------|-------------------|
| Auto HTTPS | Yes | Yes |
| Consul Integration | via template | Native |
| Service Discovery | Template based | Native |
| Certificate Storage | /pv/CERTS | /pv/CERTS |
| Metrics | Basic | Prometheus |
| Hot Reload | Yes | Yes |
| Rate Limiting | Yes | Yes |
| Circuit Breaking | No | Yes |
| Retry Policies | Basic | Advanced |
| Middleware | Limited | Extensive |

## Failure Modes & Recovery

### Certificate Management
- Acquisition Failure: Falls back to self-signed
- Storage Issues: Uses memory cache
- Renewal Errors: Auto-retry with backoff
- Validation Errors: Admin notification

### Service Discovery 
- Consul Unavailable: Cache last known config
- DNS Failures: Fallback to direct IPs
- Config Parse Error: Keep previous config
- Template Error: Alert and retry

### Connection Handling
- Circuit Breaking: Auto-disable failing backends
- Connection Draining: 30s grace period
- Rate Limiting: Per-IP and global limits
- Buffer Overflow: Automatic request queuing

## Security Implementation

### Header Security
```yaml
# Default Security Headers
security_headers:
  X-Frame-Options: SAMEORIGIN
  X-XSS-Protection: "1; mode=block"
  X-Content-Type-Options: nosniff
  Referrer-Policy: strict-origin-when-cross-origin
  Permissions-Policy: accelerometer=(), camera=(), geolocation=(), microphone=()
```

### Access Controls
1. **IP Filtering**
   - Allow/deny lists
   - CIDR range support
   - Geo-blocking options

2. **Rate Limiting**
   ```yaml
   rate_limit:
     requests_per_second: 100
     burst: 50
     response_code: 429
     cleanup_interval: 10s
   ```

3. **Authentication**
   - Basic Auth
   - JWT validation
   - Custom header verification
   - OAuth2 proxy support

4. **WAF Rules**
   - SQL injection protection
   - XSS filtering
   - Path traversal prevention
   - Request size limits

## Operational Procedures

### Hot Reload Process
1. Config validation
2. Graceful connection drain
3. New config application
4. Health check verification
5. Rollback on failure

### Monitoring Points
1. **Metrics Endpoints**
   - `/metrics` - Prometheus format
   - `/health` - Overall status
   - `/ready` - Readiness status

2. **Log Levels**
   ```yaml
   logging:
     level: INFO
     format: json
     output: stdout
     access_logs: true
   ```

3. **Debug Procedures**
   - Config dump endpoint
   - Connection tracking
   - TLS certificate inspection
   - Route testing endpoint

## Migration Guide

### For Existing Users
1. Update environment variables:
```bash
export PROXY_SERVER=traefik
```

2. Verify service discovery:
```bash
# Check service registration
nomad status
# Verify Traefik configuration
curl localhost:8080/api/rawdata
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

1. **Functional Tests**
- Service discovery verification
- Certificate management
- Environment variable support
- Load balancing behavior

2. **Integration Tests**
- Multi-service deployment
- High availability scenarios
- Failure recovery
- Performance benchmarks

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
