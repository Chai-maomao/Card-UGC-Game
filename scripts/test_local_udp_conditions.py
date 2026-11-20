import struct
import unittest

from local_udp_conditions import _without_gameplay_reply, carries_gameplay_data


def reliable(channel, sequence, payload):
    return struct.pack("!BBHH", 0x86, channel + 1, sequence, len(payload)) + payload


class GameplayReplyFilterTest(unittest.TestCase):
    def test_preserves_checkpoint_and_ack_in_same_datagram(self):
        header = b"\x80\x01\x12\x34"
        reply = reliable(1, 20, b"ordinary reply")
        checkpoint = reliable(4, 40, b"checkpoint")
        ack = struct.pack("!BBHHH", 1, 2, 5, 3, 400)
        fragment = struct.pack("!BBHHHIIII", 0x88, 2, 21, 21, 4, 2, 0, 8, 0) + b"body"

        filtered = _without_gameplay_reply(header + reply + checkpoint + ack + fragment)

        self.assertEqual(filtered, header + checkpoint + ack)
        self.assertTrue(carries_gameplay_data(filtered, channel=4))
        self.assertFalse(carries_gameplay_data(filtered))
        self.assertEqual(_without_gameplay_reply(header + reply + fragment), b"")

    def test_leaves_unrelated_and_unparseable_data_unchanged(self):
        checkpoint = reliable(4, 40, b"checkpoint")
        reply = reliable(1, 20, b"ordinary reply")
        packets = [b"\x00\x01" + checkpoint, b"\x00\x01" + reply[:-1], b"\x40\x01" + reply]
        for packet in packets:
            with self.subTest(packet=packet):
                self.assertEqual(_without_gameplay_reply(packet), packet)


if __name__ == "__main__":
    unittest.main()
