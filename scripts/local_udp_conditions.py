"""Apply repeatable test network conditions to a single local ENet client."""
import heapq
import errno
import random
import select
import socket
import struct
import threading
import time


def _enet_commands(packet):
    """Return channel, kind and byte range for each command in a test datagram."""
    if len(packet) < 2:
        return []
    flags = int.from_bytes(packet[:2], "big")
    if flags & 0x4000:  # ENet's own compression is disabled in this test.
        return []
    offset = 4 if flags & 0x8000 else 2
    command_lengths = (0, 8, 48, 44, 8, 4, 6, 8, 24, 8, 12, 16, 24)
    records = []
    while offset + 4 <= len(packet):
        command = packet[offset] & 0x0F
        if not 0 < command < len(command_lengths):
            return []
        end = offset + command_lengths[command]
        if end > len(packet):
            return []
        if command in (6, 7, 8, 9, 12):
            length_offset = offset + (4 if command == 6 else 6)
            end += struct.unpack_from("!H", packet, length_offset)[0]
            if end > len(packet):
                return []
        records.append((packet[offset + 1] - 1, command, offset, end))
        offset = end
    return records if offset == len(packet) else []


def carries_gameplay_data(packet, channel=1, commands=(6, 8)):
    return any(record_channel == channel and kind in commands
               for record_channel, kind, _, _ in _enet_commands(packet))


def _without_commands(packet, removed_channel, removed_kinds):
    records = _enet_commands(packet)
    retained = [packet[start:end] for channel, kind, start, end in records
                if channel != removed_channel or kind not in removed_kinds]
    if len(retained) == len(records):
        return packet
    if not retained:
        return b""
    # ENet can put reliable replies, checkpoints and ACKs in one datagram.
    # Keep the header and unrelated commands eligible for normal link impairment.
    return packet[:records[0][2]] + b"".join(retained)


def _without_gameplay_reply(packet):
    return _without_commands(packet, 1, (6, 8))


class LocalUdpLink:
    def __init__(self, server_port, seed, delay_ms, jitter_ms, loss_percent):
        self.listener = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.listener.bind(("127.0.0.1", 0))
        self.port = self.listener.getsockname()[1]
        self._server_address = ("127.0.0.1", server_port)
        self.delay_ms = delay_ms
        self.jitter_ms = jitter_ms
        self.loss_percent = loss_percent
        self.stats = {direction: {"forwarded": 0, "dropped": 0, "unreachable": 0} for direction in ("up", "down")}
        self.gameplay_replies_dropped = 0
        self.unreliable_probe_datagrams_filtered = 0
        self.checkpoint_datagrams_preserved = 0
        self.outage_drops = {direction: 0 for direction in ("up", "down")}
        self.resumed_intents_dropped = 0
        self._gameplay_drop_until = 0.0
        self._unreliable_probe_drop_until = 0.0
        self._checkpoint_request_drop_until = 0.0
        self._outage_until = 0.0
        self._block_intents_until = 0.0
        self.error = None
        self._random = random.Random(seed)
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

    def drop_gameplay_replies(self, seconds):
        self._gameplay_drop_until = time.monotonic() + seconds
        return time.time_ns() // 1_000_000 + round(seconds * 1000)

    def drop_checkpoint_requests(self, seconds):
        self._checkpoint_request_drop_until = time.monotonic() + seconds

    def drop_unreliable_probe_replies(self, seconds):
        self._unreliable_probe_drop_until = time.monotonic() + seconds

    def start_outage(self, seconds, block_intents_seconds=0):
        self._outage_until = time.monotonic() + seconds
        self._block_intents_until = self._outage_until + block_intents_seconds
        return time.time_ns() // 1_000_000 + round(seconds * 1000)

    def close(self):
        self._stop.set()
        self._thread.join()
        self.listener.close()

    def _run(self):
        queue, sequence = [], 0
        upstream_by_client = {}
        client_by_upstream = {}
        try:
            while not self._stop.is_set():
                now = time.monotonic()
                while queue and queue[0][0] <= now:
                    _, _, direction, data, client, upstream = heapq.heappop(queue)
                    if now < self._outage_until:
                        self.outage_drops[direction] += 1
                        continue
                    try:
                        if direction == "up":
                            upstream.send(data)
                        else:
                            self.listener.sendto(data, client)
                    except OSError as error:
                        if not self._destination_closed(error):
                            raise
                        self.stats[direction]["unreachable"] += 1
                        continue
                    self.stats[direction]["forwarded"] += 1
                delay = min(0.05, max(0, queue[0][0] - now)) if queue else 0.05
                readable, _, _ = select.select([self.listener, *client_by_upstream], [], [], delay)
                for source in readable:
                    direction = "up" if source is self.listener else "down"
                    try:
                        if source is self.listener:
                            data, client = source.recvfrom(65535)
                            upstream = upstream_by_client.get(client)
                            if upstream is None:
                                # ENet can select a fresh local port when the same client retries.
                                upstream = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                                upstream_by_client[client] = upstream
                                client_by_upstream[upstream] = client
                                upstream.connect(self._server_address)
                        else:
                            upstream = source
                            client = client_by_upstream[upstream]
                            data = source.recv(65535)
                    except OSError as error:
                        # The OS reports an ICMP response after a game process
                        # closes its port. This is a lost datagram, not relay failure.
                        if not self._destination_closed(error):
                            raise
                        self.stats[direction]["unreachable"] += 1
                        continue
                    received_at = time.monotonic()
                    if received_at < self._outage_until:
                        self.outage_drops[direction] += 1
                        continue
                    if direction == "up" and received_at < self._block_intents_until and carries_gameplay_data(data):
                        self.resumed_intents_dropped += 1
                        continue
                    if (direction == "up" and received_at < self._checkpoint_request_drop_until
                            and carries_gameplay_data(data, channel=4, commands=(6, 7, 8, 9, 12))):
                        continue
                    if direction == "down" and received_at < self._gameplay_drop_until:
                        filtered = _without_gameplay_reply(data)
                        if filtered != data:
                            self.gameplay_replies_dropped += 1
                            if carries_gameplay_data(filtered, channel=4):
                                self.checkpoint_datagrams_preserved += 1
                            data = filtered
                            if not data:
                                continue
                    if direction == "down" and received_at < self._unreliable_probe_drop_until:
                        filtered = _without_commands(data, 0, (7, 9, 12))
                        if filtered != data:
                            self.unreliable_probe_datagrams_filtered += 1
                            data = filtered
                            if not data:
                                continue
                    if self._random.random() * 100 < self.loss_percent:
                        self.stats[direction]["dropped"] += 1
                        continue
                    latency_ms = self.delay_ms + self._random.uniform(-self.jitter_ms, self.jitter_ms)
                    sequence += 1
                    deliver_at = received_at + max(0, latency_ms) / 1000
                    heapq.heappush(queue, (deliver_at, sequence, direction, data, client, upstream))
        except OSError as error:
            self.error = str(error)
        finally:
            for upstream in client_by_upstream:
                upstream.close()

    @staticmethod
    def _destination_closed(error):
        return error.errno in {errno.ECONNREFUSED, errno.ECONNRESET} or getattr(error, "winerror", None) == 10054
