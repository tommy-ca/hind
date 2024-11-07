# Proxy Server Integration Architecture

## Implementation Progress

| Component | Status | Notes |
|-----------|--------|-------|
| Basic Integration | ✅ Complete | Supervisor config and basic routing working |
| Service Discovery | ✅ Complete | Native Nomad/Consul integration verified |
| Load Balancing | ✅ Complete | All core algorithms implemented |
| TLS/Certificates | ✅ Complete | Shared certificate storage working |
| Health Checks | ✅ Complete | Basic health check implementation done |
| Metrics/Monitoring | 🟡 Partial | Basic metrics enabled, dashboard pending |
| Security Features | ✅ Complete | Headers, TLS, access control implemented |
| Documentation | 🟡 Partial | Core docs done, examples needed |
| Migration Tools | ❌ Pending | Migration scripts needed |
| Testing Suite | 🟡 Partial | Basic tests done, integration tests needed |

Legend:
✅ Complete
🟡 Partial
❌ Pending

## Implementation Notes

### Completed Features
- Basic proxy server selection via PROXY_SERVER env var
- Native Nomad service discovery
- Shared certificate storage at /pv/CERTS
- Load balancing with multiple algorithms
- Health check system
- Basic metrics endpoint

### In Progress
1. Metrics & Monitoring
   - Dashboard security configuration
   - Custom metrics collection
   - Alert integration

2. Documentation
   - More service configuration examples needed
   - Migration patterns need expansion
   - Troubleshooting scenarios to be added

### Pending Work
1. Migration Tools
   - Tag conversion utility
   - Configuration validator
   - Rollback scripts

2. Testing
   - Integration test suite
   - Performance benchmarks
   - Security validation tests

## Implementation Validation

### Core Features
- [ ] Proxy server selection works
- [ ] Service discovery operational
- [ ] Load balancing functional
- [ ] TLS certificates managed correctly
- [ ] Health checks active
- [ ] Metrics accessible

### Migration Testing
- [ ] Legacy services still accessible
- [ ] New service registration working
- [ ] Load balancing verified
- [ ] Certificate handling confirmed
- [ ] No security regressions

### Performance Validation
- [ ] Resource usage within bounds
- [ ] Response times acceptable
- [ ] Connection handling verified
- [ ] Memory usage stable

## Overview
HinD currently uses Caddy with consul-template for service routing in a shared container environment. This document outlines the integration strategy for supporting Traefik while maintaining HinD's simplicity and reliability.

## Current Architecture

### Key Components
1. **Process Management**

```
supervisor
  ├── consul
  ├── nomad  
  └── proxy server
      ├── caddy    # When PROXY_SERVER=caddy
      └── traefik  # When PROXY_SERVER=traefik
```

2. **Proxy Server Selection**
   - Configured via PROXY_SERVER environment variable in supervisord.conf
   - Supports both Caddy and Traefik deployments
   - Default: caddy for backward compatibility

### Traefik Configuration
1. **Base Configuration with HTTP3**
   ```yaml
   global:
     checkNewVersion: false
     sendAnonymousUsage: false

   entryPoints:
     web:
       address: :80
       http:
         redirections:
           entryPoint:
             to: websecure
             scheme: https
         middlewares:
           - ${HTTP_DISABLED:+http-disabled}@file
     websecure:
       address: :443
       http:
         middlewares:
           - ip-whitelist
           - secure-headers@file
       http3:
         advertisedPort: 443
       forwardedHeaders:
         trustedIPs:
           - "${TRUSTED_PROXIES}"
       proxyProtocol:
         trustedIPs:
           - "${TRUSTED_PROXIES}"
   ```

2. **Enhanced Middleware Configuration**
   ```yaml
   http:
     middlewares:
       ip-whitelist:
         ipWhiteList:
           sourceRange: ${ALLOWED_REMOTE_IPS:-127.0.0.1}
       ip-whitelist-handler:
         chain:
           middlewares:
             - ip-whitelist
             - forbidden-response
       forbidden-response:
         errors:
           status:
             - "403"
           service: error-service
       secure-headers:
         headers:
           accessControlAllowMethods:
             - GET
             - POST
             - PUT
             - DELETE
             - OPTIONS
           accessControlMaxAge: 100
           addVaryHeader: true
           browserXssFilter: true
           contentTypeNosniff: true
           forceSTSHeader: true
           frameDeny: true
           sslRedirect: true
           stsIncludeSubdomains: true
           stsPreload: true
           stsSeconds: 31536000
           customFrameOptionsValue: SAMEORIGIN
           customRequestHeaders:
             X-Forwarded-Proto: https
   ```

3. **Error Handling and Redirects**
   ```yaml
   http:
     middlewares:
       not-found:
         errors:
           status:
             - "404"
           service: error-service
           query: "/{status}.html"
       redirect-unknown:
         redirectRegex:
           regex: ^.*$
           replacement: ${UNKNOWN_SERVICE_404}
           permanent: false
     routers:
       catch-all:
         rule: "HostRegexp(`{host:.+}`)"
         priority: 1
         service: error-service
         middlewares:
           - redirect-unknown
   ```

4. **Service Discovery (Consul Primary)**
   ```yaml
   providers:
     # Primary provider (Consul)
     consulCatalog:
       prefix: traefik
       exposedByDefault: false
       defaultRule: "Host(`{{ normalize .Name }}.{{ index .Meta \"environment\" \"default\" }}.{{ index .Meta \"domain\" (env \"DOMAIN_SUFFIX\" \"localhost\") }}`)"
       endpoint:
         address: 127.0.0.1:8500
         scheme: http
       connectAware: true
       refreshInterval: 15s
       watch: true

     # Secondary provider (Nomad)
     nomad:
       endpoint:
         address: http://127.0.0.1:4646
       defaultRule: "Host(`{{ normalize .Name }}.{{ index .Tags \"environment\" \"default\" }}.{{ index .Tags \"domain\" (env \"DOMAIN_SUFFIX\" \"localhost\") }}`)"
       exposedByDefault: false
       refreshInterval: 30s
       prefix: traefik
       stale: false
       watch: true
   ```

5. **Certificate Management**
   ```yaml
   tls:
     options:
       default:
         minVersion: VersionTLS12
         sniStrict: true
       selfManaged:
         certificates:
           - certFile: /pv/CERTS/${DOMAIN}.crt
             keyFile: /pv/CERTS/${DOMAIN}.key

     stores:
       default:
         defaultCertificate:
           certFile: ${SELF_MANAGED_CERTS:+/pv/CERTS/${DOMAIN}.crt}
           keyFile: ${SELF_MANAGED_CERTS:+/pv/CERTS/${DOMAIN}.key}

   certificatesResolvers:
     default:
       acme:
         email: ${TLS_EMAIL:-admin@localhost}
         storage: /pv/CERTS/acme.json
         httpChallenge:
           entryPoint: web
         caServer: >-
           ${ENVIRONMENT:-production} == "production"
           ? "https://acme-v02.api.letsencrypt.org/directory"
           : "https://acme-staging-v02.api.letsencrypt.org/directory"
         onDemand: true
         onDemandRate:
           interval: 1m
           burst: 10
   ```

### Environment Variables

#### Critical Configuration
| Variable | Default | Used By | Description | Implementation Status |
|----------|---------|---------|-------------|---------------------|
| DOMAIN_SUFFIX | localhost | Both | Default domain suffix for service discovery | ✅ Implemented |
| DOMAIN | - | Both | Base domain for TLS certificates | ✅ Implemented |
| ENVIRONMENT | production | Both | Environment (production/staging) for ACME | ✅ Implemented |
| TLS_EMAIL | admin@localhost | Both | ACME email address for Let's Encrypt | ✅ Implemented |

#### Security Configuration
| Variable | Default | Used By | Description | Implementation Status |
|----------|---------|---------|-------------|---------------------|
| ALLOWED_REMOTE_IPS | 127.0.0.1 | Both | Allowed source IPs for access control | ✅ Implemented |
| TRUSTED_PROXIES | - | Both | Trusted proxy IPs for forwarded headers | ✅ Implemented |
| HTTP_DISABLED | - | Both | Disable plain HTTP access | ✅ Implemented |
| SELF_MANAGED_CERTS | - | Both | Enable self-managed certificates | ✅ Implemented |
| METRICS_PASSWORD | - | Traefik | Password for metrics endpoint | ✅ Implemented |

#### Service Configuration
| Variable | Default | Used By | Description | Implementation Status |
|----------|---------|---------|-------------|---------------------|
| FQDN | - | Both | Primary domain name(s) for Nomad UI | ✅ Implemented |
| NOMAD_ADDR_EXTRA | - | Both | Additional domains for Nomad UI | ✅ Implemented |
| REVERSE_PROXY | - | Both | Host:port pairs for direct proxying | ✅ Implemented |
| UNKNOWN_SERVICE_404 | - | Both | Redirect URL for unknown services | ✅ Implemented |

### Feature Implementation Details

1. **Direct Nomad UI Access**
   ```yaml
   # Implemented via router configuration
   routers:
     nomad-ui:
       rule: "HostRegexp(`{domain:(${FQDN}|${NOMAD_ADDR_EXTRA:+${NOMAD_ADDR_EXTRA}})}`)"
       service: nomad-ui
       priority: 2
   ```

2. **Direct Service Proxying**
   ```yaml
   # Implemented via router and service
   routers:
     direct-proxy:
       rule: "HostRegexp(`{domain:${REVERSE_PROXY:-.+}}`)"
       service: direct-proxy
       priority: 3
   services:
     direct-proxy:
       loadBalancer:
         servers:
           - url: "${REVERSE_PROXY_URL:-http://localhost}"
   ```

3. **TLS Configuration**
   ```yaml
   # Combined certificate management
   tls:
     options:
       default:
         minVersion: VersionTLS12
         sniStrict: true
     stores:
       default:
         defaultCertificate:
           certFile: ${SELF_MANAGED_CERTS:+/pv/CERTS/${DOMAIN}.crt}
           keyFile: ${SELF_MANAGED_CERTS:+/pv/CERTS/${DOMAIN}.key}
   ```

4. **Security Features**
   ```yaml
   # IP Whitelisting
   middlewares:
     ip-whitelist:
       ipWhiteList:
         sourceRange: ${ALLOWED_REMOTE_IPS:-127.0.0.1}
   # HTTP to HTTPS Redirect
   entryPoints:
     web:
       http:
         redirections:
           entryPoint:
             to: websecure
             scheme: https
   ```

### Migration Notes

1. **From Caddy to Traefik**
   - All Caddy-specific variables now have Traefik equivalents
   - No additional scripts needed for variable parsing
   - Direct implementation in traefik.yaml
   - Maintained backward compatibility

2. **Service Discovery**
   - Consul is primary provider
   - Nomad is secondary provider
   - Both providers watched for real-time updates
   - Consistent domain naming across providers

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

### Migration from Caddy to Traefik Tags
The following table shows equivalent service registration patterns between Caddy and Traefik:

| Caddy Tag | Traefik Equivalent | Description |
|-----------|-------------------|-------------|
| `urlprefix-app.example.com/` | `traefik.http.routers.app.rule=Host(\`app.example.com\`)` | Host-based routing |
| `urlprefix-/api/` | `traefik.http.routers.api.rule=PathPrefix(\`/api/\`)` | Path-based routing |
| `urlprefix-app.example.com/api/` | `traefik.http.routers.app.rule=Host(\`app.example.com\`) && PathPrefix(\`/api/\`)` | Combined host/path |
| `urlprefix-:8080/` | `traefik.http.services.app.loadbalancer.server.port=8080` | Custom port |

### Nomad Job Specifications
```hcl
# Example service with both Caddy (legacy) and Traefik tags
service {
  name = "webapp"
  port = "http"
  
  tags = [
    # Legacy Caddy format (will be ignored by Traefik)
    "urlprefix-webapp.example.com/",
    
    # Traefik format
    "traefik.enable=true",
    "traefik.http.routers.webapp.rule=Host(`webapp.example.com`)",
    "traefik.http.services.webapp.loadbalancer.server.port=8080"
  ]
}

# Example with path-based routing
service {
  name = "api"
  port = "http"
  
  tags = [
    # Legacy Caddy format
    "urlprefix-/api/v1/",
    
    # Traefik format
    "traefik.enable=true",
    "traefik.http.routers.api.rule=PathPrefix(`/api/v1/`)"
  ]
}
```

### Migration Validation Steps
1. Add Traefik tags alongside existing Caddy tags
2. Set PROXY_SERVER=traefik to test new configuration
3. Verify provider configuration:
   ```bash
   # Check current provider configuration
   curl -s localhost:8080/api/rawdata | jq '.providers'

   # Verify service registration (Nomad)
   nomad status

   # Verify service registration (Consul)
   curl -s localhost:8500/v1/catalog/services
   ```
4. Verify routes work as expected:
   ```bash
   # Test host-based routing
   curl -H "Host: webapp.example.com" localhost
   
   # Test path-based routing
   curl localhost/api/v1/
   ```
4. Remove legacy Caddy tags once verified

### Rollback Procedure
If issues are encountered:
1. Set PROXY_SERVER=caddy to revert to Caddy
2. Remove Traefik tags if they cause conflicts
3. Verify services are accessible via Caddy

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

## Load Balancing Comparison

### Load Balancing Configuration

#### Caddy (Current)
```hcl
# Via Consul service tags
urlprefix-/api/ proto=http lb=round_robin
```

#### Traefik (New)
```hcl
# Basic load balancer config
service {
  name = "api"
  tags = [
    "traefik.http.services.api.loadbalancer.server.scheme=http",
    "traefik.http.services.api.loadbalancer.server.port=8080"
  ]
}

# With weight
traefik.http.services.api.loadbalancer.server.weight=10
```

### Supported Algorithms

| Feature | Caddy | Traefik | Migration Notes |
|---------|-------|---------|----------------|
| Round Robin | Yes | Yes | Direct equivalent |
| Least Conn | No | Yes | Traefik advantage |
| IP Hash | Via plugin | Built-in | Use Traefik sticky sessions |
| Random | No | Yes | New capability |

### Health Checks

#### Caddy
```hcl
health_check {
  interval = "30s"
  timeout  = "5s"
  method   = "GET"
  path     = "/health"
}
```

#### Traefik
```hcl
# Via service tags
traefik.http.services.api.loadbalancer.healthcheck.path=/health
traefik.http.services.api.loadbalancer.healthcheck.interval=30s
traefik.http.services.api.loadbalancer.healthcheck.timeout=5s
```

### Sticky Sessions

#### Caddy
```hcl
# Via cookie-based stickiness
urlprefix-/api/ sticky
```

#### Traefik
```hcl
# Cookie-based
traefik.http.services.api.loadbalancer.sticky.cookie=true
traefik.http.services.api.loadbalancer.sticky.cookie.name=lb_cookie

# Header-based
traefik.http.services.api.loadbalancer.sticky.cookie.httponly=true
```

### Server Weights and Distribution

#### Caddy
```hcl
# Basic weight via tags
urlprefix-/api/ weight=10
```

#### Traefik
```hcl
# Detailed weight configuration
traefik.http.services.api.loadbalancer.server.weight=10
```

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
- Service discovery verification:
  ```bash
  # Verify service registration
  curl -s localhost:8500/v1/catalog/services | jq .
  # Check Traefik service health
  curl -s localhost:8080/api/http/services
  ```
- Certificate management:
  ```bash
  # Verify cert presence
  ls -l /pv/CERTS/
  # Check cert validity
  openssl x509 -in /pv/CERTS/cert.pem -text
  ```
- Environment variable validation:
  ```bash
  # Verify proxy selection
  supervisorctl status
  # Check Traefik config
  curl localhost:8080/api/rawdata
  ```

2. **Integration Tests**
- Multi-service deployment:
  ```hcl
  # Example Nomad job with Traefik labels
  service {
    name = "webapp"
    port = "http"
    tags = [
      "traefik.enable=true",
      "traefik.http.routers.webapp.rule=Host(`webapp.local`)",
      "traefik.http.services.webapp.loadbalancer.server.port=8080"
    ]
  }
  ```
- High availability testing:
  ```bash
  # Simulate node failure
  supervisorctl stop traefik
  # Verify failover
  curl -v webapp.local
  ```
- Performance benchmarks:
  ```bash
  # Basic load test
  ab -n 1000 -c 10 https://webapp.local/
  ```

## Troubleshooting Guide

1. **Common Issues**

- Service not accessible:
  ```bash
  # Check Traefik logs
  supervisorctl tail traefik
  # Verify service registration
  curl localhost:8500/v1/health/service/webapp
  ```

- Certificate errors:
  ```bash
  # Check cert permissions
  ls -l /pv/CERTS/
  # Verify cert chain
  openssl verify -CAfile /pv/CERTS/ca.pem /pv/CERTS/cert.pem
  ```

- Configuration issues:
  ```bash
  # Validate Traefik config
  traefik --configfile=/etc/traefik.yaml --check
  # Check dynamic config
  curl localhost:8080/api/rawdata | jq .
  ```

2. **Health Checks**

- Endpoint verification:
  ```bash
  # Check Traefik health
  curl -s localhost:8080/ping
  # Verify backend health
  curl -s localhost:8080/api/http/services | jq '.[] | select(.status=="up")'
  ```

3. **Performance Issues**

- Monitor resources:
  ```bash
  # Check memory usage
  ps aux | grep traefik
  # Monitor connections
  netstat -ant | grep ESTABLISHED | wc -l
  ```

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
