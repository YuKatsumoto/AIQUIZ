# AIQUIZ Relay (protocol v2)

WebSocket relay for online 1v1. Pairs players (random queue by mode, subject and
grade band, or a private 5-character friend code), forwards in-match messages
between host and guest, and holds a match for a 30 s reconnect grace window.

## Run locally

    pip install -r requirements.txt
    uvicorn main:app --port 8080

Point the game at it with `RELAY_SERVER_URL=ws://localhost:8080` in `AIQUIZ-Godot/.env`.

## Test

    python tests/test_relay.py

## Network simulation (dev only)

    RELAY_NETSIM="lat=120,jit=40,stall_p=0.01,stall_ms=300" uvicorn main:app --port 8080

`lat` is one-way relay→client latency in ms. `kill_after=N,kill_role=2` drops
the guest's first matched connection after N seconds (1 = host, 0 = both).

## Deploy

    PROJECT=<gcp-project> ./deploy_cloud_run.sh

Single instance only (`--max-instances 1`): match state is in memory.
Request-based billing with `--min-instances 0`: the service scales to zero when
nobody is connected and the first player afterwards waits for a cold start.

## Protocol

Frames are `{"t": type, "d": payload}`. The first frame must be
`hello{proto:2, build, profile, resume?{match_id, token}}`.

| Direction | Types |
|---|---|
| client → relay | `hello`, `queue`, `friend_create`, `friend_join`, `cancel`, `leave`, `ping` |
| relay → client | `welcome`, `update_required`, `queued`, `queue_timeout`, `friend_code`, `matched`, `resumed`, `resume_failed`, `peer_paused`, `peer_resumed`, `peer_left`, `forfeit`, `profile`, `pong`, `error`, `server_restart` |
| host → guest (relayed) | `settings`, `start`, `snap`, `quiz`, `evt`, `resync`, `finish`, `profile` |
| guest → host (relayed) | `cmd`, `ready`, `req_resync`, `profile` |

Profiles carry preset ids (`nick`, `hat`, `toon`, `emotes`) and one player-chosen
`name`. The name is checked by `relay/name_filter.py` (allowed characters, at most
12 characters and 3 digits, NG words) and replaced by `""` when it fails, in which
case the game shows the preset nickname for `nick`. There is no chat.
