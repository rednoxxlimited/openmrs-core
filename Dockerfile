# Dockerfile for openmrs-core

FROM tomcat:8.5-jdk8-corretto

# Remove default webapps
RUN rm -rf /usr/local/tomcat/webapps/*

# Copy the built WAR file
COPY webapp/target/openmrs.war /usr/local/tomcat/webapps/openmrs.war

# Create OpenMRS data directory
RUN mkdir -p /openmrs/data/modules

# Set environment variables
ENV OMRS_HOME=/openmrs/data
ENV CATALINA_OPTS="-Xmx2g -Xms1g -XX:+UseG1GC -DOPENMRS_INSTALLATION_SCRIPT=/openmrs/data/installation.properties -DOPENMRS_APPLICATION_DATA_DIRECTORY=/openmrs/data"

EXPOSE 8080

CMD ["catalina.sh", "run"]