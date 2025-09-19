# --- STAGE 1: The Builder ---
# We use a specific version of Alpine for reproducible builds.
# This stage is named 'builder'.
FROM alpine:3.20 AS builder

# Install dependencies needed ONLY for compiling the application.
RUN apk add --no-cache git build-base

# Clone the microsocks repository.
RUN git clone https://github.com/rofl0r/microsocks.git /tmp/microsocks

# Compile the application. 'make' will run inside the cloned directory.
RUN cd /tmp/microsocks && make


# --- STAGE 2: The Final Image ---
# Start from a fresh, clean base image.
FROM alpine:3.20

# Install only the packages required for the application to RUN.
# This keeps the final image small and secure.
RUN apk add --no-cache ip6tables iproute2

# Copy the compiled 'microsocks' binary from the 'builder' stage.
# This is the magic of multi-stage builds. None of the build tools
# from the first stage will be included in our final image.
COPY --from=builder /tmp/microsocks/microsocks /usr/local/bin/

# Copy the entrypoint script into the image.
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
# Make the entrypoint script executable.
RUN chmod +x /usr/local/bin/entrypoint.sh

# Document that the container exposes port 1080. This is good practice.
EXPOSE 1080

# Set the entrypoint to our custom script.
# This script will run when the container starts.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
