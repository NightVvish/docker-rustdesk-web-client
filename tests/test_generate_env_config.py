import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = (
    Path(__file__).resolve().parents[1]
    / "v1"
    / "server"
    / "generate_env_config.py"
)
SPEC = importlib.util.spec_from_file_location("generate_env_config", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
generate_env_config = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(generate_env_config)


class GenerateEnvConfigTests(unittest.TestCase):
    def test_defaults_are_applied_to_missing_or_empty_values(self) -> None:
        content = generate_env_config.render_config({"API_SERVER": ""})

        self.assertIn(
            'window.localStorage.setItem("api-server", "api.rustdesk.com");',
            content,
        )
        self.assertIn(
            'window.localStorage.setItem("custom-rendezvous-server", "");',
            content,
        )

    def test_values_are_json_encoded(self) -> None:
        value = 'rd.example.com";\nwindow.evil = true; //\\'
        content = generate_env_config.render_config(
            {
                "CUSTOM_RENDEZVOUS_SERVER": value,
                "RELAY_SERVER": "relay.example.com:21117",
                "API_SERVER": "api.example.com",
                "KEY": "clé publique",
            }
        )

        encoded = json.dumps(value, ensure_ascii=False)
        self.assertIn(
            f'window.localStorage.setItem("custom-rendezvous-server", {encoded});',
            content,
        )
        self.assertNotIn("\nwindow.evil = true", content)

    def test_write_is_atomic_and_utf8(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "env-config.js"
            expected = generate_env_config.render_config({"KEY": "clé"})

            generate_env_config.write_config(output, expected)

            self.assertEqual(output.read_text(encoding="utf-8"), expected)


if __name__ == "__main__":
    unittest.main()
