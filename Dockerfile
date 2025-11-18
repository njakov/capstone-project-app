# Use a multi-stage build to keep the image small
# Stage 1: Build the JAR
FROM maven:3.9.6-eclipse-temurin-17 AS build
WORKDIR /app
COPY . .
# Skip tests here because they require a DB, and we run them in the pipeline instead
RUN mvn clean package -DskipTests

# Stage 2: Run the App
FROM eclipse-temurin:17-jdk-jammy
WORKDIR /app
COPY --from=build /app/target/*.jar app.jar

# Create a non-root user for security (Best Practice)
RUN groupadd -r petclinic && useradd -r -g petclinic petclinic
USER petclinic

EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]