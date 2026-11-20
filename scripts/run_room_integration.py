"""Verify the supported LAN room flow using two isolated real processes."""
import argparse
import json
import os
from pathlib import Path
import socket
import subprocess
import time
from local_udp_conditions import LocalUdpLink


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("godot")
    parser.add_argument("--output", default="artifacts/room-integration")
    parser.add_argument("--native", action="store_true", help="Render the room or battle screens under test")
    parser.add_argument("--copy-invite", action="store_true", help="Join a LAN room using the address copied by its native host")
    parser.add_argument("--language", choices=["zh", "en"], help="Set the test clients' display language")
    parser.add_argument("--incompatible-project", type=Path, help="Use a project with a different protocol for the first guest")
    parser.add_argument("--stall-card-art", action="store_true", help="Withhold the guest's first card-art receipt")
    parser.add_argument("--rematch", action="store_true", help="Return to the same LAN room before playing a second match")
    parser.add_argument("--results-guest-leaves", nargs="?", const="host-returns",
                        choices=["host-returns", "guest-leaves", "guest-link-lost"],
                        help="Replace a departing guest, with either player leaving results first")
    parser.add_argument("--edit-in-room", nargs="?", const="host",
                        choices=["host", "client", "solo-host", "client-leaves", "host-leaves"],
                        help="Exercise card editing during readiness, joining, or departure")
    parser.add_argument("--drop-editor-link", action="store_true",
                        help="Cut all guest room traffic instead of pressing Leave Room")
    args = parser.parse_args()
    if args.drop_editor_link and args.edit_in_room != "client-leaves":
        parser.error("--drop-editor-link requires --edit-in-room client-leaves")
    if args.results_guest_leaves and (args.rematch or args.edit_in_room or args.stall_card_art):
        parser.error("--results-guest-leaves runs a separate room scenario")
    if args.incompatible_project and (args.rematch or args.edit_in_room or args.stall_card_art or args.results_guest_leaves):
        parser.error("--incompatible-project runs a separate room scenario")
    if args.copy_invite and (not args.native or args.edit_in_room or args.results_guest_leaves or args.incompatible_project):
        parser.error("--copy-invite requires --native and runs with an ordinary LAN room")
    root = Path(__file__).resolve().parents[1]
    if args.native and os.name == "nt":
        from visual_test_windows import keep_windows_behind

        keep_windows_behind()
    output = (root / args.output / str(time.time_ns())).resolve()
    output.mkdir(parents=True)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    processes = []
    handles = []
    records = []
    drop_results_link = args.results_guest_leaves == "guest-link-lost"
    guest_link = LocalUdpLink(port, 42, 0, 0, 0) if args.drop_editor_link or drop_results_link else None
    try:
        refill_room = args.incompatible_project or args.results_guest_leaves or args.edit_in_room == "client-leaves"
        roles = ["host", "client", "replacement"] if refill_room else ["host", "client"]
        for role in roles:
            profile = output / ("profile-" + role)
            profile.mkdir()
            env = os.environ.copy()
            for key in ["APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME"]:
                env[key] = str(profile)
            log = output / (role + ".log")
            handle = log.open("wb")
            handles.append(handle)
            native_role = "host" if refill_room or args.copy_invite else "client"
            native = args.native and (role == native_role or ((drop_results_link or args.incompatible_project) and role == "client"))
            display = ["--position", "-10000,-10000"] if native else ["--headless"]
            if native and os.name == "nt":
                display.append("--windowed")
            connection_port = guest_link.port if guest_link and role == "client" else port
            project = args.incompatible_project.resolve() if args.incompatible_project and role == "client" else root
            command = [args.godot] + display + ["--path", str(project), "--scene",
                       "res://tests/integration/lobby_room_client.tscn", "--",
                       "--role=" + ("client" if role == "replacement" else role), "--port=" + str(connection_port), "--no-audio"]
            if native:
                if os.name == "nt":
                    command.append("--background-visual-test")
                command.append("--screenshot=" + str(output / "disconnect-result.png"))
            if args.language:
                command.append("--language=" + args.language)
            if args.copy_invite:
                command.append("--invite-file=" + str(output / "copied-endpoint"))
            if args.incompatible_project and role != "replacement":
                command.append("--test-lan-protocol-mismatch")
            if args.stall_card_art:
                command.append("--stall-card-art")
            if args.rematch:
                command.append("--rematch")
            if args.results_guest_leaves and role != "replacement":
                command.append("--results-guest-leaves=" + args.results_guest_leaves)
                if args.results_guest_leaves != "host-returns":
                    command.append("--results-host-ready=" + str(output / "host-showing-results"))
            if role == "replacement" and args.edit_in_room == "client-leaves":
                command.append("--replacing-editor-peer")
            if args.edit_in_room and role != "replacement":
                command.extend(["--editing-gate=" + str(output / "editing-verified"),
                                "--editing-side=" + args.edit_in_room])
            if args.drop_editor_link:
                command.append("--drop-editor-link")
            process = subprocess.Popen(command, cwd=root, env=env, stdout=handle, stderr=subprocess.STDOUT)
            processes.append(process)
            records.append({"role": role, "command": command, "log": str(log)})
            if role == "host":
                deadline = time.monotonic() + 10
                marker = "TEST_ROOM_COPIED_ENDPOINT_HOST" if args.copy_invite else "Hosting on port"
                while process.poll() is None and time.monotonic() < deadline:
                    if marker in log.read_text(encoding="utf8", errors="replace"):
                        break
                    time.sleep(.05)
                else:
                    raise RuntimeError("Room host did not start; see " + str(log))
            if role == "client" and refill_room:
                host_log = Path(records[0]["log"])
                if guest_link:
                    cut_marker = "TEST_ROOM_RESULTS_CUT_READY" if drop_results_link else "TEST_ROOM_EDITOR_PEER_CUT_READY"
                    deadline = time.monotonic() + (28 if drop_results_link else 12)
                    while time.monotonic() < deadline and process.poll() is None:
                        if cut_marker in log.read_text(encoding="utf8", errors="replace"):
                            guest_link.start_outage(35)
                            break
                        time.sleep(.05)
                    else:
                        raise RuntimeError("Guest never reached the planned link cut; see " + str(log))
                marker = "TEST_ROOM_EDITOR_HOST_RETAINED"
                if args.incompatible_project:
                    marker = "TEST_ROOM_INCOMPATIBLE_HOST_RETAINED"
                elif args.results_guest_leaves:
                    marker = "TEST_ROOM_RESULTS_HOST_RETAINED"
                deadline = time.monotonic() + 16
                while time.monotonic() < deadline and processes[0].poll() is None and process.poll() in (None, 0):
                    if marker in host_log.read_text(encoding="utf8", errors="replace"):
                        break
                    time.sleep(.05)
                else:
                    break
        deadline = time.monotonic() + (55 if args.rematch or args.results_guest_leaves else 35)
        while any(process.poll() is None for process in processes) and time.monotonic() < deadline:
            if any(process.poll() not in [None, 0] for process in processes):
                break
            time.sleep(.05)
    finally:
        for process in processes:
            if process.poll() is None:
                process.kill()
            process.wait()
        for handle in handles:
            handle.close()
        if guest_link:
            guest_link.close()
        for record, process in zip(records, processes):
            text = Path(record["log"]).read_text(encoding="utf8", errors="replace")
            role = "CLIENT" if record["role"] == "replacement" else record["role"].upper()
            if args.edit_in_room == "host-leaves":
                markers = ["TEST_ROOM_EDITOR_PEER_LEFT" if role == "HOST" else "TEST_ROOM_EDITOR_CLIENT_BACK"]
            elif args.edit_in_room == "client-leaves" and record["role"] == "client":
                markers = ["TEST_ROOM_EDITOR_PEER_LEFT"]
            elif args.results_guest_leaves and record["role"] == "client":
                markers = ["TEST_ROOM_RESULTS_GUEST_LINK_LOST" if drop_results_link else "TEST_ROOM_RESULTS_GUEST_LEFT"]
            elif args.incompatible_project and record["role"] == "client":
                markers = ["TEST_ROOM_INCOMPATIBLE_GUEST_RETRY"]
            else:
                markers = ["TEST_ROOM_RULES_SYNC_" + role, "TEST_ROOM_READY_" + role, "TEST_ROOM_CANCEL_READY_" + role]
                if args.rematch:
                    markers.append("TEST_ROOM_REMATCH_" + role)
                if args.results_guest_leaves and role == "HOST":
                    markers.append("TEST_ROOM_RESULTS_HOST_RETAINED")
                if args.incompatible_project and role == "HOST":
                    markers.append("TEST_ROOM_INCOMPATIBLE_HOST_RETAINED")
                if args.copy_invite:
                    markers.append("TEST_ROOM_COPIED_ENDPOINT_" + role)
                if role == "CLIENT":
                    markers.extend(["TEST_ROOM_DISCONNECT_NO_RECONNECT_OK", "TEST_ROOM_DISCONNECT_BACK_TO_MULTIPLAYER_OK"])
                    if args.stall_card_art:
                        markers.append("TEST_ROOM_ART_FALLBACK_CLIENT")
                else:
                    markers.append("TEST_ROOM_MATCH_STARTED_HOST")
                if args.edit_in_room == "client-leaves" and role == "HOST":
                    markers.append("TEST_ROOM_EDITOR_HOST_RETAINED")
                elif args.edit_in_room and record["role"] != "replacement":
                    markers.append("TEST_ROOM_EDITOR_RETURN_" + role)
            record.update(exit=process.returncode, passed=process.returncode == 0
                          and all(marker in text for marker in markers)
                          and not any(error in text for error in ["ERROR:", "SCRIPT ERROR", "FAILED"]))
        (output / "verification.json").write_text(json.dumps(records, indent=2), encoding="utf8")
        if guest_link:
            evidence = {"outage_drops": guest_link.outage_drops, "error": guest_link.error}
            (output / "link-verification.json").write_text(json.dumps(evidence, indent=2), encoding="utf8")
    print(json.dumps({"output": str(output), "clients": records}, indent=2))
    link_verified = guest_link is None or (not guest_link.error and all(guest_link.outage_drops.values()))
    return 0 if link_verified and len(records) == len(roles) and all(record["passed"] for record in records) else 1


if __name__ == "__main__":
    raise SystemExit(main())
