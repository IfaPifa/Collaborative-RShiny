# Stage 1: Build the app using Maven and Java 21
FROM maven:3.9.6-eclipse-temurin-21 AS build
WORKDIR /app
COPY . .
# We skip tests during the build to save time
RUN mvn clean package -DskipTests

# Stage 2: Run the app using a slim Java 21 image
FROM eclipse-temurin:21-jre
WORKDIR /app
# Copy the compiled war file from the build stage
COPY --from=build /app/target/shinyswarm-0.0.1-SNAPSHOT.war app.war
# Your app runs on port 8085
EXPOSE 8085
ENTRYPOINT ["java", "-jar", "app.war"]