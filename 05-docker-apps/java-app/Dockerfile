# ---- Java Hello World (multi-stage: JDK to compile, JRE to run) ----------

# Stage 1: compile the source with a full JDK
FROM eclipse-temurin:21-jdk-alpine AS builder
WORKDIR /build
COPY src/HelloWorldServer.java .
RUN javac -d classes HelloWorldServer.java

# Stage 2: runtime image only needs the JRE, not the compiler
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY --from=builder /build/classes ./classes

EXPOSE 8080

RUN addgroup -S app && adduser -S app -G app
USER app

CMD ["java", "-cp", "classes", "HelloWorldServer"]
