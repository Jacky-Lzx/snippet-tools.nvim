"""Fast checks for the measurement transport and statistics (no Neovim needed)."""
import errno
import io
import unittest
from unittest.mock import Mock, patch

from compare import InputProcess, summary
from rpc import Client, answer_terminal, pack, unpack


class ProtocolTests(unittest.TestCase):
    def test_messagepack_roundtrip(self):
        value = [None, True, False, -12, 2**40, 1.25, "中文\ntext", {"keys": [1, 2]}]
        self.assertEqual(value, unpack(io.BytesIO(pack(value)).read))

    def test_terminal_queries_survive_every_chunk_boundary(self):
        query = b"\x1b]11;?\x1b\\"
        for split in range(len(query) + 1):
            with self.subTest(split=split), patch("rpc.os.write") as write:
                state = {}
                answer_terminal(10, query[:split], state)
                answer_terminal(10, query[split:], state)
                answer_terminal(10, b"unrelated text", state)
                write.assert_called_once_with(10, b"\x1b]11;rgb:0000/0000/0000\x1b\\")

    def test_status_dsr_handshake(self):
        with patch("rpc.os.write") as write:
            answer_terminal(10, b"\x1b[5n", {})
            write.assert_called_once_with(10, b"\x1b[0n")

    def test_nearest_rank_tail_and_even_median(self):
        stats = summary(list(range(1, 21)))
        self.assertEqual(10.5, stats["median"])
        self.assertEqual(19, stats["p95"])
        self.assertEqual(20, stats["p99"])
        self.assertIsNone(summary([]))

    def test_editor_exits_before_retrying_temporary_cache_cleanup(self):
        proc = InputProcess.__new__(InputProcess)
        proc.closed = False
        proc.client, proc.process, proc.temporary = Mock(), Mock(), Mock()
        proc.client.lua.side_effect = EOFError("editor exited")
        proc.process.poll.return_value = None
        proc.temporary.cleanup.side_effect = [OSError(errno.ENOTEMPTY, "cache worker"), None]
        with patch("compare.time.sleep"):
            proc.close()
        proc.client.lua.assert_called_once_with("vim.cmd('qa!')")
        proc.process.wait.assert_called_once_with(timeout=2)
        proc.process.terminate.assert_not_called()
        self.assertEqual(2, proc.temporary.cleanup.call_count)

    def test_ui_completion_requires_matching_validation(self):
        client = Client.__new__(Client)
        client.received_ns = 12345
        client.awaiting_id, client.results, client.frame_results = 7, {}, {}
        client.redraw([["flush", []]])
        self.assertEqual({}, client.frame_results)
        client.results[7] = {"valid": True}
        client.redraw([["flush", []]])
        self.assertEqual({7: 12345}, client.frame_results)


if __name__ == "__main__":
    unittest.main()
