# axiom

Godot-Projekt des axiom-Clients **und** des dedizierten Servers — beides ist
dasselbe Projekt. Der Server ist nur ein Headless-Build, weil axiom
physics-heavy ist und der Server dieselbe Jolt-Physik simulieren muss.

Godot 4.7, Forward+, Jolt Physics.

## Modi

| Modus | Start | Netzwerk |
|---|---|---|
| **Singleplayer** | Hauptmenü → Singleplayer | keins (`OfflineMultiplayerPeer`) |
| **Listen-Server** | Multiplayer → Listen-Server starten | ENet-Server + lokaler Spieler |
| **Client** | Multiplayer → Beitreten / Direkt verbinden | ENet-Client |
| **Dedicated Server** | `--server` oder Feature `dedicated_server` | ENet-Server, kein lokaler Spieler |

Alle Modi laden dieselbe `scenes/world.tscn`.

## Autoloads

Reihenfolge ist wichtig — `Boot._ready()` benutzt `Net` und `MasterServer`.

| Name | Skript | Aufgabe |
|---|---|---|
| `Net` | `scripts/net.gd` | ENet, Spielerliste, Spawnen |
| `MasterServer` | `scripts/masterServerClient.gd` | Server-Liste holen, eigenen Server registrieren + Heartbeat |
| `Boot` | `scripts/boot.gd` | CLI-Parsing, Client/Server-Entscheidung |
| `PortMapper` | `scripts/portMapper.gd` | UPnP-Portfreigabe (threaded) |

## Steuerung

`W A S D` laufen · `Shift` sprinten · `Leertaste` springen · `Maus` umsehen ·
`Escape` Pause. Die Bewegungs-Actions sind auf **physical keycodes** gebunden,
funktionieren also auch auf nicht-QWERTY-Layouts.

## Server-CLI

Alles nach `--` landet in `OS.get_cmdline_user_args()`. Ein exportierter
Server mit dem Preset „Linux Dedicated Server" braucht kein `--server`, weil
`OS.has_feature("dedicated_server")` greift.

| Flag | Default | Bedeutung |
|---|---|---|
| `--server` | – | Server-Modus erzwingen (im Editor-Build nötig) |
| `--port=N` | 7777 | UDP-Port |
| `--name=…` | `axiom dedicated` | Name in der Server-Liste |
| `--map=…` | `world` | Karte (nur Metadatum) |
| `--mode=…` | `default` | Spielmodus (nur Metadatum) |
| `--max-players=N` | 16 | Slots (1–1024) |
| `--tickrate=N` | 60 | `physics_ticks_per_second` **und** `max_fps` (10–240) |
| `--no-publish` | – | nicht beim Master Server registrieren |
| `--upnp` | – | Router per UPnP um eine Portfreigabe bitten |
| `--master=URL` | `http://127.0.0.1:8080` | Master Server (auch via `$AXIOM_MASTER_URL`) |
| `--public-address=…` | – | öffentliche Adresse; ohne Angabe nimmt der Master die IP der Verbindung |

Client-Flags, gedacht für lokale Tests:

| Flag | Bedeutung |
|---|---|
| `--connect=host:port` | direkt verbinden, ohne Splash und Menü |
| `--player-name=…` | Spielername |

## Lokal hochziehen

```bash
# 1. Master Server (optional - ohne ihn geht "Direkt verbinden")
cd ../axiom-masterserver && go run ./cmd/masterserver

# 2. Dedicated Server
godot --headless --path . -- --server --port=7777 --name="Dev #1"

# 3. Registrierung prüfen
curl http://127.0.0.1:8080/v1/servers

# 4. Zwei Clients, die sofort verbinden
godot --path . -- --connect=127.0.0.1:7777 --player-name=Eins
godot --path . -- --connect=127.0.0.1:7777 --player-name=Zwei
```

Ohne Master Server: Client starten, **Multiplayer → Direkt verbinden**
(`127.0.0.1:7777`).

## Erreichbarkeit — mit Freunden spielen

Ein Listen-Server läuft auf dem Rechner eines Spielers. Damit Freunde von
außen reinkommen, muss der Port durch Router und Firewall. Drei Wege, kein
Relay nötig:

**UPnP** (Autoload `PortMapper`, Godots eingebaute `UPNP`-Klasse). Der Host
bittet den Router selbst um die Freigabe. Im Server-Browser die Checkbox
„Port per UPnP öffnen", beim Dedicated Server das Flag `--upnp`. Läuft in
einem Thread, weil `UPNP.discover()` rund zwei Sekunden blockiert. Das
Ergebnis steht im HUD der Welt (nicht im Browser — der ist zu dem Zeitpunkt
schon weg).

Wichtig: eine erfolgreiche Freigabe heißt nicht automatisch erreichbar. Hinter
DS-Lite oder Carrier-NAT liefert der Router eine Adresse, die selbst privat
ist. `PortMapper.is_public_address()` prüft das (inklusive `100.64.0.0/10`,
RFC 6598) und meldet `reachable = false`.

**IPv6.** Kein NAT, keine Portfreigabe im NAT-Sinn. Verifiziert: ENet bindet
dual-stack (`::`), `Net.parse_address()` versteht `[2003:…]:7777`, und eine
Verbindung über eine globale IPv6-Adresse kommt zustande. Die Router-Firewall
filtert eingehend aber weiterhin — eine Freigabe (per UPnP oder von Hand)
braucht es also auch hier.

**Portfreigabe von Hand.** Funktioniert immer, außer hinter Carrier-NAT.

Und der Punkt, der das meiste erspart: **in einer Freundesrunde muss nur
einer hostbar sein.** Klappt es bei dir nicht, hostet jemand anders.

## Dedicated-Server-Build

Preset „Linux Dedicated Server" in `export_presets.cfg`
(`platform="Linux"`, `dedicated_server=true`, Ziel `./build/axiom_server`).
Für die Entwicklung reicht das Editor-Binary mit `--headless`; das Preset ist
nur fürs Deployment nötig.

## Netzwerk-Architektur

Bewegung ist **client-authoritativ**: jeder Peer ist Authority über seine
eigene Figur, der Server verteilt nur den Zustand. Auf dem Dedicated Server
läuft für Spielerfiguren kein `_physics_process` — der Server simuliert die
Spieler also derzeit **nicht**. Kein Anti-Cheat, keine Lag-Kompensation.

Ablauf beim Beitreten:

1. `Net.join()` → ENet `connected_to_server`
2. `world.tscn` laden → `world.gd._ready()` ruft `Net.world_ready(self)`
3. Client schickt `_request_join(name, version)`
4. Server prüft Version und Slots, spawnt die Figur, broadcastet die Spielerliste
5. Server schickt `_set_spawn(position)` an den Client

Schritt 3 ist Absicht: sonst kommt die Spawn-Replikation an, bevor der Client
den `Players`-Node hat.

Schritt 5 ist nötig, weil `set_multiplayer_authority()` in
`player.gd._enter_tree()` **rekursiv** wirkt und damit auch dem
`MultiplayerSynchronizer` der Figur gehört — dem Client, nicht dem Server.
Der Server kann die Startposition deshalb nicht im Spawn-State mitgeben. Ohne
`_set_spawn` starten alle Figuren im Ursprung und schieben sich gegenseitig weg.
`_set_spawn` läuft über einen anderen Kanal als die Spawn-Replikation, die
Reihenfolge ist also nicht garantiert — beide Fälle sind abgedeckt (siehe
`Net._set_spawn` und `player.gd.apply_spawn_position`).

Der nächste Schritt wäre ein server-authoritativer Tick: Clients senden
Input-Frames, der Server simuliert und schickt Snapshots, Clients machen
Prediction und Reconciliation. Das ist ein eigenes Arbeitspaket.

## Master Server

Siehe `../axiom-masterserver`. Wichtig für den Client: der JSON-Decoder dort
ist `DisallowUnknownFields` — **kein zusätzliches Feld** im Request-Body.
Rate-Limit sind 5 Registrierungen pro Minute und IP.
