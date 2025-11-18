# ---------------------------------------------------------------------------
# Base Image: OpenJDK 25 EA (Slim)
# ---------------------------------------------------------------------------
FROM openjdk:25-ea-21-jdk-slim

WORKDIR /opt/spring-petclinic

# ---------------------------------------------------------------------------
# Security: Create a non-root user
# ---------------------------------------------------------------------------
RUN groupadd -r petclinic && useradd -r -g petclinic petclinic

# ---------------------------------------------------------------------------
# Installation
# We copy the 3 required files (App, Agent, Config) from the build context.
# ---------------------------------------------------------------------------
COPY spring-petclinic.jar spring-petclinic.jar
COPY jmx.jar jmx.jar
COPY config.yaml config.yaml

# Grant ownership to the non-root user
RUN chown -R petclinic:petclinic /opt/spring-petclinic

# ---------------------------------------------------------------------------
# Execution
# ---------------------------------------------------------------------------
USER petclinic

# Expose App (8080) and Metrics (9093)
EXPOSE 8080 9093

# Run with the Prometheus Java Agent attached
ENTRYPOINT [ "java", \
  "-javaagent:/opt/spring-petclinic/jmx.jar=9093:/opt/spring-petclinic/config.yaml", \
  "-jar", \
  "spring-petclinic.jar" \
]