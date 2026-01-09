# syntax=docker/dockerfile:1.3

# OpenMRS Core with Modules
# This Dockerfile builds openmrs-core and includes essential modules

ARG BUILDPLATFORM
ARG DEV_JDK=eclipse-temurin-21
ARG RUNTIME_JDK=jdk21-temurin

### Compile Stage
FROM --platform=$BUILDPLATFORM maven:3.9-$DEV_JDK AS compile

RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*

WORKDIR /openmrs_core

ENV OMRS_SDK_PLUGIN="org.openmrs.maven.plugins:openmrs-sdk-maven-plugin"
ENV OMRS_SDK_PLUGIN_VERSION="5.11.0"

COPY docker-pom.xml .

ARG MVN_SETTINGS="-s /usr/share/maven/ref/settings-docker.xml -Daether.dependencyCollector.impl=bf"

RUN mvn $MVN_SETTINGS -f docker-pom.xml $OMRS_SDK_PLUGIN:$OMRS_SDK_PLUGIN_VERSION:setup-sdk -N -DbatchAnswers=n

COPY pom.xml .
COPY test/pom.xml test/
COPY tools/pom.xml tools/
COPY liquibase/pom.xml liquibase/
COPY api/pom.xml api/
COPY web/pom.xml web/
COPY webapp/pom.xml webapp/
COPY test-suite/pom.xml test-suite/
COPY test-suite/module/pom.xml test-suite/module/
COPY test-suite/module/api/pom.xml test-suite/module/api/
COPY test-suite/module/omod/pom.xml test-suite/module/omod/
COPY test-suite/performance/pom.xml test-suite/performance/

COPY . .

ARG MVN_ARGS='clean install -DskipTests'

RUN mvn $MVN_SETTINGS $MVN_ARGS


### Download Modules Stage
FROM alpine:3.19 AS modules

RUN apk add --no-cache curl unzip

WORKDIR /modules

# Download modules from GitHub releases with verification
RUN set -ex && \
    echo "Downloading webservices.rest..." && \
    curl -fSL -o webservices.rest-2.44.0.omod \
      "https://github.com/openmrs/openmrs-module-webservices.rest/releases/download/2.44.0/webservices.rest-2.44.0.omod" && \
    unzip -t webservices.rest-2.44.0.omod && \
    \
    echo "Downloading fhir2..." && \
    curl -fSL -o fhir2-2.2.0.omod \
      "https://github.com/openmrs/openmrs-module-fhir2/releases/download/2.2.0/fhir2-2.2.0.omod" && \
    unzip -t fhir2-2.2.0.omod && \
    \
    echo "Downloading spa..." && \
    curl -fSL -o spa-1.0.11.omod \
      "https://github.com/openmrs/openmrs-module-spa/releases/download/1.0.11/spa-1.0.11.omod" && \
    unzip -t spa-1.0.11.omod && \
    \
    echo "Downloading initializer..." && \
    curl -fSL -o initializer-2.7.0.omod \
      "https://github.com/mekomsolutions/openmrs-module-initializer/releases/download/2.7.0/initializer-2.7.0.omod" && \
    unzip -t initializer-2.7.0.omod && \
    \
    echo "Downloading idgen..." && \
    curl -fSL -o idgen-4.10.0.omod \
      "https://github.com/openmrs/openmrs-module-idgen/releases/download/4.10.0/idgen-4.10.0.omod" && \
    unzip -t idgen-4.10.0.omod && \
    \
    echo "Downloading legacyui..." && \
    curl -fSL -o legacyui-1.16.0.omod \
      "https://github.com/openmrs/openmrs-module-legacyui/releases/download/1.16.0/legacyui-1.16.0.omod" && \
    unzip -t legacyui-1.16.0.omod && \
    \
    echo "Downloading event..." && \
    curl -fSL -o event-2.11.0.omod \
      "https://github.com/openmrs/openmrs-module-event/releases/download/2.11.0/event-2.11.0.omod" && \
    unzip -t event-2.11.0.omod && \
    \
    echo "=== All modules downloaded ===" && \
    ls -la /modules/


### Development Stage
FROM maven:3.9-$DEV_JDK AS dev

RUN apt-get update && apt-get install -y tar gzip git && rm -rf /var/lib/apt/lists/*

ARG TARGETARCH
ARG TINI_VERSION=v0.19.0
ARG TINI_URL="https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini"
ARG TINI_SHA="93dcc18adc78c65a028a84799ecf8ad40c936fdfc5f2a57b1acda5a8117fa82c"
ARG TINI_SHA_ARM64="07952557df20bfd2a95f9bef198b445e006171969499a1d361bd9e6f8e5e0e81"
RUN if [ "$TARGETARCH" = "arm64" ] ; then TINI_URL="${TINI_URL}-arm64" TINI_SHA=${TINI_SHA_ARM64} ; fi \
    && curl -fsSL -o /usr/bin/tini ${TINI_URL} \
    && echo "${TINI_SHA}  /usr/bin/tini" | sha256sum -c \
    && chmod +x /usr/bin/tini 

ARG TOMCAT_VERSION=11.0.11
ARG TOMCAT_SHA="a26b2269530fd2fc834e9b1544962f6524cf87925de43b05ad050e66b5eaa76a4ad754a2c5fc4f851baf75a0ea1b0ed8f51082300393a4c35d8c2da0d7c535bd"
ARG TOMCAT_URL="https://www.apache.org/dyn/closer.cgi?action=download&filename=tomcat/tomcat-11/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz"
RUN curl -fL -o /tmp/apache-tomcat.tar.gz "$TOMCAT_URL" \
    && echo "${TOMCAT_SHA}  /tmp/apache-tomcat.tar.gz" | sha512sum -c \
    && mkdir -p /usr/local/tomcat && gzip -d /tmp/apache-tomcat.tar.gz  \
    && tar -xvf /tmp/apache-tomcat.tar -C /usr/local/tomcat/ --strip-components=1 \
    && rm -rf /tmp/apache-tomcat.tar.gz /usr/local/tomcat/webapps/* 

WORKDIR /openmrs_core

COPY --from=compile /usr/share/maven/ref /usr/share/maven/ref
COPY --from=compile /openmrs_core /openmrs_core/

RUN mkdir -p /openmrs/distribution/openmrs_core/ \
    && cp /openmrs_core/webapp/target/openmrs.war /openmrs/distribution/openmrs_core/openmrs.war \
    && cp /openmrs_core/wait-for-it.sh /openmrs_core/startup-init.sh /openmrs_core/startup.sh /openmrs_core/startup-dev.sh /openmrs/  \
    && chmod +x /openmrs/wait-for-it.sh && chmod +x /openmrs/startup-init.sh && chmod +x /openmrs/startup.sh \
    && chmod +x /openmrs/startup-dev.sh 

EXPOSE 8080

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/mvn-entrypoint.sh"]

CMD ["/openmrs/startup-dev.sh"]


### Production Stage
FROM tomcat:11-$RUNTIME_JDK

RUN apt-get update && rm -rf /var/lib/apt/lists/* && rm -rf /usr/local/tomcat/webapps/*

ARG TARGETARCH
ARG TINI_VERSION=v0.19.0
ARG TINI_URL="https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini"
ARG TINI_SHA="93dcc18adc78c65a028a84799ecf8ad40c936fdfc5f2a57b1acda5a8117fa82c"
ARG TINI_SHA_ARM64="07952557df20bfd2a95f9bef198b445e006171969499a1d361bd9e6f8e5e0e81"
RUN if [ "$TARGETARCH" = "arm64" ] ; then TINI_URL="${TINI_URL}-arm64" TINI_SHA=${TINI_SHA_ARM64} ; fi \
    && curl -fsSL -o /usr/bin/tini ${TINI_URL} \
    && echo "${TINI_SHA}  /usr/bin/tini" | sha256sum -c \
    && chmod g+rx /usr/bin/tini 

RUN sed -i '/Connector port="8080"/a URIEncoding="UTF-8" relaxedPathChars="[]|" relaxedQueryChars="[]|{}^&#x5c;&#x60;&quot;&lt;&gt;"' \
    /usr/local/tomcat/conf/server.xml \
    && chmod -R g+rx /usr/local/tomcat \
    && touch /usr/local/tomcat/bin/setenv.sh && chmod g+w /usr/local/tomcat/bin/setenv.sh \
    && chmod -R g+w /usr/local/tomcat/webapps /usr/local/tomcat/logs /usr/local/tomcat/work /usr/local/tomcat/temp 

RUN mkdir -p /openmrs/data/modules \
    && mkdir -p /openmrs/data/owa  \
    && mkdir -p /openmrs/data/configuration \
    && mkdir -p /openmrs/data/configuration_checksums \
    && mkdir -p /openmrs/data/complex_obs \
    && mkdir -p /openmrs/data/activemq-data \
    && chmod -R g+rw /openmrs

# Copy startup scripts
COPY --from=dev /openmrs/wait-for-it.sh /openmrs/startup-init.sh /openmrs/startup.sh /openmrs/
RUN chmod g+x /openmrs/wait-for-it.sh && chmod g+x /openmrs/startup-init.sh && chmod g+x /openmrs/startup.sh

WORKDIR /openmrs

COPY --from=dev /openmrs_core/LICENSE LICENSE
COPY --from=dev /openmrs/distribution/openmrs_core/openmrs.war /openmrs/distribution/openmrs_core/openmrs.war

# Copy modules from modules stage
COPY --from=modules /modules/*.omod /openmrs/data/modules/

# Verify modules were copied
RUN ls -la /openmrs/data/modules/

EXPOSE 8080

USER 1001

ENTRYPOINT ["/usr/bin/tini", "--"]

CMD ["/openmrs/startup.sh"]