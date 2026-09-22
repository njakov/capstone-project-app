# ---------------------------------------------------------------------------
# Base Image: Eclipse Temurin 17 JRE (matches pom.xml java.version)
# Index digest of eclipse-temurin:17-jre-jammy, resolved 2026-09-22 (17.0.20_8).
# ---------------------------------------------------------------------------
FROM eclipse-temurin:17-jre-jammy@sha256:e85989f3e4d136b3d7dde921e157fddb9c7016805a225c1ec483326b825b3ca5

WORKDIR /opt/spring-petclinic

# ---------------------------------------------------------------------------
# Security: Create a non-root user
# ---------------------------------------------------------------------------
RUN groupadd -r petclinic && useradd -r -g petclinic petclinic

# ---------------------------------------------------------------------------
# Installation
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
