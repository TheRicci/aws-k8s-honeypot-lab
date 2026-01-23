# qeeqbox/honeypots - Multi-Protocol Honeypot Server
# Based on https://github.com/qeeqbox/honeypots
# Docker image: justsky/honeypots

FROM justsky/honeypots:latest

# Create log directories
RUN mkdir -p /var/log/honeypots /opt/honeypots

# Set working directory
WORKDIR /opt/honeypots

# Expose ports for multiple honeypot services
# FTP
EXPOSE 21  
# SSH 
EXPOSE 22   
# HTTP
EXPOSE 80   
# HTTPS
EXPOSE 443  
# FTPS
EXPOSE 990 

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD python3 -c "import socket; s=socket.socket(); s.connect(('localhost', 80))" || exit 1

# Run multiple honeypots: HTTP, HTTPS, FTP, SSH
CMD ["python3", "-m", "honeypots", "--setup", "http:80,https:443,ftp:21,ssh:22", "--auto"]