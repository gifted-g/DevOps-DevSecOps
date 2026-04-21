FROM rust:1.72-alpine as builder

WORKDIR /usr/src/app

# Install build dependencies
RUN apk add --no-cache musl-dev

# Create a new empty shell project
COPY Cargo.toml .
COPY src src/

# Build for release
RUN cargo build --release

# Runner stage
FROM alpine:3.19

# Install runtime dependencies
RUN apk add --no-cache libgcc

WORKDIR /app

# Copy the binary from the builder stage
COPY --from=builder /usr/src/app/target/release/rust-todo /app/rust-todo

# Create a data directory for task storage
RUN mkdir -p /app/data

# Set the work directory as volume
VOLUME ["/app/data"]

# Run the binary
ENTRYPOINT ["/app/rust-todo"]
CMD ["list"]