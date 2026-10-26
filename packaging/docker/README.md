# Running CADCraft with Docker

One image holds the two parts of CADCraft that containerise well: nginx serves the browser build,
and the same image carries the headless `cadcraft-cli` (info, convert, run, commands, perf, sample,
and MCP over stdio). Neither needs anything from a registry. The desktop app is deliberately not one
of them — it opens a window on the system's GPU and uses native menus, tray, file dialogs and
clipboard, none of which a container has. Use the web build for the UI and the CLI for automation.

## Building the image

`packaging/docker/Dockerfile` builds `cadcraft-cli` from the committed `Cargo.lock` and copies the
web build in. So the site has to exist first — the image does not build wasm itself, because a wasm
build of egui, wgpu and naga wants trunk, wasm-bindgen, wasm-opt and several GB of build tree:

```sh
packaging/web/package.sh                       # writes dist/web/ (trunk build --release)
docker build -f packaging/docker/Dockerfile -t cadcraft .
```

`package.sh` needs [trunk](https://trunkrs.dev) and the `wasm32-unknown-unknown` target
(`rustup target add wasm32-unknown-unknown`).

**Set `CRAFT_FONTS_DIR` if the site has to draw Chinese, Japanese or Arabic text** — a browser has
no system fonts, so without the embedded faces those characters show as empty boxes:

```sh
CRAFT_FONTS_DIR=/path/to/craft-fonts packaging/web/package.sh   # absolute path
```

That bakes the craft-fonts faces in (Droid Sans Fallback for Simplified Chinese, BIZ UDPGothic for
Japanese, Noto Sans Arabic), exactly as the release build does, and adds about 9 MB to the wasm.

No trunk at hand? Unpack a [release
zip](https://github.com/storytold/cadcraft/releases) instead — `index.html` loads everything through
relative URLs, so the published site is byte-for-byte what the image should serve:

```sh
mkdir -p dist/web
unzip -j cadcraft-web-0.13.1.zip 'cadcraft-web-0.13.1/index.html' \
  'cadcraft-web-0.13.1/*.js' 'cadcraft-web-0.13.1/*.wasm' -d dist/web
docker build -f packaging/docker/Dockerfile -t cadcraft .
```

The image's build stage is `rust:1.95-bookworm` (egui 0.36.2's floor) and the runtime is
`nginx:stable-bookworm` — the same Debian family the CLI links against, so the binary runs as built.
The image installs no fonts: CADCraft's drafting font is drawn in code and travels inside the wasm.

Both stages build natively for the platform being built, so a cross-build works — slowly, under
emulation:

```sh
docker buildx build --platform linux/arm64 -f packaging/docker/Dockerfile --load -t cadcraft .
```

A multi-architecture manifest is assembled by buildx, which has to push to a registry rather than
load into the local image store (`--platform linux/amd64,linux/arm64 --push`). Nothing in this
repository publishes an image.

## The web app

```sh
docker run --rm -p 8771:80 cadcraft        # then open http://localhost:8771/
```

8771 is the port `trunk serve` uses for this app (see `apps/cadcraft-web/Trunk.toml`); inside the
image nginx listens on 80. Publish a different port (`-p 18771:80`) if another Crafting App's
container already holds 8771.

With compose, which builds and runs the same image:

```sh
docker compose -f packaging/docker/compose.yaml up --build --wait     # then open http://localhost:8771/
docker compose -f packaging/docker/compose.yaml down
```

`CADCRAFT_WEB_PORT` moves the published port. The compose service runs nginx with a read-only
container filesystem and only its pid file and cache writable.

`nginx/default.conf` is the nginx form of the hosting requirements in
[`packaging/web/README.md`](../web/README.md), baked into the image. `smoke-test.sh` checks a running
server — this one or your own — against them:

```sh
packaging/docker/smoke-test.sh http://localhost:8771
```

It fails on a wrong MIME type, a missing or wrong `Cache-Control`, an asset the page asks for that
404s, or a `.wasm` that is not gzipped.

Mind the HTTPS rule from that README: WebGPU and the clipboard need a secure context, so
`http://localhost` is fine while a plain-HTTP LAN address such as `http://192.168.1.5:8771` serves
the app with the WebGL2 fallback.

## The CLI

The CLI is a command on the image above, not a second one. Mount the directory holding your
drawings at `/work` (the image's working directory) and the paths read like the ones in the
[README](../../README.md):

```sh
docker run --rm cadcraft --version
docker run --rm -v "$PWD:/work" cadcraft sample bracket /work/bracket.dxf
docker run --rm -v "$PWD:/work" cadcraft info /work/bracket.dxf
docker run --rm -v "$PWD:/work" cadcraft convert /work/bracket.dxf /work/bracket.svg
docker run --rm -v "$PWD:/work" cadcraft run --sample --script 'CIRCLE 22,3 1\n' --save /work/out.dxf --export /work/out.png
docker run --rm cadcraft commands circle   # the command catalog as JSON
docker run --rm cadcraft perf 200000       # timing table on a synthetic drawing
```

Through compose, run the same image's CLI branch with `docker compose run`:

```sh
docker compose -f packaging/docker/compose.yaml run --rm -v "$PWD:/work" web info /work/bracket.dxf
```

The container runs as root so a bind-mounted directory stays writable. Pass
`--user "$(id -u):$(id -g)"` to run as yourself instead, which needs the mount writable by that
user.

## MCP over stdio

`mcp` speaks JSON-RPC over stdio, so the client starts the container itself and has to keep stdin
open (`-i`, no `-t`):

```sh
claude mcp add cadcraft -- docker run --rm -i cadcraft mcp
```

or, for a client configured by JSON (the headless form from [docs/mcp.md](../../docs/mcp.md)):

```json
{
  "mcpServers": {
    "cadcraft": {
      "command": "docker",
      "args": ["run", "--rm", "-i", "cadcraft", "mcp"]
    }
  }
}
```

Mount a directory and open a drawing through the tools (`-v "$PWD:/work"`, then `open` with
`/work/plan.dxf`), or start from nothing: the headless backend has `command_line`, `execute`,
`inspect_drawing`, `query_entities` and `render`.

To drive a **running desktop app** instead, the MCP server bridges to its control channel:

```sh
docker run --rm -i --add-host host.docker.internal:host-gateway \
  cadcraft mcp --connect host.docker.internal:7979
```

The app has to run on the host with `--control 7979` (any free port; see
[docs/control-protocol.md](../../docs/control-protocol.md)), and a container reaches it as
`host.docker.internal` on Docker Desktop and through `--add-host ...:host-gateway` on Linux. With
`--network host` (Linux only) `--connect 127.0.0.1:7979` works too. This is the only part of the
image that needs the host; the file, render and CLI paths need no such link.
