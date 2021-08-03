### build the frontend
FROM mcr.microsoft.com/vscode/devcontainers/javascript-node:14 AS frontendbuild
ENV NODE_ENV production
WORKDIR /app

# copy project meta data
COPY ["package.json", "package-lock.json", "./"]

# install dependencies
RUN npm ci --only=production

# copy app 
COPY . ./ 

# build release app
RUN npm run build


###########################################################


### build runtime container for frontend
FROM mcr.microsoft.com/vscode/devcontainers/base:buster AS frontendruntime

ARG NGINX_VERSION=1.20.1
ARG NJS_VERSION=0.5.3
ARG PKG_RELEASE=1~buster

ARG NGINX_PACKAGES=" \
    nginx=${NGINX_VERSION}-${PKG_RELEASE} \
    nginx-module-xslt=${NGINX_VERSION}-${PKG_RELEASE} \
    nginx-module-geoip=${NGINX_VERSION}-${PKG_RELEASE} \
    nginx-module-image-filter=${NGINX_VERSION}-${PKG_RELEASE} \
    nginx-module-njs=${NGINX_VERSION}+${NJS_VERSION}-${PKG_RELEASE}"

RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update
RUN apt-get upgrade -y
RUN apt-get -y install --no-install-recommends curl
RUN apt-get install --no-install-recommends --no-install-suggests -y gnupg ca-certificates

# Get NGINX signing key
RUN curl -fsSL https://nginx.org/keys/nginx_signing.key | apt-key add -

# Edit the sources.list file
RUN echo "deb https://nginx.org/packages/debian/ buster nginx" >> /etc/apt/sources.list.d/nginx.list && \
    echo "deb-src https://nginx.org/packages/debian/ buster nginx" >> /etc/apt/sources.list.d/nginx.list && \
    apt-get update

RUN apt-get build-dep -y ${NGINX_PACKAGES} && \
    apt-get source --compile ${NGINX_PACKAGES} && \
    apt-get install --no-install-recommends --no-install-suggests -y ${NGINX_PACKAGES} gettext-base

# forward request and error logs to docker log collector
RUN ln -sf /dev/stdout /var/log/nginx/access.log && \
    ln -sf /dev/stderr /var/log/nginx/error.log

COPY --from=frontendbuild /app/build /usr/share/nginx/html

EXPOSE 80

STOPSIGNAL SIGQUIT

CMD ["nginx", "-g", "daemon off;"]

