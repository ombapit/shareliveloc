FROM golang:1.21-alpine AS builder

WORKDIR /app

RUN apk add --no-cache gcc musl-dev

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 go build -o shareliveloc-api .

FROM alpine:3.19

WORKDIR /app

COPY --from=builder /app/shareliveloc-api .

EXPOSE 8080

CMD ["./shareliveloc-api"]
