FROM jwilder/nginx-proxy
WORKDIR /buildimage

RUN apt-get update && apt-get install -y --allow-unauthenticated \
    apt-utils autoconf automake \
    build-essential git libcurl4-openssl-dev \
    libgeoip-dev liblmdb-dev libpcre++-dev \
    libtool libxml2-dev libyajl-dev pkgconf \
    wget zlib1g-dev && \
    git clone --depth 1 -b v3/master --single-branch https://github.com/SpiderLabs/ModSecurity

WORKDIR /buildimage/ModSecurity
RUN git submodule init && git submodule update && \
    ./build.sh && ./configure && make && make install

RUN git clone --depth 1 https://github.com/SpiderLabs/ModSecurity-nginx.git && \
    nginx_version=$(nginx -v 2>&1 | awk -F/ '{print $2}') && \
    wget http://nginx.org/download/nginx-$nginx_version.tar.gz && \
    tar zxvf nginx-$nginx_version.tar.gz && \
    cd nginx-$nginx_version && \
    ./configure --with-compat --add-dynamic-module=../ModSecurity-nginx && \
    make modules && \
    cp objs/ngx_http_modsecurity_module.so /etc/nginx/modules && \
    mkdir /etc/nginx/modsec && \
    wget -P /etc/nginx/modsec/ https://raw.githubusercontent.com/SpiderLabs/ModSecurity/v2/master/modsecurity.conf-recommended && \
    mv /etc/nginx/modsec/modsecurity.conf-recommended /etc/nginx/modsec/modsecurity.conf && \
    sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/' /etc/nginx/modsec/modsecurity.conf && \
    sed -i.bak 's/^\(SecRequestBodyInMemoryLimit\).*/#\1/' /etc/nginx/modsec/modsecurity.conf

WORKDIR /downloadrules

RUN wget https://github.com/SpiderLabs/owasp-modsecurity-crs/archive/v3.0.0.tar.gz && \
    tar -xzvf v3.0.0.tar.gz && \
    mv owasp-modsecurity-crs-3.0.0 /usr/local/ && \
    cd /usr/local/owasp-modsecurity-crs-3.0.0 && \
    cp crs-setup.conf.example crs-setup.conf

RUN echo $'# From https://github.com/SpiderLabs/ModSecurity/blob/master/\\n# modsecurity.conf-recommended\n#\n# Edit to set SecRuleEngine On\nInclude "/etc/nginx/modsec/modsecurity.conf"\n# OWASP CRS v3 rules\nInclude /usr/local/owasp-modsecurity-crs-3.0.0/crs-setup.conf\nInclude /usr/local/owasp-modsecurity-crs-3.0.0/rules/*.conf' > /etc/nginx/modsec/main.conf && \
    grep -v '^\$' /etc/nginx/modsec/main.conf > tmpfile.conf && \
    mv tmpfile.conf /etc/nginx/modsec/main.conf
#I had to to the grep and temp file thing because sometimes the pesky $ sign ends up at the beginning of the main.conf file

RUN echo 'load_module modules/ngx_http_modsecurity_module.so;' | cat - /etc/nginx/nginx.conf > temp && mv temp /etc/nginx/nginx.conf && \
    mkdir /etc/nginx/vhost.d && \
    echo $'#This puts modsec in each vhost\nmodsecurity on;\nmodsecurity_rules_file /etc/nginx/modsec/main.conf;' > /etc/nginx/vhost.d/default && \
    grep -v '^\$' /etc/nginx/vhost.d/default > tmpfile.conf && \
    mv tmpfile.conf /etc/nginx/vhost.d/default

WORKDIR /app

ENTRYPOINT ["/app/docker-entrypoint.sh"]

CMD ["forego", "start", "-r"]

#Last step add to each individual website(container) launched:
#server {
   #modsecurity on;
   #modsecurity_rules_file /etc/nginx/modsec/main.conf;
#}

#Instructions:
#https://www.nginx.com/blog/compiling-and-installing-modsecurity-for-open-source-nginx/

#Fix File: /etc/nginx/modsec/modsecurity.conf. Line: 37. Column: 33. As of ModSecurity version 3.0, SecRequestBodyInMemoryLimit is no longer supported
#Fix Dollar Sign at the begginning of /etc/nginx/modsec/main.conf
