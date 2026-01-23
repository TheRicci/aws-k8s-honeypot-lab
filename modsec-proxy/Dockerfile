# ModSecurity WAF Proxy with NGINX
FROM alpine:latest

# Install dependencies
RUN apk add --no-cache \
    nginx \
    nginx-mod-http-modsecurity \
    modsecurity \
    modsecurity-crs \
    curl \
    openssl

# Create necessary directories
RUN mkdir -p /etc/nginx/modsec /var/log/modsec /var/log/nginx

# Copy custom configurations
COPY nginx.conf /etc/nginx/nginx.conf
COPY modsecurity.conf /etc/nginx/modsec/modsecurity.conf

# Copy OWASP Core Rule Set
COPY --from=owasp/modsecurity-crs:nginx /opt/modsecurity-crs /etc/nginx/modsec/owasp-crs

# Setup ModSecurity
RUN cp /etc/modsecurity/modsecurity.conf-recommended /etc/nginx/modsec/modsecurity.conf && \
    sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/' /etc/nginx/modsec/modsecurity.conf

# Create non-root user
RUN adduser -D -s /bin/sh nginx

# Set permissions
RUN chown -R nginx:nginx /etc/nginx /var/log/nginx /var/log/modsec /var/cache/nginx

# Switch to non-root user
USER nginx

# Expose ports
EXPOSE 80 443 990

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD curl -f http://localhost/health || exit 1

# Start NGINX
CMD ["nginx", "-g", "daemon off;"]