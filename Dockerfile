# syntax=docker/dockerfile:1.3

# OpenMRS Core with Modules
ARG DEV_JDK=eclipse-temurin-21
ARG RUNTIME_JDK=jdk21-temurin

### Compile Stage
FROM maven:3.9-${DEV_JDK} AS compile

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


### Download Modules Stage - Using Maven
FROM maven:3.9-eclipse-temurin-21 AS modules

WORKDIR /modules

# Create a pom.xml to download modules from OpenMRS Maven repository
RUN cat > pom.xml << 'POMEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>org.openmrs.distro</groupId>
    <artifactId>module-downloader</artifactId>
    <version>1.0.0</version>
    <packaging>pom</packaging>

    <repositories>
        <repository>
            <id>openmrs-repo</id>
            <name>OpenMRS Nexus Repository</name>
            <url>https://mavenrepo.openmrs.org/nexus/content/repositories/public</url>
        </repository>
        <repository>
            <id>openmrs-repo-modules</id>
            <name>OpenMRS Modules</name>
            <url>https://mavenrepo.openmrs.org/nexus/content/repositories/modules/</url>
        </repository>
        <repository>
            <id>openmrs-repo-snapshots</id>
            <name>OpenMRS Snapshots</name>
            <url>https://mavenrepo.openmrs.org/nexus/content/repositories/snapshots</url>
            <snapshots>
                <enabled>true</enabled>
            </snapshots>
        </repository>
    </repositories>

    <dependencies>
        <!-- Web Services REST Module -->
        <dependency>
            <groupId>org.openmrs.module</groupId>
            <artifactId>webservices.rest-omod</artifactId>
            <version>2.44.0</version>
            <type>jar</type>
        </dependency>
        <!-- FHIR2 Module -->
        <dependency>
            <groupId>org.openmrs.module</groupId>
            <artifactId>fhir2-omod</artifactId>
            <version>2.2.0</version>
            <type>jar</type>
        </dependency>
        <!-- SPA Module -->
        <dependency>
            <groupId>org.openmrs.module</groupId>
            <artifactId>spa-omod</artifactId>
            <version>1.0.11</version>
            <type>jar</type>
        </dependency>
        <!-- Initializer Module -->
        <dependency>
            <groupId>org.openmrs.module</groupId>
            <artifactId>initializer-omod</artifactId>
            <version>2.7.0</version>
            <type>jar</type>
        </dependency>
        <!-- ID Gen Module -->
        <dependency>
            <groupId>org.openmrs.module</groupId>
            <artifactId>idgen-omod</artifactId>
            <version>4.10.0</version>
            <type>jar</type>
        </dependency>
        <!-- Legacy UI Module -->
        <dependency>
            <groupId>org.openmrs.module</groupId>
            <artifactId>legacyui-omod</artifactId>
            <version>1.16.0</version>
            <type>jar</type>
        </dependency>
        <!-- Event Module -->
        <dependency>
            <groupId>org.openmrs.module</groupId>
            <artifactId>event-omod</artifactId>
            <version>2.11.0</version>
            <type>jar</type>
        </dependency>
    </dependencies>

    <build>
        <plugins>
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-dependency-plugin</artifactId>
                <version>3.6.1</version>
            </plugin>
        </plugins>
    </build>
</project>
POMEOF

# Download modules using Maven dependency plugin
RUN mvn dependency:copy-dependencies -DoutputDirectory=/modules/omod -Dmdep.useRepositoryLayout=false -Dmdep.copyPom=false

# Rename .jar to .omod
RUN cd /modules/omod && \
    for f in *.jar; do \
      newname=$(echo "$f" | sed 's/-omod-/-/' | sed 's/\.jar$/.omod/'); \
      mv "$f" "$newname"; \
    done && \
    ls -la /modules/omod/


### Development Stage
FROM maven:3.9-${DEV_JDK} AS dev

RUN apt-get update && apt-get install -y tar gzip git curl && rm -rf /var/lib/apt/lists/*

ARG TARGETARCH=amd64
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
FROM tomcat:11-${RUNTIME_JDK}

RUN apt-get update && rm -rf /var/lib/apt/lists/* && rm -rf /usr/local/tomcat/webapps/*

ARG TARGETARCH=amd64
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
COPY --from=modules /modules/omod/*.omod /openmrs/data/modules/

# Verify modules were copied
RUN ls -la /openmrs/data/modules/

EXPOSE 8080

USER 1001

ENTRYPOINT ["/usr/bin/tini", "--"]

CMD ["/openmrs/startup.sh"]
