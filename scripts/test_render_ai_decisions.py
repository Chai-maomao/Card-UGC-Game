"""Report integrity guards and UGC script-text containment."""
import copy
import json
import tempfile
import unittest
from pathlib import Path

from render_ai_decisions import render


class ReportTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.source = Path(self.directory.name) / "__TRACE__.json"
        self.output = Path(self.directory.name) / "report.html"
        self.data = {
            "version": 1, "kind": "cardex_ai_decisions", "final_hash": "verified",
            "summary": {"decisions": 1, "activations_without_observed_payload": 0},
            "rows": [{"hash": "verified", "activation_without_observed_payload": False,
                      "source": {"name": '</script><img src=x onerror="alert(1)">&__JSON_LINK____TRACE__'}}],
        }

    def write(self, data=None):
        self.source.write_text(json.dumps(self.data if data is None else data), encoding="utf-8")

    def test_ugc_is_data_and_source_preserved(self):
        self.write()
        original = self.source.read_bytes()
        render(self.source, self.output)
        page = self.output.read_text(encoding="utf-8")
        embedded = page.split('<script type="application/json" id="trace">', 1)[1].split('</script>', 1)[0]
        self.assertEqual(json.loads(embedded), self.data)
        self.assertNotIn("<img", embedded)
        self.assertEqual(page.count("<script"), 2)
        self.assertIn('href="__TRACE__.json"', page)
        self.assertEqual(self.source.read_bytes(), original)

    def test_reject_inconsistent_or_unsupported_report(self):
        for change in ["version", "decisions", "flags", "hash"]:
            with self.subTest(change=change):
                data = copy.deepcopy(self.data)
                if change == "version": data["version"] = 999
                elif change == "decisions": data["summary"]["decisions"] = 2
                elif change == "flags": data["summary"]["activations_without_observed_payload"] = 1
                else: data["rows"][0]["hash"] = "tampered"
                self.write(data)
                with self.assertRaises(ValueError): render(self.source, self.output)
                self.assertFalse(self.output.exists())

    def test_reject_output_over_source(self):
        self.write()
        original = self.source.read_bytes()
        with self.assertRaises(ValueError): render(self.source, self.source)
        self.assertEqual(self.source.read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
