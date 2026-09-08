import json
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

from test_apply_catppuccin import MODULE_PATH, apply_catppuccin, custom_config, synthetic_fixture_with_keys


RELY_DIR = MODULE_PATH.parent


class PreflightIntegrationTests(unittest.TestCase):
    def run_preflight(self, live, backup, config):
        return subprocess.run(
            ["python3", str(MODULE_PATH), str(live), "--backup", str(backup),
             "--config", str(config), "--preflight"],
            text=True, capture_output=True)

    def test_valid_preflight_succeeds_without_writes_or_backup_creation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            live, backup, config_path = root / "live", root / "backup", root / "theme.json"
            original = synthetic_fixture_with_keys("bg0")
            live.write_bytes(original)
            config = custom_config()
            config["advanced"]["light"]["bg0"] = "#abcdef"
            config_path.write_text(json.dumps(config), encoding="utf-8")
            before = {p: (p.read_bytes(), p.stat().st_mode) for p in (live, config_path)}

            result = self.run_preflight(live, backup, config_path)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(backup.exists())
            for path, snapshot in before.items():
                self.assertEqual((path.read_bytes(), path.stat().st_mode), snapshot)

    def test_unknown_or_case_mismatched_advanced_fails_without_mutation(self):
        for key in ("not_a_verified_named_key", "BG0"):
            with self.subTest(key=key), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                live, backup, config_path = root / "live", root / "backup", root / "theme.json"
                original = synthetic_fixture_with_keys("bg0")
                live.write_bytes(original)
                config = custom_config()
                config["advanced"]["dark"][key] = "#abcdef"
                encoded = json.dumps(config).encode()
                config_path.write_bytes(encoded)

                result = self.run_preflight(live, backup, config_path)

                self.assertNotEqual(result.returncode, 0)
                self.assertIn(key, result.stderr)
                self.assertEqual(live.read_bytes(), original)
                self.assertEqual(config_path.read_bytes(), encoded)
                self.assertFalse(backup.exists())
                self.assertEqual(list(root.glob(".*")), [])

    def test_apply_shell_preflight_precedes_every_quit_or_kill(self):
        text = (RELY_DIR / "apply_theme.sh").read_text(encoding="utf-8")
        preflight = text.index("--preflight")
        self.assertLess(preflight, text.index("osascript"))
        self.assertLess(preflight, text.index("pkill"))

    def test_panel_uses_temporary_config_for_synchronous_preflight_before_confirmation(self):
        text = (RELY_DIR.parent / "SovietExtension" / "GlobalThemeSettingsWindowController.m").read_text()
        preflight = text.index('ym_preflightConfiguration:config')
        confirmation = text.index('@"应用全局主题？"')
        active_write = text.index('writeToFile:path', confirmation)
        self.assertLess(preflight, confirmation)
        self.assertLess(confirmation, active_write)
        self.assertIn('removeItemAtPath:temporaryConfigPath', text)

    def test_installer_preserves_theme_json_and_mode_by_construction(self):
        text = (RELY_DIR / "install.sh").read_text(encoding="utf-8")
        self.assertIn('THEME_SUPPORT_DIR}/themes', text)
        for dangerous in ('cp *"${THEME_SUPPORT_DIR}/themes', 'chmod *"${THEME_SUPPORT_DIR}/themes',
                          'rm *"${THEME_SUPPORT_DIR}/themes'):
            self.assertNotIn(dangerous, text)

    def test_build_phase_is_default_noop_and_explicitly_opted_in(self):
        text = (RELY_DIR.parent / "SovietExtension.xcodeproj" / "project.pbxproj").read_text()
        guard = 'SOVIET_INSTALL_AFTER_BUILD'
        self.assertIn(guard, text)
        self.assertLess(text.index(guard), text.index('APP_PATH=\\"/Applications/'))


if __name__ == "__main__":
    unittest.main()
