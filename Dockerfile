# Dockerfile for openmrs-backend with modules

FROM maven:3.9-eclipse-temurin-21 AS builder

WORKDIR /app

# Copy source and build
COPY . .
RUN mvn clean install -DskipTests -B

# Download required modules
RUN mkdir -p /modules && \
    # REST Web Services Module
    curl -L -o /modules/webservices.rest-2.44.0.omod \
      "https://addons.openmrs.org/api/v1/addon/org.openmrs.module.webservices.rest/2.44.0/download" && \
    # FHIR2 Module
    curl -L -o /modules/fhir2-2.4.0.omod \
      "https://addons.openmrs.org/api/v1/addon/org.openmrs.module.fhir2/2.4.0/download" && \
    # SPA Module
    curl -L -o /modules/spa-1.0.13.omod \
      "https://addons.openmrs.org/api/v1/addon/org.openmrs.module.spa/1.0.13/download" && \
    # Initializer Module
    curl -L -o /modules/initializer-2.8.0.omod \
      "https://addons.openmrs.org/api/v1/addon/org.openmrs.module.initializer/2.8.0/download" && \
    # Legacy UI Module (required dependency)
    curl -L -o /modules/legacyui-1.16.0.omod \
      "https://addons.openmrs.org/api/v1/addon/org.openmrs.module.legacyui/1.16.0/download" && \
    # ID Gen Module
    curl -L -o /modules/idgen-4.10.0.omod \
      "https://addons.openmrs.org/api/v1/addon/org.openmrs.module.idgen/4.10.0/download" && \
    # Address Hierarchy
    curl -L -o /modules/addresshierarchy-2.18.0.omod \
      "https://addons.openmrs.org/api/v1/addon/org.openmrs.module.addresshierarchy/2.18.0/download" && \
    # App Framework
    curl -L -o /modules/appframework-2.17.0.omod \
      "https://addons.openmrs.org/api/v1/addon/org.openmrs.module.appframework/2.17.0/download" && \
    # UI Framework
    curl -L -o /modules/uiframework-3.24.0.omod \
      "https://addons.openmrs.org/api/v1/addon/org.openmrs.module.uiframework/3.24.0/download" && \
    # App UI
    curl -L -o /modules/appui-1.18.0.omod \
      "https://addons.openmrs.org/api/v1/addon/org.openmrs.module.appui/1.18.0/download" && \
    # Metadatadeploy
    curl -L -o /modules/metadatadeploy-1.14.0.omod \
      "https://addons.openmrs.org/api/v1/addon/org.openmrs.module.metadatadeploy/1.14.0/download" && \
    # Metadatasharing
    curl -L -o /modules/metadatasharing-1.9.0.omod \
      "https://addons.openmrs.org/api/v1/addon/org.openmrs.module.metadatasharing/1.9.0/download" && \
    # Metadatamapping
    curl -L -o /modules/metadatamapping-1.6.0.omod \
      "https://addons.openmrs.org/api/v1/addon/org.openmrs.module.metadatamapping/1.6.0/download" && \
    # Event
    curl -L -o /modules/event-2.11.0.omod \
      "https://addons.openmrs.org/api/v1/addon/org.openmrs.module.event/2.11.0/download" && \
    ls -la /modules/

# Production stage
FROM tomcat:9.0-jdk21-temurin

# Remove default webapps
RUN rm -rf /usr/local/tomcat/webapps/*

# Copy the built WAR
COPY --from=builder /app/webapp/target/openmrs.war /usr/local/tomcat/webapps/openmrs.war

# Create data directories and copy modules
RUN mkdir -p /openmrs/data/modules
COPY --from=builder /modules/*.omod /openmrs/data/modules/

# Set environment
ENV OMRS_HOME=/openmrs/data
ENV CATALINA_OPTS="-Xmx2g -Xms1g -XX:+UseG1GC -DOPENMRS_APPLICATION_DATA_DIRECTORY=/openmrs/data"

EXPOSE 8080

CMD ["catalina.sh", "run"]