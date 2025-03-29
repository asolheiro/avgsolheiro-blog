FROM alpine:latest AS builder

RUN apk add --no-cache --repository=https://dl-cdn.alpinelinux.org/alpine/edge/community hugo

WORKDIR /src

COPY . .

RUN hugo --minify

FROM nginx:alpine

COPY --from=builder /src/public /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]