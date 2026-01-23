FROM nginx:1.25

# Install dependencies
RUN apt-get update && apt-get install -y \
    git \
    gcc \
    make \
    libpcre3 \
    libpcre3-dev \
    libssl-dev \
    libxml2 \
    libxml2-dev \
    libyajl-dev \
    pkgconf \
    libtool \
    automake \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install ModSecurity v3
RUN git clone --depth 1 https://github.com/SpiderLabs/ModSecurity /opt/modsecurity && \
    cd /opt/modsecurity && \
    git submodule init && git submodule update && \
    ./build.sh && \
    ./configure && \
    make && \
    make install

# Install ModSecurity-nginx connector
RUN git clone --depth 1 https://github.com/SpiderLabs/ModSecurity-nginx.git /opt/modsecurity-nginx

# Download OWASP CRS
RUN git clone --depth 1 https://github.com/coreruleset/coreruleset /etc/nginx/modsec/owasp-crs && \
    cp /etc/nginx/modsec/owasp-crs/crs-setup.conf.example \
       /etc/nginx/modsec/crs-setup.conf

# Load ModSecurity module
RUN sed -i '1iload_module modules/ngx_http_modsecurity_module.so;' /etc/nginx/nginx.conf

# Create log directory
RUN mkdir -p /var/log/modsec && chmod -R 755 /var/log/modsec

CMD ["nginx", "-g", "daemon off;"]
