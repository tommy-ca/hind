# Proxy Server Integration Architecture

## Implementation Progress

| Component | Status | Notes |
|-----------|--------|-------|
| Basic Integration | ✅ Complete | Traefik config and basic routing working |
| Service Discovery | ✅ Complete | Native Nomad/Consul integration verified |
| Load Balancing | ✅ Complete | Least connections algorithm implemented |
| TLS/Certificates | ✅ Complete | ACME and self-managed certs working |
| Health Checks | ✅ Complete | Standard health check system implemented |
| High Availability | ✅ Complete | Circuit breaker and retry policies in place |
| Metrics/Monitoring | ✅ Complete | Prometheus metrics with basic auth |
| Security Features | ✅ Complete | IP whitelist, secure headers, HSTS implemented |

## Current Architecture

### Key Components
1. **Process Management**
   - Supervisor manages Consul, Nomad, and proxy server
   - PROXY_SERVER environment variable selects between Caddy/Traefik
   - Default: Caddy for backward compatibility

### Traefik Configuration

1. **Entry Points**
   ```yaml
   entryPoints:
     web:
       address: :80
       # HTTP to HTTPS redirect with optional disable
     websecure:
       address: :443
       # HTTP/3 enabled
       # IP whitelist and secure headers
   ```

2. **Middleware Security**
   ```yaml
   middlewares:
     ip-whitelist:
       ipWhiteList:
         sourceRange: ${ALLOWED_REMOTE_IPS:-127.0.0.1}
     secure-headers:
       headers:
         browserXssFilter: true
         contentTypeNosniff: true
         frameDeny: true
         sslRedirect: true
         # Additional security headers...
   ```

3. **Service Discovery**
   ```yaml
   providers:
     consulCatalog:
       prefix: traefik
       address: localhost:8500
       # Native integration
     nomad:
       address: http://localhost:4646
       # Direct Nomad integration
   ```

4. **Load Balancing**
   ```yaml
   services:
     default:
       loadBalancer:
         strategy: leastconn
         healthCheck:
           interval: 10s
           timeout: 5s
         circuitBreaker:
           expression: NetworkErrorRatio() > 0.20
   ```

### Environment Variables

#### Critical Configuration
| Variable | Default | Description |
|----------|---------|-------------|
| DOMAIN_SUFFIX | localhost | Default domain suffix |
| DOMAIN | - | Base domain for TLS |
| ENVIRONMENT | production | ACME environment |
| TLS_EMAIL | admin@localhost | ACME email |
| METRICS_PASSWORD | - | Prometheus auth |

#### Security Configuration
| Variable | Default | Description |
|----------|---------|-------------|
| ALLOWED_REMOTE_IPS | 127.0.0.1 | IP whitelist |
| TRUSTED_PROXIES | - | Trusted IPs |
| HTTP_DISABLED | - | Disable HTTP |
| SELF_MANAGED_CERTS | - | Use local certs |

#### Service Configuration
| Variable | Default | Description |
|----------|---------|-------------|
| FQDN | - | Nomad UI domain |
| NOMAD_ADDR_EXTRA | - | Additional UI domains |
| REVERSE_PROXY | - | Direct proxy hosts |
| UNKNOWN_SERVICE_404 | - | 404 redirect URL |
| ON_DEMAND_TLS_ASK | - | Dynamic TLS |

### Security Features

1. **TLS Configuration**
   ```yaml
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

2. **Certificate Management**
   ```yaml
   certificatesResolvers:
     default:
       acme:
         email: ${TLS_EMAIL:-admin@localhost}
         storage: /pv/CERTS/acme.json
         httpChallenge:
           entryPoint: web
   ```

### Observability

1. **Logging**
   ```yaml
   log:
     level: INFO
     format: json
     filePath: /dev/stdout

   accessLog:
     filePath: /dev/stdout
     format: json
   ```

2. **Metrics**
   ```yaml
   metrics:
     prometheus:
       enabled: true
       port: 9100
       basicAuth:
         users:
           - metrics:${METRICS_PASSWORD}
   ```

### Migration Notes

1. **Service Tag Migration**
   | Caddy Tag | Traefik Label |
   |-----------|---------------|
   | urlprefix-host.com/ | traefik.http.routers.name.rule=Host(\`host.com\`) |
   | proto=http | traefik.http.services.name.loadBalancer.scheme=http |
   | lb=least_conn | (default) |

2. **Validation Steps**
   ```bash
   # Check config
   curl localhost:8080/api/rawdata
   
   # Verify services
   nomad status
   
   # Test routing
   curl -H "Host: service.domain" localhost
   ```

3. **Rollback Process**
   - Set PROXY_SERVER=caddy
   - Verify service access
   - Remove Traefik tags if needed

### Performance Characteristics

1. **Resource Requirements**
   - Memory: 256MB recommended
   - CPU: 1-2 cores
   - File descriptors: 32767
   - Connection limit: Matches Consul (32767)

2. **Health Checks**
   - 10s interval
   - 5s timeout
   - Circuit breaker at 20% error rate
   - 3 retry attempts

### Troubleshooting

1. **Common Checks**
   ```bash
   # Config validation
   curl localhost:8080/api/rawdata
   
   # Service health
   curl localhost:8080/api/http/services
   
   # Metrics
   curl -u metrics:${METRICS_PASSWORD} localhost:9100/metrics
   ```

2. **Log Locations**
   - Access logs: stdout
   - Error logs: stdout
   - Metrics: :9100/metrics

3. **Security Verification**
   ```bash
   # TLS check
   openssl s_client -connect host:443
   
   # Header check
   curl -I https://host
   ```

### Caddy vs Traefik Implementation

1. **Service Discovery**
   | Feature | Caddy | Traefik |
   |---------|-------|---------|
   | Method | consul-template | Native providers |
   | Update Method | Template regeneration | Watch API |
   | Config Format | Caddyfile | YAML |
   | Dynamic Updates | Via template | Real-time |

2. **URL Handling**
   ```hcl
   # Caddy (via consul-template)
   urlprefix-app.example.com/
   
   # Traefik (via labels)
   traefik.http.routers.app.rule=Host(`app.example.com`)
   ```

3. **Reverse Proxy Setup**
   ```
   # Caddy
   reverse_proxy localhost:{{ $port }} {
     lb_policy least_conn
     trusted_proxies {{ env "TRUSTED_PROXIES" }}
   }
   
   # Traefik
   services:
     app:
       loadBalancer:
         strategy: leastconn
         servers:
           - url: http://localhost:${port}
   ```

4. **HTTPS Redirection**
   ```
   # Caddy
   {{ if eq (env "HTTP_DISABLED") "true" }}
     respond Forbidden 403
   {{ else }}
     redir https://{host}{uri} permanent
   {{ end }}
   
   # Traefik
   web:
     http:
       redirections:
         entryPoint:
           to: websecure
           scheme: https
       middlewares:
         - ${HTTP_DISABLED:+http-disabled}@file
   ```

5. **Certificate Management**
   ```
   # Caddy
   {{ if ne (env "SELF_MANAGED_CERTS") "" }}
     tls /pv/CERTS/{{ $dom }}.crt /pv/CERTS/{{ $dom }}.key
   {{ end }}
   
   # Traefik
   tls:
     stores:
       default:
         defaultCertificate:
           certFile: ${SELF_MANAGED_CERTS:+/pv/CERTS/${DOMAIN}.crt}
           keyFile: ${SELF_MANAGED_CERTS:+/pv/CERTS/${DOMAIN}.key}
   ```

6. **Health Checks**
   ```
   # Caddy
   health_check {
     interval 30s
     timeout 5s
   }
   
   # Traefik
   healthCheck:
     interval: 10s
     timeout: 5s
     headers:
       User-Agent: Traefik-Health-Check
   ```

7. **IP Filtering**
   ```
   # Caddy
   {{ if ne (env "ALLOWED_REMOTE_IPS") "" }}
     @blocked not remote_ip {{ env "ALLOWED_REMOTE_IPS" }}
     respond @blocked Forbidden 403
   {{ end }}
   
   # Traefik
   middlewares:
     ip-whitelist:
       ipWhiteList:
         sourceRange: ${ALLOWED_REMOTE_IPS:-127.0.0.1}
   ```

8. **Unknown Service Handling**
   ```
   # Caddy
   http:// {
     redir {{ env "UNKNOWN_SERVICE_404" }}
   }
   
   # Traefik
   routers:
     catch-all:
       rule: "HostRegexp(`{host:.+}`)"
       service: error-service
       middlewares:
         - redirect-unknown
   ```

9. **Environment Variables**
   - Both use same variable names for compatibility
   - Traefik adds METRICS_PASSWORD for Prometheus auth
   - Both support ON_DEMAND_TLS_ASK for dynamic certs
   - Both use SELF_MANAGED_CERTS for local certificates

10. **Key Differences**
    - Traefik uses native service discovery vs template-based
    - Traefik provides built-in dashboard and API
    - Traefik offers more detailed metrics
    - Caddy has simpler configuration syntax
    - Traefik provides more middleware options
    - Both support HTTP/3, but with different configurations
