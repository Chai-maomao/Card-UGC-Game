"""Exercise the actual lobby server, room child and isolated game clients."""
import argparse
import json
import os
from pathlib import Path
import re
import socket
import signal
import subprocess
import time
from local_udp_conditions import LocalUdpLink


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("godot")
    parser.add_argument("--address", help="Read-only public status probe; does not create a room")
    parser.add_argument("--native", action="store_true", help="Render the waiting room or outage result and the full-room form")
    parser.add_argument("--language", choices=("zh", "en"), help="Set the test clients' display language")
    parser.add_argument("--server-binary", type=Path, help="Use an exported server executable with its pack")
    parser.add_argument("--weak-network", action="store_true", help="Apply 80 ± 35 ms one-way delay and 7%% loss locally")
    rules_scenario = parser.add_mutually_exclusive_group()
    rules_scenario.add_argument("--live-rule-view", action="store_true", help="Verify a guest's open rules dialog follows the host's changes")
    rules_scenario.add_argument("--ready-before-rules", action="store_true", help="Ready the host before sending its rule preview to the guest")
    fault = parser.add_mutually_exclusive_group()
    fault.add_argument("--hold-gameplay-replies", action="store_true", help="Drop the guest's ordinary gameplay replies for 5 seconds")
    fault.add_argument("--hold-unreliable-probes", action="store_true", help="Drop the guest's unreliable room probe replies while reliable traffic still flows")
    fault.add_argument("--end-turn-timeout", action="store_true", help="Hold the guest turn and the host snapshot until the guest's command times out")
    fault.add_argument("--discard-timeout", action="store_true", help="Hold a predicted discard and the host snapshot until the guest's command times out")
    fault.add_argument("--discard-rejection", action="store_true", help="Advance the host revision before its first guest discard and verify a rejected action can be retried")
    fault.add_argument("--combat-checkpoint", action="store_true", help="Reconcile a guest attack and active skill before their ordinary replies arrive")
    fault.add_argument("--stationary-aim", action="store_true", help="Render a guest aiming at one target and cancelling with Escape")
    fault.add_argument("--skill-result", nargs="?", const="host", choices=("host", "guest"),
                       help="Finish the first match with a lethal skill. The guest case also sends an in-flight follow-up")
    fault.add_argument("--short-outage", action="store_true", help="Cut the guest's room traffic in both directions for 9.5 seconds")
    fault.add_argument("--waiting-outage", action="store_true", help="Cut the guest's traffic before Ready and during match confirmation")
    fault.add_argument("--return-during-outage", action="store_true", help="Return from the first result during a guest connection interruption")
    fault.add_argument("--editor-outage", action="store_true", help="Save a locally edited card while the host's room traffic is interrupted")
    fault.add_argument("--long-outage", action="store_true", help="Isolate the host during the rematch until both clients see its end")
    fault.add_argument("--replay-prior-match", action="store_true", help="Deliver the preceding match's turn and snapshot after starting a rematch")
    fault.add_argument("--replay-prior-offer", action="store_true", help="Deliver a cancelled rules offer after both players return to preparation")
    fault.add_argument("--offer-deck-mismatch", action="store_true", help="Deliver a second confirmation with a different deck digest and verify both players can retry")
    fault.add_argument("--confirmation-progress", action="store_true", help="Verify room feedback while waiting for the other player and while starting the match")
    fault.add_argument("--no-match-start", action="store_true", help="Hold back the host's start after both confirmations, then return to preparation")
    fault.add_argument("--join-during-results", action="store_true", help="Fill the vacated seat while the promoted host is still viewing the result")
    fault.add_argument("--leave-from-results", action="store_true", help="Leave from the battle result and press Escape before the room acknowledges departure")
    fault.add_argument("--stall-card-art", action="store_true", help="Withhold one client's card-art receipt until the first match")
    fault.add_argument("--cancel-entry", action="store_true", help="Cancel a guest join while the room connection is still opening")
    fault.add_argument("--cancel-entry-timeout", action="store_true", help="Hold authentication until the guest cancels, then verify reservation feedback and retry")
    fault.add_argument("--reject-room-handoff", nargs="?", const="invalid_token",
                       choices=("invalid_token", "slot_in_use", "protocol_mismatch"),
                       help="Exercise a room authentication rejection and retry from the restored join form")
    fault.add_argument("--leave-during-confirmation", action="store_true", help="Verify an arriving match offer waits for the guest to decide whether to leave")
    parser.add_argument("--block-resumed-intents", action="store_true", help="Keep the ordinary uplink blocked for 5 seconds after --short-outage ends")
    parser.add_argument("--outage-after-results", action="store_true", help="Show a completed result on both clients before the sustained host outage")
    parser.add_argument("--start-timeout-race", choices=("start-first", "reset-first"), help="Check either server ordering of a delayed start and return to preparation")
    parser.add_argument("--cancel-while-leave-open", action="store_true", help="Have the host cancel preparation while the guest is deciding whether to leave")
    parser.add_argument("--room-card-overlays", action="store_true", help="Verify card detail overlays close on withdrawn readiness and match confirmation")
    parser.add_argument("--cancel-during-confirmation-outage", action="store_true", help="Queue Cancel Ready during the confirmation interruption")
    parser.add_argument("--checkpoint-before-rejection", action="store_true", help="Deliver room checkpoints before ordinary rejection and discard replies")
    parser.add_argument("--checkpoint-after-action-timeout", action="store_true", help="Block discard checkpoint requests until the guest command times out")
    parser.add_argument("--checkpoint-same-revision", action="store_true", help="Reject the timed-out discard without advancing the battle revision")
    parser.add_argument("--checkpoint-rejected-chain", action="store_true", help="Reject consecutive guest discards that depend on an unconfirmed first discard")
    parser.add_argument("--terminal-cancel-outage", action="store_true", help="Keep the cancellation link down until the room expires the guest's connection")
    parser.add_argument("--room-deck-keyboard", action="store_true", help="Verify card focus, inspection and deck switching in the host's room")
    parser.add_argument("--room-invite", action="store_true", help="Verify room-code copying in a native run or the unavailable-clipboard fallback headless")
    parser.add_argument("--invalid-local-deck", action="store_true", help="Verify an incompatible local deck is rejected before readiness is submitted")
    parser.add_argument("--seed", type=int, default=42, help="Seed used for local network conditions")
    args = parser.parse_args()
    if args.stationary_aim and not args.native:
        parser.error("--stationary-aim requires --native for the guest's pointer")
    if args.block_resumed_intents and not args.short_outage:
        parser.error("--block-resumed-intents requires --short-outage")
    if args.outage_after_results and not args.long_outage:
        parser.error("--outage-after-results requires --long-outage")
    if args.start_timeout_race and not args.no_match_start:
        parser.error("--start-timeout-race requires --no-match-start")
    if args.cancel_while_leave_open and not args.leave_during_confirmation:
        parser.error("--cancel-while-leave-open requires --leave-during-confirmation")
    if args.room_card_overlays and not args.ready_before_rules:
        parser.error("--room-card-overlays requires --ready-before-rules")
    if args.cancel_during_confirmation_outage and not args.waiting_outage:
        parser.error("--cancel-during-confirmation-outage requires --waiting-outage")
    if args.terminal_cancel_outage and not args.cancel_during_confirmation_outage:
        parser.error("--terminal-cancel-outage requires --cancel-during-confirmation-outage")
    if args.checkpoint_before_rejection and not args.discard_rejection:
        parser.error("--checkpoint-before-rejection requires --discard-rejection")
    if args.checkpoint_after_action_timeout and not args.checkpoint_before_rejection:
        parser.error("--checkpoint-after-action-timeout requires --checkpoint-before-rejection")
    if args.checkpoint_same_revision and not args.checkpoint_after_action_timeout:
        parser.error("--checkpoint-same-revision requires --checkpoint-after-action-timeout")
    if args.checkpoint_rejected_chain and not args.checkpoint_same_revision:
        parser.error("--checkpoint-rejected-chain requires --checkpoint-same-revision")
    root = Path(__file__).resolve().parents[1]
    if args.native and os.name == "nt":
        from visual_test_windows import keep_windows_behind

        keep_windows_behind()
    output = root / "artifacts/dedicated-integration" / str(time.time_ns())
    output.mkdir(parents=True)
    processes, records, handles = [], [], []
    links = {}
    gameplay_drop_end_ms = 0
    outage_end_ms = 0
    guest_turn_latency_ms = None
    outage_recovery_ms = None
    waiting_outages = {}
    long_outage_started_ms = None
    long_outage_result_ms = {}

    def launch(role, extra):
        profile = output / ("profile-" + role)
        profile.mkdir()
        env = os.environ.copy()
        for key in ["APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME"]:
            env[key] = str(profile.resolve())
        log = output / (role + ".log")
        stream = log.open("wb")
        handles.append(stream)
        scene = "server.tscn" if role == "server" else "tests/integration/dedicated_room_client.tscn"
        if args.language and role != "server":
            extra = extra + ["--language=" + args.language]
        if args.live_rule_view and role in ("owner", "survivor", "replacement"):
            extra = extra + ["--live-rule-view"]
        if args.ready_before_rules and role in ("owner", "survivor"):
            extra = extra + ["--ready-before-rules"]
        if args.room_card_overlays and role in ("owner", "survivor", "replacement"):
            extra = extra + ["--room-card-overlays"]
        if args.room_deck_keyboard and role == "owner":
            extra = extra + ["--room-deck-keyboard"]
        if args.room_invite and role == "owner":
            extra = extra + ["--room-invite"]
        if args.invalid_local_deck and role == "survivor":
            extra = extra + ["--invalid-local-deck"]
        if args.leave_during_confirmation and role == "replacement":
            extra = extra + ["--leave-during-confirmation"]
        if args.cancel_while_leave_open and role in ("survivor", "replacement"):
            extra = extra + ["--cancel-while-leave-open"]
        native_role = "cancelling_guest" if args.cancel_entry or args.cancel_entry_timeout else "replacement" if args.short_outage or args.waiting_outage or args.replay_prior_offer or args.return_during_outage or args.offer_deck_mismatch or args.confirmation_progress or args.no_match_start or args.end_turn_timeout or args.discard_timeout or args.discard_rejection or args.combat_checkpoint or args.stationary_aim else "survivor"
        if args.join_during_results:
            native_role = "rejoin"
        elif args.leave_from_results:
            native_role = "replacement"
        native = args.native and (
            role == native_role or (role in ("owner", "full", "reserved") and not args.weak_network)
            or (role == "replacement" and (args.live_rule_view or args.leave_during_confirmation or args.room_card_overlays or args.outage_after_results or args.skill_result))
        )
        display = ["--position", "-10000,-10000"] if native else ["--headless"]
        if native and os.name == "nt":
            display.append("--windowed")
            extra = extra + ["--background-visual-test"]
        if native:
            if role == "full":
                screenshot = "room-entry-full.png"
            elif role == "reserved":
                screenshot = "room-entry-seat-reserved.png"
            elif role == "owner":
                screenshot = "room-entry-after-leave.png"
            elif args.cancel_entry or args.cancel_entry_timeout:
                screenshot = "room-entry-cancelled.png"
            elif args.stall_card_art:
                screenshot = "card-art-fallback.png"
            elif args.waiting_outage:
                screenshot = "waiting-outage.png"
            elif args.return_during_outage:
                screenshot = "return-during-outage.png"
            elif args.replay_prior_offer:
                screenshot = "new-rule-confirmation.png"
            elif args.join_during_results:
                screenshot = "join-during-results.png"
            else:
                screenshot = f"result-outage-{role}.png" if args.outage_after_results else "long-outage.png" if args.long_outage else "short-outage.png" if args.short_outage else "waiting-room.png"
            extra = extra + ["--screenshot=" + str(output / screenshot)]
        executable, cwd = args.godot, root
        entry = ["--path", str(root), "--scene", "res://" + scene, "--"]
        if role == "server" and args.server_binary:
            executable = str(args.server_binary.resolve())
            cwd = args.server_binary.resolve().parent
            entry = ["--", "--server"]
        command = [executable] + display + entry + ["--no-audio"] + extra
        process = subprocess.Popen(command, cwd=cwd, env=env, stdout=stream, stderr=subprocess.STDOUT,
                                   start_new_session=os.name != "nt")
        processes.append(process)
        record = {"role": role, "log": str(log), "pid": process.pid}
        records.append(record)
        return process, record

    def wait_for(process, record, marker, timeout=20):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            text = Path(record["log"]).read_text(encoding="utf8", errors="replace")
            if "SCRIPT ERROR" in text or "ERROR:" in text:
                raise RuntimeError(record["role"] + " reported an error: " + text[-1800:])
            if marker in text:
                return
            if process.poll() is not None:
                raise RuntimeError(record["role"] + " exited before " + marker + ": " + text[-1800:])
            for other, other_record in zip(processes, records):
                if other != process and other.poll() not in (None, 0):
                    log_text = Path(other_record["log"]).read_text(encoding="utf8", errors="replace")
                    raise RuntimeError(other_record["role"] + " exited unexpectedly: " + log_text[-1800:])
            time.sleep(.05)
        raise RuntimeError(record["role"] + " timed out waiting for " + marker)

    passed, error = False, ""
    try:
        if args.address:
            client, record = launch("probe", ["--role=probe", "--address=" + args.address])
            wait_for(client, record, "SERVER_STATUS_OK")
        else:
            def free_port():
                with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
                    probe.bind(("127.0.0.1", 0))
                    return probe.getsockname()[1]
            lobby_port, room_port = free_port(), free_port()
            server_args = [f"--lobby-port={lobby_port}", f"--port-start={room_port}", f"--port-end={room_port}"]
            if args.stall_card_art:
                server_args.append("--allow-card-art")
            server, record = launch("server", server_args)
            wait_for(server, record, "Lobby listening on port")
            code = "QA" + str(time.time_ns())[-10:]
            gate = (output / "owner-may-leave").resolve()
            common = ["--code=" + code, "--leave-gate=" + str(gate)]

            if not args.weak_network:
                with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as silent_lobby:
                    silent_lobby.bind(("127.0.0.1", 0))
                    silent_port = silent_lobby.getsockname()[1]
                    client, client_record = launch("unreachable", ["--role=unreachable", f"--lobby-port={silent_port}"] + common)
                    wait_for(client, client_record, "DEDICATED_ENTRY_TIMEOUT_OK")

            def launch_client(role):
                port = lobby_port
                extra = []
                cut_link = ((args.hold_gameplay_replies or args.hold_unreliable_probes or args.short_outage or args.waiting_outage or args.return_during_outage or args.combat_checkpoint)
                            and role == "replacement") or ((args.long_outage or args.editor_outage) and role == "survivor")
                if args.checkpoint_before_rejection and role == "replacement":
                    cut_link = True
                    extra.append("--checkpoint-before-rejection")
                    if args.checkpoint_after_action_timeout:
                        extra.append("--checkpoint-after-action-timeout")
                if args.combat_checkpoint and role in ("survivor", "replacement"):
                    extra.append("--combat-checkpoint")
                if args.stationary_aim and role in ("survivor", "replacement"):
                    extra.append("--stationary-aim")
                if args.skill_result and role in ("survivor", "replacement"):
                    extra.append("--skill-result=" + args.skill_result)
                if args.start_timeout_race == "start-first" and role == "replacement":
                    cut_link = True
                if args.weak_network or cut_link:
                    conditions = (80, 35, 7) if args.weak_network else (0, 0, 0)
                    for kind, target_port in [("lobby", lobby_port), ("room", room_port)]:
                        links[role + "-" + kind] = LocalUdpLink(target_port, args.seed + len(links), *conditions)
                    port = links[role + "-lobby"].port
                    extra.append(f"--room-proxy-port={links[role + '-room'].port}")
                if (args.hold_gameplay_replies or args.hold_unreliable_probes) and role in ("survivor", "replacement"):
                    extra.append("--hold-gameplay-replies")
                if args.end_turn_timeout and role in ("survivor", "replacement"):
                    extra.append("--end-turn-timeout")
                if args.discard_timeout and role in ("survivor", "replacement"):
                    extra.append("--discard-timeout")
                if args.discard_rejection and role in ("survivor", "replacement"):
                    extra.append("--discard-rejection")
                    if args.checkpoint_same_revision:
                        extra.append("--checkpoint-same-revision")
                    if args.checkpoint_rejected_chain:
                        extra.append("--checkpoint-rejected-chain")
                if args.short_outage and role in ("survivor", "replacement"):
                    extra.append("--short-outage")
                if args.waiting_outage and role == "replacement":
                    extra.append("--waiting-outage")
                if args.cancel_during_confirmation_outage and role in ("survivor", "replacement"):
                    extra.append("--cancel-during-confirmation-outage")
                if args.terminal_cancel_outage and role in ("survivor", "replacement"):
                    extra.append("--terminal-cancel-outage")
                if args.return_during_outage and role == "replacement":
                    extra.append("--return-during-outage")
                if args.editor_outage and role == "survivor":
                    extra.append("--editor-outage")
                if args.long_outage and role in ("survivor", "replacement", "rejoin"):
                    extra.append("--long-outage")
                    if args.outage_after_results and role != "rejoin":
                        extra.append("--outage-after-results")
                if args.replay_prior_match and role in ("survivor", "replacement"):
                    extra.append("--replay-prior-match")
                if args.replay_prior_offer and role in ("survivor", "replacement"):
                    extra.append("--replay-prior-offer")
                if args.offer_deck_mismatch and role in ("survivor", "replacement"):
                    extra.append("--offer-deck-mismatch")
                if args.confirmation_progress and role in ("survivor", "replacement"):
                    extra.append("--confirmation-progress")
                if args.no_match_start and role in ("survivor", "replacement"):
                    extra.append("--no-match-start")
                    if args.start_timeout_race:
                        extra.append("--start-timeout-race=" + args.start_timeout_race)
                if args.reject_room_handoff and role in ("owner", "survivor"):
                    extra.append("--reject-room-handoff=" + args.reject_room_handoff)
                if args.join_during_results and role in ("replacement", "rejoin"):
                    extra.append("--join-during-results")
                if args.leave_from_results and role == "replacement":
                    extra.append("--leave-from-results")
                if args.stall_card_art and role in ("survivor", "replacement"):
                    extra.append("--stall-card-art")
                return launch(role, ["--role=" + role, f"--lobby-port={port}"] + common + extra)

            owner, owner_record = launch_client("owner")
            wait_for(owner, owner_record, "DEDICATED_JOINED_OWNER")
            if not args.weak_network:
                wait_for(owner, owner_record, "DEDICATED_ENTRY_CANCEL_OK")
                wait_for(owner, owner_record, "DEDICATED_ENTRY_RETRY_OK")
            if args.room_invite:
                wait_for(owner, owner_record, "DEDICATED_ROOM_INVITE_OK")
            if args.cancel_entry or args.cancel_entry_timeout:
                cancel_options = ["--stall-entry-authentication"] if args.cancel_entry_timeout else []
                cancelling_guest, cancelling_record = launch("cancelling_guest", [
                    "--role=cancelling_guest", f"--lobby-port={lobby_port}",
                ] + common + cancel_options)
                if args.cancel_entry_timeout:
                    wait_for(cancelling_guest, cancelling_record, "DEDICATED_RESERVATION_ACTIVE")
                    reserved, reserved_record = launch("reserved", [
                        "--role=reserved", f"--lobby-port={lobby_port}",
                    ] + common)
                    wait_for(reserved, reserved_record, "DEDICATED_RESERVED_OK")
                    Path(str(gate) + ".reservation-checked").write_text("another client saw the reservation", encoding="utf8")
                    wait_for(cancelling_guest, cancelling_record, "DEDICATED_RESERVATION_RETRY_OK")
                    wait_for(server, record, f"Room '{code}' resumed the existing P2 reservation")
                wait_for(cancelling_guest, cancelling_record, "DEDICATED_ASSIGNED_JOIN_CANCELLED",
                         timeout=30 if args.cancel_entry_timeout else 20)
            survivor, survivor_record = launch_client("survivor")
            if args.reject_room_handoff:
                wait_for(survivor, survivor_record, "DEDICATED_HANDOFF_REJECTION_RECOVERED")
            wait_for(survivor, survivor_record, "DEDICATED_JOINED_SURVIVOR")
            if args.ready_before_rules:
                wait_for(survivor, survivor_record, "DEDICATED_EARLY_OPPONENT_READY_OK")
            if args.live_rule_view:
                wait_for(survivor, survivor_record, "DEDICATED_LIVE_RULE_VIEW_OK")
            # Prove occupancy is authoritative after the old 15 second join
            # reservation has expired, rather than accidentally testing the TTL.
            time.sleep(15.2)
            full, full_record = launch_client("full")
            wait_for(full, full_record, "DEDICATED_FULL_OK")
            gate.write_text("full room verified", encoding="utf8")
            wait_for(owner, owner_record, "DEDICATED_OWNER_LEFT_OK")
            wait_for(owner, owner_record, "DEDICATED_EXIT_CANCEL_OK")
            wait_for(survivor, survivor_record, "DEDICATED_PROMOTED_OK")
            replacement, replacement_record = launch_client("replacement")
            wait_for(replacement, replacement_record, "DEDICATED_EDITOR_STATUS_OK")
            if args.editor_outage:
                wait_for(survivor, survivor_record, "DEDICATED_EDITOR_OUTAGE_ARMED")
                editor_link = links["survivor-room"]
                editor_link.start_outage(9.5)
                wait_for(survivor, survivor_record, "DEDICATED_EDITOR_OUTAGE_SAVED")
                if not all(editor_link.outage_drops.values()):
                    raise RuntimeError("The editor interruption did not drop traffic in both directions")
                wait_for(survivor, survivor_record, "DEDICATED_EDITOR_OUTAGE_RECOVERED")
            if args.waiting_outage:
                wait_for(replacement, replacement_record, "DEDICATED_WAITING_OUTAGE_ARMED")
                guest_link = links["replacement-room"]
                end_ms = guest_link.start_outage(8.5)
                Path(str(gate) + ".waiting-outage").write_text("waiting room link interrupted", encoding="utf8")
                wait_for(replacement, replacement_record, "DEDICATED_WAITING_OUTAGE_PAUSE_OK")
                wait_for(replacement, replacement_record, "DEDICATED_WAITING_OUTAGE_RECOVERY_OK")
                waiting_outages["before_ready"] = {"end_unix_ms": end_ms, "dropped": guest_link.outage_drops.copy()}
                if not all(waiting_outages["before_ready"]["dropped"].values()):
                    raise RuntimeError("The waiting room outage did not drop packets in both directions")
            wait_for(survivor, survivor_record, "DEDICATED_RULE_DRAFT_LOCKED_OK")
            if args.invalid_local_deck:
                wait_for(survivor, survivor_record, "DEDICATED_LOCAL_DECK_VALIDATION_OK")
            if args.stall_card_art:
                wait_for(survivor, survivor_record, "DEDICATED_ART_CONFIRMATION_SURVIVOR")
                wait_for(replacement, replacement_record, "DEDICATED_ART_CONFIRMATION_REPLACEMENT")
            wait_for(replacement, replacement_record, "DEDICATED_CANCELLED_REPLACEMENT_OK")
            wait_for(survivor, survivor_record, "DEDICATED_CANCELLED_SURVIVOR_OK")
            if args.replay_prior_offer:
                wait_for(replacement, replacement_record, "DEDICATED_CANCELLED_OFFER_IGNORED")
            if args.offer_deck_mismatch:
                wait_for(replacement, replacement_record, "DEDICATED_MISMATCH_INJECTED")
                wait_for(replacement, replacement_record, "DEDICATED_MISMATCH_RECOVERED_REPLACEMENT", 8)
                wait_for(survivor, survivor_record, "DEDICATED_MISMATCH_RECOVERED_SURVIVOR", 8)
            if args.confirmation_progress:
                wait_for(survivor, survivor_record, "DEDICATED_WAITING_FOR_CONFIRMATION_OK")
                wait_for(replacement, replacement_record, "DEDICATED_BOTH_CONFIRMED_OK")
            if args.no_match_start:
                wait_for(survivor, survivor_record, "DEDICATED_START_SUPPRESSED")
                wait_for(replacement, replacement_record, "DEDICATED_START_TIMEOUT_ACTION", 16)
                if args.start_timeout_race == "start-first":
                    guest_link = links["replacement-room"]
                    outage_end = guest_link.start_outage(3.0)
                    Path(str(gate) + ".release-timeout-start").touch()
                    wait_for(survivor, survivor_record, "DEDICATED_OPENING_PLAYER", 3)
                    Path(str(gate) + ".submit-timeout-reset").touch()
                    wait_for(replacement, replacement_record, "DEDICATED_TIMEOUT_RESET_REQUESTED", 3)
                    if time.time_ns() // 1_000_000 >= outage_end or not all(guest_link.outage_drops.values()):
                        raise RuntimeError("The guest did not ask to return while the committed start was held back")
                else:
                    wait_for(replacement, replacement_record, "DEDICATED_START_TIMEOUT_RESET_REPLACEMENT")
                    wait_for(survivor, survivor_record, "DEDICATED_START_TIMEOUT_RESET_SURVIVOR")
                    if args.start_timeout_race == "reset-first":
                        wait_for(survivor, survivor_record, "DEDICATED_LATE_START_IGNORED")
            if args.waiting_outage:
                wait_for(replacement, replacement_record, "DEDICATED_CONFIRMATION_OUTAGE_ARMED")
                end_ms = guest_link.start_outage(36.0 if args.terminal_cancel_outage else 8.5)
                Path(str(gate) + ".confirmation-outage").write_text("confirmation link interrupted", encoding="utf8")
                wait_for(replacement, replacement_record, "DEDICATED_CONFIRMATION_OUTAGE_PAUSE_OK")
                if args.cancel_during_confirmation_outage:
                    wait_for(replacement, replacement_record, "DEDICATED_OUTAGE_CANCEL_QUEUED", 6)
                    if time.time_ns() // 1_000_000 >= end_ms:
                        raise RuntimeError("Cancel Ready was not exercised during the interruption")
                    if not args.terminal_cancel_outage:
                        wait_for(survivor, survivor_record, "DEDICATED_OUTAGE_CANCEL_RECEIVED")
                if args.terminal_cancel_outage:
                    wait_for(replacement, replacement_record, "DEDICATED_OUTAGE_CANCEL_DISCONNECTED", 35)
                    wait_for(survivor, survivor_record, "DEDICATED_OUTAGE_CANCEL_ROOM_RETAINED", 35)
                    time.sleep(max(0, (end_ms - time.time_ns() // 1_000_000) / 1000))
                    Path(str(gate) + ".terminal-cancel-retry").touch()
                    wait_for(replacement, replacement_record, "DEDICATED_OUTAGE_CANCEL_REJOINED")
                else:
                    wait_for(replacement, replacement_record, "DEDICATED_CONFIRMATION_OUTAGE_RECOVERY_OK")
                previous = waiting_outages["before_ready"]["dropped"]
                dropped = {way: count - previous[way] for way, count in guest_link.outage_drops.items()}
                waiting_outages["confirmation"] = {"end_unix_ms": end_ms, "dropped": dropped}
                if not all(dropped.values()):
                    raise RuntimeError("The confirmation outage did not drop packets in both directions")
                samples = Path(replacement_record["log"]).read_text(encoding="utf8", errors="replace")
                events = [json.loads(line[6:]) for line in samples.splitlines() if line.startswith("[NET] ")]
                for phase, record in waiting_outages.items():
                    if phase == "confirmation" and args.terminal_cancel_outage:
                        continue
                    restored = next((event["unix_ms"] for event in events if event["event"] == "waiting_room_link_restored"
                                     and event["unix_ms"] >= record["end_unix_ms"]), None)
                    if restored is None:
                        raise RuntimeError("No waiting-room recovery was observed after restoring traffic")
                    record["recovery_ms"] = restored - record["end_unix_ms"]
            if args.stall_card_art:
                wait_for(survivor, survivor_record, "DEDICATED_ART_FALLBACK_STARTED_SURVIVOR")
                wait_for(replacement, replacement_record, "DEDICATED_ART_FALLBACK_STARTED_REPLACEMENT")
            if args.end_turn_timeout:
                wait_for(replacement, replacement_record, "DEDICATED_END_TURN_TIMEOUT_RETRY_OK", 25)
            if args.discard_timeout:
                wait_for(replacement, replacement_record, "DEDICATED_DISCARD_TIMEOUT_RETRY_OK", 25)
            if args.discard_rejection:
                if args.checkpoint_before_rejection:
                    wait_for(replacement, replacement_record, "DEDICATED_STALE_DISCARD_READY")
                    guest_link = links["replacement-room"]
                    # The loss and jitter can delay a checkpoint beyond a fixed
                    # three-second window. Release channel 1 after it is applied.
                    guest_link.drop_gameplay_replies(15.0)
                    if args.checkpoint_after_action_timeout:
                        guest_link.drop_checkpoint_requests(15.0)
                    Path(str(gate) + ".hold-stale-discard-reply").touch()
                wait_for(survivor, survivor_record, "DEDICATED_STALE_DISCARD_REJECTED")
                if args.checkpoint_before_rejection:
                    if args.checkpoint_after_action_timeout:
                        wait_for(replacement, replacement_record, "DEDICATED_TIMEOUT_SYNC_VISIBLE", 12)
                        guest_link.drop_checkpoint_requests(0.0)
                    wait_for(replacement, replacement_record, '"event":"room_checkpoint_applied"', 10)
                    guest_link.drop_gameplay_replies(0.0)
                wait_for(replacement, replacement_record, "DEDICATED_DISCARD_REJECTION_WAITED_FOR_STATE")
                wait_for(replacement, replacement_record, "DEDICATED_DISCARD_REJECTION_RETRY_OK",
                         40 if args.checkpoint_rejected_chain else 20)
                if args.checkpoint_before_rejection and not guest_link.gameplay_replies_dropped:
                    raise RuntimeError("The delay did not intercept the ordinary rejection")
                if args.checkpoint_before_rejection:
                    wait_for(replacement, replacement_record, "DEDICATED_CAP_DISCARD_READY")
                    guest_link.drop_gameplay_replies(15.0)
                    Path(str(gate) + ".hold-cap-discard-reply").touch()
                    wait_for(replacement, replacement_record, "DEDICATED_CAP_DISCARD_CHECKPOINT_APPLIED", 10)
                    guest_link.drop_gameplay_replies(0.0)
                    wait_for(replacement, replacement_record, "DEDICATED_CAP_DISCARD_LATE_REPLY_OK")
            if args.combat_checkpoint:
                guest_link = links["replacement-room"]
                wait_for(replacement, replacement_record, "DEDICATED_COMBAT_CHECKPOINT_READY")
                guest_link.drop_gameplay_replies(15.0)
                Path(str(gate) + ".hold-combat-replies").touch()
                wait_for(replacement, replacement_record, "DEDICATED_COMBAT_CHECKPOINT_APPLIED", 10)
                guest_link.drop_gameplay_replies(0.0)
                wait_for(replacement, replacement_record, "DEDICATED_COMBAT_CHECKPOINT_LATE_REPLIES_OK")
                if not guest_link.gameplay_replies_dropped:
                    raise RuntimeError("The impairment did not intercept ordinary combat replies")
            if args.stationary_aim:
                wait_for(survivor, survivor_record, "DEDICATED_STATIONARY_AIM_OK")
            if args.hold_gameplay_replies:
                wait_for(replacement, replacement_record, "DEDICATED_GUEST_TURN_READY")
                gameplay_drop_end_ms = links["replacement-room"].drop_gameplay_replies(5.0)
                Path(str(gate) + ".guest-turn").write_text("ordinary replies blocked", encoding="utf8")
            if args.hold_unreliable_probes:
                wait_for(replacement, replacement_record, "DEDICATED_GUEST_TURN_READY")
                guest_link = links["replacement-room"]
                guest_link.drop_unreliable_probe_replies(8.0)
                time.sleep(6.0)
                if guest_link.unreliable_probe_datagrams_filtered < 4:
                    raise RuntimeError("The test did not suppress a sustained sequence of unreliable replies")
                log = Path(replacement_record["log"]).read_text(encoding="utf8", errors="replace")
                if '"event":"room_link_interrupted"' in log:
                    raise RuntimeError("Unreliable probe loss paused a room that still accepted reliable traffic")
                Path(str(gate) + ".guest-turn").touch()
            if args.short_outage:
                wait_for(replacement, replacement_record, "DEDICATED_GUEST_TURN_READY")
                outage_end_ms = links["replacement-room"].start_outage(9.5, 5.0 if args.block_resumed_intents else 0)
                Path(str(gate) + ".guest-turn").write_text("guest connection interrupted", encoding="utf8")
                wait_for(replacement, replacement_record, "DEDICATED_SHORT_OUTAGE_PAUSE_OK")
            if args.return_during_outage:
                wait_for(replacement, replacement_record, "DEDICATED_RESULT_RETURN_OUTAGE_ARMED")
                return_outage_end_ms = links["replacement-room"].start_outage(9.5)
                wait_for(replacement, replacement_record, "DEDICATED_RESULT_RETURN_OUTAGE_OK")
                if not all(links["replacement-room"].outage_drops.values()):
                    raise RuntimeError("The result-return interruption did not drop traffic in both directions")
            wait_for(replacement, replacement_record, "DEDICATED_REMATCH_REPLACEMENT_OK", 45)
            wait_for(survivor, survivor_record, "DEDICATED_REMATCH_SURVIVOR_OK")
            if args.start_timeout_race == "start-first":
                for client, client_record in ((survivor, survivor_record), (replacement, replacement_record)):
                    wait_for(client, client_record, "DEDICATED_COMMITTED_START_PRESERVED")
            if args.start_timeout_race:
                stale_action = "cancel" if args.start_timeout_race == "start-first" else "start"
                marker = f"[ROOM {code}] Ignored stale {stale_action} from preparation"
                room_logs = [Path(record["log"]), *(output / "profile-server").rglob("godot*.log")]
                if not any(marker in path.read_text(encoding="utf8", errors="replace") for path in room_logs):
                    raise RuntimeError("The room server did not record the delayed request being rejected")
            if args.return_during_outage:
                lines = Path(replacement_record["log"]).read_text(encoding="utf8", errors="replace").splitlines()
                events = [json.loads(line[6:]) for line in lines if line.startswith("[NET] ")]
                if not any(event["event"] == "waiting_room_link_restored" and event["unix_ms"] >= return_outage_end_ms for event in events):
                    raise RuntimeError("Returning from results did not recover on the waiting-room connection")
                if any(event["event"] == "waiting_room_link_interrupted" and event["unix_ms"] >= return_outage_end_ms for event in events):
                    raise RuntimeError("The waiting room reported a second interruption after traffic resumed")
            if args.replay_prior_match:
                wait_for(survivor, survivor_record, "DEDICATED_PRIOR_MATCH_READY_SURVIVOR")
                wait_for(replacement, replacement_record, "DEDICATED_PRIOR_MATCH_READY_REPLACEMENT")
                Path(str(gate) + ".prior-match").write_text("deliver prior match messages", encoding="utf8")
                wait_for(survivor, survivor_record, "DEDICATED_PRIOR_MATCH_IGNORED_SURVIVOR")
                wait_for(replacement, replacement_record, "DEDICATED_PRIOR_MATCH_IGNORED_REPLACEMENT")
                for player, kind in ((survivor_record, "intent"), (replacement_record, "authority_state")):
                    samples = Path(player["log"]).read_text(encoding="utf8", errors="replace").splitlines()
                    events = [json.loads(line[6:]) for line in samples if line.startswith("[NET] ")]
                    if not any(event["event"] == "prior_match_message_ignored" and event["kind"] == kind for event in events):
                        raise RuntimeError(player["role"] + " did not receive and reject the old " + kind)
                Path(str(gate) + ".prior-match-checked").write_text("verify a fresh turn", encoding="utf8")
                wait_for(survivor, survivor_record, "DEDICATED_PRIOR_MATCH_FRESH_TURN_SURVIVOR")
                wait_for(replacement, replacement_record, "DEDICATED_PRIOR_MATCH_FRESH_TURN_REPLACEMENT")
                hashes = []
                for player in (survivor_record, replacement_record):
                    samples = Path(player["log"]).read_text(encoding="utf8", errors="replace")
                    fresh_turn = re.search(r"^DEDICATED_PRIOR_MATCH_FRESH_TURN_[A-Z]+ ([a-f0-9]+)$", samples, re.MULTILINE)
                    if not fresh_turn:
                        raise RuntimeError(player["role"] + " did not report the new turn state")
                    hashes.append(fresh_turn.group(1))
                if hashes[0] != hashes[1]:
                    raise RuntimeError("The host and guest disagreed on the turn played in the rematch")
            states = []
            for player in (survivor_record, replacement_record):
                log_text = Path(player["log"]).read_text(encoding="utf8", errors="replace")
                state = re.search(r"^DEDICATED_GUEST_TURN_STATE ([a-f0-9]+)$", log_text, re.MULTILINE)
                if not state:
                    raise RuntimeError(player["role"] + " did not record its resolved turn state")
                states.append(state.group(1))
            if states[0] != states[1]:
                raise RuntimeError("The host and guest ended the turn with different battle states")
            if args.hold_gameplay_replies or args.short_outage:
                log_text = Path(replacement_record["log"]).read_text(encoding="utf8", errors="replace")
                diagnostics = [json.loads(line[6:]) for line in log_text.splitlines() if line.startswith("[NET] ")]
                visible = next(event for event in diagnostics if event["event"] == "test_guest_turn_visible")
                sent = next(event for event in diagnostics if event["event"] == "command_sent" and event["kind"] == "end_turn")
                guest_turn_latency_ms = visible["unix_ms"] - sent["unix_ms"]
            if args.hold_gameplay_replies:
                if not links["replacement-room"].gameplay_replies_dropped:
                    raise RuntimeError("The impairment did not intercept a gameplay reply")
                if visible["unix_ms"] >= gameplay_drop_end_ms or not any(
                    event["event"] == "room_checkpoint_applied" and event["revision"] == visible["revision"]
                    for event in diagnostics
                ):
                    raise RuntimeError("The guest could not confirm the turn while ordinary replies were blocked")
                if not args.weak_network and any(event["event"] == "room_link_interrupted" for event in diagnostics):
                    raise RuntimeError("The client reported an outage even though the room link was reachable")
            if args.short_outage:
                outage_recovery_ms = visible["unix_ms"] - outage_end_ms
                if not all(links["replacement-room"].outage_drops.values()) or outage_recovery_ms < 0:
                    raise RuntimeError("Turn completed without exercising a two-way outage")
                if not any(event["event"] == "test_short_outage_pause" and event["unix_ms"] < outage_end_ms
                           for event in diagnostics):
                    raise RuntimeError("The paused UI was only sampled after the outage ended")
                wait_for(replacement, replacement_record, "DEDICATED_SHORT_OUTAGE_RECOVERY_OK")
                if args.block_resumed_intents:
                    host_log = Path(survivor_record["log"]).read_text(encoding="utf8", errors="replace")
                    host_events = [json.loads(line[6:]) for line in host_log.splitlines() if line.startswith("[NET] ")]
                    if outage_recovery_ms >= 5000 or not any(
                        event["event"] == "command_arrived" and event.get("recovery_channel") and event["command_id"] == sent["command_id"]
                        for event in host_events
                    ):
                        raise RuntimeError("The guest turn did not recover while the ordinary uplink was blocked")
            in_progress, in_progress_record = launch_client("in_progress")
            wait_for(in_progress, in_progress_record, "DEDICATED_IN_PROGRESS_OK")
            if args.long_outage:
                wait_for(survivor, survivor_record, "DEDICATED_TERMINAL_OUTAGE_ARMED")
                if args.outage_after_results:
                    wait_for(replacement, replacement_record, "DEDICATED_COMPLETED_RESULT_READY")
                links["survivor-room"].start_outage(75.0)
                long_outage_started_ms = time.time_ns() // 1_000_000
                wait_for(survivor, survivor_record, "DEDICATED_DROPPED_BACK_TO_MULTIPLAYER_OK", 52)
                wait_for(replacement, replacement_record, "DEDICATED_LONG_OUTAGE_ROOM_RETAINED_OK", 15)
                rejoin, rejoin_record = launch_client("rejoin")
                wait_for(rejoin, rejoin_record, "DEDICATED_LONG_OUTAGE_NEW_PLAYER_READY_OK")
                wait_for(replacement, replacement_record, "DEDICATED_LONG_OUTAGE_ROOM_READY_OK")
                for player in (survivor_record, replacement_record):
                    samples = Path(player["log"]).read_text(encoding="utf8", errors="replace")
                    events = [json.loads(line[6:]) for line in samples.splitlines() if line.startswith("[NET] ")]
                    result_event = next((event for event in events if event["event"] == "test_long_outage_result"), None)
                    if result_event is None or result_event["unix_ms"] <= long_outage_started_ms:
                        raise RuntimeError(player["role"] + " did not observe a result after the outage")
                    long_outage_result_ms[player["role"]] = result_event["unix_ms"] - long_outage_started_ms
                if not all(links["survivor-room"].outage_drops.values()):
                    raise RuntimeError("The sustained outage did not drop packets in both directions")
            else:
                Path(str(gate) + ".rematch").write_text("in-progress match verified", encoding="utf8")
                wait_for(survivor, survivor_record, "DEDICATED_HOST_ABANDONED_OK")
                if args.join_during_results:
                    wait_for(replacement, replacement_record, "DEDICATED_RESULT_HELD_FOR_JOIN")
                    rejoin, rejoin_record = launch_client("rejoin")
                    wait_for(rejoin, rejoin_record, "DEDICATED_GUEST_WAITING_FOR_RESULT_OK")
                    wait_for(replacement, replacement_record, "DEDICATED_RESULT_HOST_SAW_NEW_READY")
                    wait_for(rejoin, rejoin_record, "DEDICATED_RESULT_GUEST_READY_OK")
                elif args.leave_from_results:
                    wait_for(replacement, replacement_record, '"event":"room_leave_confirmed"')
                    wait_for(replacement, replacement_record, "DEDICATED_RESULT_DEPARTURE_OK")
                else:
                    wait_for(replacement, replacement_record, "DEDICATED_LIVE_HOST_LEFT_OK")
        for process, record in zip(processes, records):
            if record["role"] != "server":
                process.wait(timeout=5)
                if process.returncode != 0:
                    raise RuntimeError(record["role"] + " returned " + str(process.returncode))
        passed = True
    except (RuntimeError, subprocess.TimeoutExpired) as exc:
        error = str(exc)
    finally:
        if args.reject_room_handoff == "slot_in_use":
            (output / "owner-may-leave.local-occupied-slot").unlink(missing_ok=True)
        for link in links.values():
            link.close()
            if link.error:
                passed = False
                error += " Local UDP link: " + link.error
        if args.weak_network and links and not any(link.stats[way]["dropped"] for link in links.values() for way in ("up", "down")):
            passed = False
            error += " No packets were dropped under the configured conditions."
        # Only terminate children of processes created by this runner.
        for process in processes:
            if process.poll() is None:
                if os.name == "nt":
                    subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
                else:
                    os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        for stream in handles:
            stream.close()
        for process, record in zip(processes, records):
            text = Path(record["log"]).read_text(encoding="utf8", errors="replace")
            record.update(exit=process.returncode, errors="ERROR:" in text or "SCRIPT ERROR" in text)
            if record["errors"]:
                passed = False
        result = {"passed": passed, "error": error, "address": args.address or "local",
                  "processes": records}
        if links:
            result["network_conditions"] = {"seed": args.seed, "delay_ms": 80 if args.weak_network else 0,
                                            "jitter_ms": 35 if args.weak_network else 0,
                                            "loss_percent": 7 if args.weak_network else 0,
                                            "links": {name: link.stats for name, link in links.items()}}
        if args.combat_checkpoint and "replacement-room" in links:
            link = links["replacement-room"]
            result["combat_reply_impairment"] = {
                "gameplay_datagrams_filtered": link.gameplay_replies_dropped,
                "checkpoint_datagrams_preserved": link.checkpoint_datagrams_preserved,
            }
        if gameplay_drop_end_ms:
            result["gameplay_reply_impairment"] = {"drop_end_unix_ms": gameplay_drop_end_ms,
                                                  "dropped": links["replacement-room"].gameplay_replies_dropped,
                                                  "guest_turn_latency_ms": guest_turn_latency_ms}
        if outage_end_ms:
            result["short_outage"] = {"end_unix_ms": outage_end_ms, "dropped": links["replacement-room"].outage_drops,
                                      "guest_turn_latency_ms": guest_turn_latency_ms, "recovery_ms": outage_recovery_ms}
            if args.block_resumed_intents:
                result["short_outage"]["resumed_intents_dropped"] = links["replacement-room"].resumed_intents_dropped
        if long_outage_started_ms:
            result["long_outage"] = {"dropped": links["survivor-room"].outage_drops,
                                     "result_latency_ms": long_outage_result_ms}
        if waiting_outages:
            result["waiting_outages"] = waiting_outages
        (output / "verification.json").write_text(json.dumps(result, indent=2), encoding="utf8")
        print(json.dumps({"passed": passed, "error": error, "output": str(output)}, indent=2))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
