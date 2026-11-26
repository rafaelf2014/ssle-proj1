# one image per service, picked by --build-arg SERVICE=<name>
# pure-Go build (CGO off) so the result is a static binary on a tiny base
ARG GO_VERSION=1.27

FROM golang:${GO_VERSION} AS build
WORKDIR /src
# copy go.mod/go.sum first so the module download layer caches across services
COPY go.mod go.sum ./
RUN go mod download
COPY . .
ARG SERVICE
RUN CGO_ENABLED=0 GOOS=linux go build -o /out/app ./services/${SERVICE}

FROM gcr.io/distroless/static:latest
COPY --from=build /out/app /app
ENTRYPOINT ["/app"]
