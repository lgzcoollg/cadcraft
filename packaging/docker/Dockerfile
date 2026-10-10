# syntax=docker/dockerfile:1
#
# CADCraft in one image: the browser build served by nginx, with the headless cadcraft-cli (info,
# convert, run, commands, perf, sample, and MCP over stdio) alongside it. Nothing is published to a
# registry:
#
#   packaging/web/package.sh                                    # writes dist/web/ (trunk build --release)
#   docker build -f packaging/docker/Dockerfile -t cadcraft .
#   docker run --rm -p 8771:80 cadcraft                         # the web app at http://localhost:8771/
#   docker run --rm -v "$PWD:/work" cadcraft info /work/plan.dxf
#   docker run -i --rm cadcraft mcp                             # stdio MCP server
#
# The image serves nginx by default; any other first argument is a cadcraft-cli subcommand, so the
# CLI reads the same in and out of a container (see the entrypoint at the end of this file).
#
# The desktop app (apps/cadcraft) is deliberately not in here: it opens a window on the system's GPU
# and uses native menus, tray, file dialogs and clipboard, none of which a container has. The web
# build is the same UI in a browser, and it is what this image serves.
#
# Two things worth knowing:
#   - The site is built on the host, not here: it needs trunk with wasm-bindgen and wasm-opt, and a
#     wasm build of egui, wgpu and naga wants several GB of build tree — more than a container build
#     should carry. packaging/web/package.sh also bakes in the optional font face if CRAFT_FONTS_DIR
#     is set, so the image serves exactly the site the release publishes. No trunk at hand? Unpack a
#     release zip into dist/web/ instead — see packaging/docker/README.md.
#   - The image runs as root, so a bind-mounted directory stays writable. Pass
#     `--user "$(id -u):$(id -g)"` to run as yourself instead; the mount then has to be writable by
#     that user.
#
# Details in packaging/docker/README.md.

# egui/eframe 0.36.2 need rustc 1.95, which the workspace's rust-version (1.90) predates.
ARG RUST_VERSION=1.95

# ---- cadcraft-cli --------------------------------------------------------------------------------
FROM rust:${RUST_VERSION}-bookworm AS cli

WORKDIR /src
# Manifests first, then the sources: a source-only change reuses the dependency build below.
COPY Cargo.toml Cargo.lock rustfmt.toml ./
COPY crates ./crates
COPY apps ./apps
COPY contributors ./contributors
COPY xtask ./xtask

# --locked: build exactly the graph the committed Cargo.lock pins, as a release does. The caches keep
# the registry and the build tree out of the image layers and warm between builds.
RUN --mount=type=cache,id=cargo-registry,target=/usr/local/cargo/registry \
    --mount=type=cache,id=cargo-target-cli,target=/src/target \
    cargo build --release --locked -p cadcraft-cli \
    && cp target/release/cadcraft-cli /usr/local/bin/cadcraft-cli

# ---- runtime: nginx serves the site, the CLI sits next to it -------------------------------------
# Debian, not Alpine: the CLI is linked against glibc, which the Alpine image would not run. This
# official nginx image also carries curl for compose's healthcheck and keeps nginx's own entrypoint.
FROM nginx:stable-bookworm

# The site packaging/web/package.sh built. index.html loads everything through relative URLs, so it
# works from any path (packaging/web/README.md).
COPY dist/web/ /usr/share/nginx/html/
RUN test -s /usr/share/nginx/html/index.html \
    || { echo "dist/web/index.html is missing or empty - run packaging/web/package.sh first (see packaging/docker/README.md)" >&2; exit 1; }

# The server settings that README requires (MIME types, caching, compression), written out for
# nginx. Replaces the image's default.conf; mount over it to change it without rebuilding.
COPY packaging/docker/nginx/default.conf /etc/nginx/conf.d/default.conf

COPY --from=cli /usr/local/bin/cadcraft-cli /usr/local/bin/cadcraft-cli

# One image, two jobs. No argument — or a web-ish one — starts nginx through the image's own
# entrypoint, so its /docker-entrypoint.d tuning still runs; any other argument goes to the CLI.
# `--entrypoint sh` gets a shell.
COPY <<'EOF' /usr/local/bin/cadcraft-entrypoint
#!/bin/sh
set -e
case "${1:-}" in
    "" | nginx | web | serve)
        exec /docker-entrypoint.sh nginx -g "daemon off;"
        ;;
    *)
        exec cadcraft-cli "$@"
        ;;
esac
EOF
RUN chmod 0755 /usr/local/bin/cadcraft-entrypoint

# Drawings get mounted here, e.g. `-v "$PWD:/work"`, so CLI paths read as /work/....
WORKDIR /work
EXPOSE 80
ENTRYPOINT ["/usr/local/bin/cadcraft-entrypoint"]
CMD ["web"]
