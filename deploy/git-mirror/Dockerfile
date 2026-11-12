# Throw-away git server for the local GitOps demo (docs/adr/0005-gitops-source-and-release-flow.md)
# Unauthenticated by design: it is reachable only inside the kind cluster and via kubectl port-forward.
FROM alpine:3.24@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf

RUN apk add --no-cache git git-daemon nginx fcgiwrap spawn-fcgi \
 && addgroup -g 10001 -S git && adduser -u 10001 -S -G git -H -h /data -s /sbin/nologin git \
 && mkdir -p /data && chown 10001:10001 /data

COPY nginx.conf /etc/nginx/nginx.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod 0755 /entrypoint.sh

USER 10001:10001
EXPOSE 8080
ENTRYPOINT ["/entrypoint.sh"]
