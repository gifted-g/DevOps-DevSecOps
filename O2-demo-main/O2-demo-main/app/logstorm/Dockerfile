FROM golang:1.21-alpine AS builder
WORKDIR /build
COPY go.mod ./
COPY *.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o logstorm .

FROM scratch
COPY --from=builder /build/logstorm /logstorm
ENTRYPOINT ["/logstorm"]
