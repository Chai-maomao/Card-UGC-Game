"""Run party matches over loopback with a separate Godot process for every seat."""
import argparse
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import time

from local_udp_conditions import LocalUdpLink


ROOT = Path(__file__).resolve().parents[1]
MARKER = "TEST_TEAM_ROOM_OK "


def test_environment(profile: Path, invite: str) -> dict[str, str]:
    profile.mkdir(exist_ok=True)
    return dict(os.environ, APPDATA=str(profile), LOCALAPPDATA=str(profile),
                XDG_DATA_HOME=str(profile), XDG_CONFIG_HOME=str(profile), CARDEX_PARTY_INVITE=invite)


def wait_for_listener(process, log: Path, marker: str) -> None:
    deadline = time.monotonic() + 10
    while marker not in log.read_text(encoding="utf8", errors="replace"):
        if process.poll() is not None or time.monotonic() > deadline:
            raise RuntimeError(f"Room could not listen. See {log}")
        time.sleep(0.05)


def run_match(godot: Path, count: int, output: Path, visual: bool, dedicated: bool,
              weak_network: bool, server_binary: Path | None, managed: bool = False,
              remote_lobby: str | None = None, visual_size: str = "1280x720",
              visual_language: str = "zh", visual_renderer: str = "forward_plus") -> None:
    output.mkdir(parents=True, exist_ok=True)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as reservation:
        reservation.bind(("127.0.0.1", 0))
        port = reservation.getsockname()[1]

    processes = []
    clients = []
    logs = []
    links = []
    invite = secrets.token_hex(12) if dedicated else ""
    room_code = secrets.token_hex(6) if remote_lobby else ""
    scene = "res://tests/integration/team_room_client.tscn"
    try:
        if dedicated and not remote_lobby:
            server_log = output / "server.log"
            environment = test_environment(output / "server", invite)
            server_command = [str(server_binary or godot), "--headless"]
            if server_binary is None:
                server_command.extend(["--path", str(ROOT)])
            server_command.extend(["--", "--no-audio"])
            if managed:
                with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as reservation:
                    reservation.bind(("127.0.0.1", 0))
                    worker_port = reservation.getsockname()[1]
                server_command.extend(["--server", f"--lobby-port={port}",
                                       f"--port-start={worker_port}", f"--port-end={worker_port}"])
            else:
                server_command.extend(["--party-server", f"--party-port={port}", f"--party-size={count}"])
            with server_log.open("wb") as handle:
                server = subprocess.Popen(
                    server_command, cwd=server_binary.parent if server_binary else ROOT,
                    env=environment, stdout=handle, stderr=subprocess.STDOUT,
                )
            processes.append(server)
            wait_for_listener(server, server_log, "[SERVER] Lobby listening" if managed else "TEAM_SERVER_LISTENING")
        if dedicated and not managed:
            rejection_log = output / "incorrect-invite.log"
            with rejection_log.open("wb") as handle:
                rejection = subprocess.run(
                    [str(godot), "--headless", "--path", str(ROOT), "--scene", scene, "--",
                     "--no-audio", "--wrong-invite", f"--port={port}"],
                    cwd=ROOT, env=test_environment(output / "incorrect-invite", invite),
                    stdout=handle, stderr=subprocess.STDOUT, timeout=15,
                )
            if rejection.returncode != 0 or "TEAM_INVALID_INVITE_REJECTED" not in rejection_log.read_text(encoding="utf8"):
                raise RuntimeError(f"Room accepted an incorrect invite. See {rejection_log}")
        for index in range(count):
            profile = output / f"client-{index + 1}"
            env = test_environment(profile, invite)
            if remote_lobby:
                env.update(CARDEX_PARTY_TEST_LOBBY=remote_lobby, CARDEX_PARTY_TEST_ROOM=room_code)
            log = output / f"client-{index + 1}.log"
            engine_flags = ["--headless"]
            client_port = port
            if weak_network and (dedicated or index != 0):
                link = LocalUdpLink(port, 17 + index, 65, 25, 5)
                links.append(link)
                client_port = link.port
            if visual and index == 0:
                engine_flags = ["--rendering-method", visual_renderer, "--windowed",
                                "--resolution", visual_size, "--position", "-10000,-10000",
                                "--audio-driver", "Dummy"]
                settings = profile / "Godot" / "app_userdata" / "CardUGCGame" / "settings.cfg"
                settings.parent.mkdir(parents=True, exist_ok=True)
                settings.write_text(f"[presentation]\nwindow_mode=1\nmute=true\n[locale]\nlanguage=\"{visual_language}\"\n",
                                    encoding="utf8")
            command = [str(godot), *engine_flags, "--path", str(ROOT), "--scene",
                       scene, "--", "--no-audio",
                       f"--players={count}", f"--port={client_port}"]
            if managed:
                command.append("--managed-lobby")
            if visual and remote_lobby is None:
                command.append("--verify-aim")
            if index == 0:
                if not dedicated:
                    command.append("--host")
                if visual:
                    command.extend([f"--capture={output}", f"--window-size={visual_size}", "--background-visual-test"])
                if managed:
                    command.append("--create-room")
            with log.open("wb") as handle:
                client = subprocess.Popen(command, cwd=ROOT, env=env, stdout=handle, stderr=subprocess.STDOUT)
            clients.append(client)
            processes.append(client)
            logs.append(log)
            if index == 0 and not dedicated:
                wait_for_listener(client, log, "TEAM_HOST_LISTENING")
            elif index == 0 and (visual or managed):
                wait_for_listener(client, log, "TEAM_CLIENT_SEATED 1")

        deadline = time.monotonic() + (55 if weak_network else 35)
        reports = []
        for client, log in zip(clients, logs):
            status = client.wait(timeout=max(0.1, deadline - time.monotonic()))
            content = log.read_text(encoding="utf8", errors="replace")
            results = [line[len(MARKER):] for line in content.splitlines() if line.startswith(MARKER)]
            if status != 0 or len(results) != 1 or "ERROR:" in content:
                raise RuntimeError(f"Party client failed. See {log}")
            reports.append(json.loads(results[0]))

        seats = {item["seat"] for item in reports}
        all_hands = [card for report in reports for card in report["opening_hand"]]
        outcomes = {(report["winner"], tuple(report["hp"]), report["revision"]) for report in reports}
        if seats != set(range(1, count + 1)) or len(set(all_hands)) != len(all_hands) or len(outcomes) != 1:
            raise RuntimeError(f"Seats, independent opening hands, or outcomes disagreed. See {output}")
        if dedicated and not remote_lobby and (server.poll() is not None or "ERROR:" in server_log.read_text(encoding="utf8", errors="replace")):
            raise RuntimeError(f"Party server failed. See {server_log}")
        if weak_network:
            dropped = sum(stats["dropped"] for link in links for stats in link.stats.values())
            if not dropped or any(link.error for link in links):
                raise RuntimeError(f"The network fixture did not apply packet loss cleanly. See {output}")
            print(f"Delayed links dropped {dropped} datagrams", flush=True)
        mode = "room-code lobby" if managed else "dedicated server" if dedicated else "player-hosted room"
        print(f"PASS {count} seats in {mode}, independent hands and turns, synchronized elimination and victory", flush=True)
    finally:
        for client in reversed(processes):
            if client.poll() is None:
                client.kill()
                client.wait(timeout=5)
        for link in links:
            link.close()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("godot", type=Path)
    parser.add_argument("--output", type=Path, default=ROOT / "artifacts/team-integration")
    parser.add_argument("--players", type=int, choices=(3, 4, 5), nargs="+", default=(3, 4, 5))
    parser.add_argument("--visual", action="store_true", help="Render the host's lobby, battle, and result")
    parser.add_argument("--visual-size", default="1280x720", help="Window dimensions for the visual client")
    parser.add_argument("--visual-language", choices=("zh", "en"), default="zh")
    parser.add_argument("--visual-renderer", choices=("forward_plus", "gl_compatibility"), default="forward_plus")
    parser.add_argument("--dedicated", action="store_true", help="Run the party on a separate headless server")
    parser.add_argument("--managed-lobby", action="store_true", help="Create and join a party through the room-code lobby")
    parser.add_argument("--remote-lobby", help="Use an existing room-code lobby at HOST:PORT")
    parser.add_argument("--weak-network", action="store_true", help="Add local UDP delay, jitter, and packet loss")
    parser.add_argument("--server-binary", type=Path, help="Run a Windows export as the dedicated server")
    args = parser.parse_args()
    if args.remote_lobby:
        args.managed_lobby = True
        if args.server_binary:
            parser.error("--remote-lobby cannot launch a local server binary")
    if args.server_binary and not (args.dedicated or args.managed_lobby):
        parser.error("--server-binary requires a dedicated server mode")
    if args.managed_lobby and args.weak_network:
        parser.error("--weak-network requires a direct game endpoint")
    server_binary = args.server_binary.resolve(strict=True) if args.server_binary else None
    for count in args.players:
        run_match(args.godot.resolve(strict=True), count, args.output.resolve() / f"players-{count}",
                  args.visual, args.dedicated or args.managed_lobby, args.weak_network, server_binary,
                  args.managed_lobby, args.remote_lobby, args.visual_size, args.visual_language,
                  args.visual_renderer)


if __name__ == "__main__":
    main()
