"""Exercise both matchmade modes with two real Godot clients."""
import argparse
import os
from pathlib import Path
from random import SystemRandom
import signal
import socket
import subprocess
import time

from run_team_integration import ROOT, test_environment, wait_for_listener


def run_match(godot: Path, mode: str, output: Path, native: bool, size: str, language: str,
              light: bool, server_binary: Path | None, cancel_pending: bool, leave_room: bool, retry_entry: bool) -> None:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as lobby, socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as room:
        lobby.bind(("127.0.0.1", 0))
        # Do not reserve the subprocess port from the client's ephemeral range.
        for candidate in SystemRandom().sample(range(22000, 35000), 15):
            try:
                room.bind(("0.0.0.0", candidate))
                break
            except OSError:
                continue
        else:
            raise RuntimeError("No test room port available")
        lobby_port, room_port = lobby.getsockname()[1], room.getsockname()[1]
    processes = []

    def launch(role, scene, arguments, render=False):
        profile = output / role
        environment = test_environment(profile, "")
        log = profile / "run.log"
        flags = ["--headless"]
        if render:
            flags = ["--rendering-method", "gl_compatibility", "--windowed",
                     "--resolution", size, "--position", "-10000,-10000", "--audio-driver", "Dummy"]
            arguments += [f"--capture={profile}", f"--window-size={size}", "--background-visual-test"]
            if light:
                arguments.append("--light")
        executable = server_binary if role == "server" else None
        invocation = [str(executable), "--headless", "--", "--server"] if executable else [
            str(godot), *flags, "--path", str(ROOT), "--scene", "res://" + scene, "--"]
        with log.open("wb") as stream:
            process = subprocess.Popen(
                [*invocation, "--no-audio", *arguments], cwd=executable.parent if executable else ROOT, env=environment,
                stdout=stream, stderr=subprocess.STDOUT, start_new_session=os.name != "nt")
        processes.append(process)
        return process, log

    try:
        server, server_log = launch("server", "server.tscn", [
            f"--lobby-port={lobby_port}", f"--port-start={room_port}", f"--port-end={room_port}"])
        wait_for_listener(server, server_log, "[SERVER] Lobby listening")
        common = [f"--matchmaking-endpoint=127.0.0.1:{lobby_port}", f"--{mode}", f"--language={language}"]
        if leave_room:
            common.append(f"--leave-room-marker={output / 'preparation-open'}")
        scene = "tests/integration/matchmaking_client.tscn"
        cancel_args = [*common, "--cancel-only"]
        if retry_entry:
            cancel_args.append("--retry-entry")
        if cancel_pending:
            winner = launch("winner", scene, list(common), render=native)
            wait_for_listener(*winner, f"TEST_MATCHMAKING_WAITING {mode}")
            pending = output / "server" / "Godot" / "app_userdata" / "CardUGCGame" / "matchmaking"
            cancel_args.append(f"--cancel-pending-in={pending}")
        cancelled, cancel_log = launch("cancel", scene, cancel_args, render=native and retry_entry)
        cancel_status = cancelled.wait(timeout=22 if retry_entry else 12)
        cancel_content = cancel_log.read_text(encoding="utf8", errors="replace")
        if cancel_status != 0 or "ERROR:" in cancel_content or f"TEST_MATCHMAKING_CANCEL_OK {mode}" not in cancel_content:
            raise RuntimeError(f"{mode} cancellation failed. See {cancel_log}")
        surrender = launch("surrender", scene, [*common, "--surrender"], render=native)
        if not cancel_pending:
            winner = launch("winner", scene, list(common), render=native)
        clients = [surrender, winner]
        for client, log in clients:
            status = client.wait(timeout=32)
            content = log.read_text(encoding="utf8", errors="replace")
            if status != 0 or "ERROR:" in content or f"TEST_MATCHMAKING_CLIENT_OK {mode}" not in content:
                raise RuntimeError(f"{mode} client failed. See {log}")
        content = server_log.read_text(encoding="utf8", errors="replace")
        if "ERROR:" in content:
            raise RuntimeError(f"{mode} lobby reported an error. See {server_log}")
        print(f"{mode}: passed ({output})", flush=True)
    finally:
        for process in reversed(processes):
            if process.poll() is not None:
                continue
            if os.name == "nt":
                subprocess.run(["taskkill", "/T", "/F", "/PID", str(process.pid)], capture_output=True, check=False)
            else:
                os.killpg(process.pid, signal.SIGTERM)
            process.wait(timeout=5)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", type=Path, default=Path(os.environ.get("GODOT_BIN") or
                        "D:/XunLeiXiaZai/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe"))
    parser.add_argument("--mode", choices=("ranked", "random", "both"), default="both")
    parser.add_argument("--native", action="store_true")
    parser.add_argument("--size", default="1280x720")
    parser.add_argument("--language", choices=("zh", "en"), default="zh")
    parser.add_argument("--light", action="store_true")
    parser.add_argument("--server-binary", type=Path)
    parser.add_argument("--cancel-pending", action="store_true", help="Cancel during room startup and match the survivor again")
    parser.add_argument("--leave-room", action="store_true", help="Leave the preparation room and check both clients return")
    parser.add_argument("--retry-entry", action="store_true", help="Start on an unavailable endpoint, then retry on the test server")
    args = parser.parse_args()
    output = ROOT / "artifacts" / "matchmaking-integration" / str(time.time_ns())
    output.mkdir(parents=True)
    if args.native and os.name == "nt":
        from visual_test_windows import keep_windows_behind
        keep_windows_behind()
    modes = ("ranked", "random") if args.mode == "both" else (args.mode,)
    server_binary = args.server_binary.resolve(strict=True) if args.server_binary else None
    for mode in modes:
        target = output / mode
        target.mkdir()
        run_match(args.godot, mode, target, args.native, args.size, args.language, args.light, server_binary,
                  args.cancel_pending, args.leave_room, args.retry_entry)


if __name__ == "__main__":
    main()
