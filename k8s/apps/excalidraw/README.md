# Excalidraw

Self-hosted whiteboard at https://draw.homelab.krymancer.dev.

Uses the official `excalidraw/excalidraw` image (port 80). Upstream does not
publish semver tags, so the Deployment pins the 2026-05-06 multi-arch digest
instead of `:latest`. Live collaboration still talks to Excalidraw's hosted
room server; fully private collab needs a custom image + `excalidraw-room`.

No auth in v1 (LAN + Cloudflare). Authelia can be added later.
