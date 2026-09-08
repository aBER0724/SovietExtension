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

    def test_preflight_existing_backup_is_authoritative_without_mutation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            live, backup, config_path = root / "live", root / "backup", root / "theme.json"
            live.write_bytes(b"invalid and deliberately different live payload")
            backup.write_bytes(synthetic_fixture_with_keys("bg0"))
            os.chmod(live, 0o604)
            os.chmod(backup, 0o640)
            config = custom_config()
            config["advanced"]["light"]["bg0"] = "#abcdef"
            config_path.write_text(json.dumps(config), encoding="utf-8")
            before = {p: (p.read_bytes(), stat.S_IMODE(p.stat().st_mode)) for p in (live, backup)}

            result = self.run_preflight(live, backup, config_path)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(f"source={backup}", result.stdout)
            for path, snapshot in before.items():
                self.assertEqual((path.read_bytes(), stat.S_IMODE(path.stat().st_mode)), snapshot)

    def test_preflight_invalid_existing_backup_does_not_fall_back_to_valid_live(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            live, backup, config_path = root / "live", root / "backup", root / "theme.json"
            live.write_bytes(synthetic_fixture_with_keys("bg0"))
            backup.write_bytes(b"invalid authoritative backup")
            os.chmod(live, 0o604)
            os.chmod(backup, 0o640)
            config_path.write_text(json.dumps(custom_config()), encoding="utf-8")
            before = {p: (p.read_bytes(), stat.S_IMODE(p.stat().st_mode)) for p in (live, backup)}

            result = self.run_preflight(live, backup, config_path)

            self.assertNotEqual(result.returncode, 0)
            for path, snapshot in before.items():
                self.assertEqual((path.read_bytes(), stat.S_IMODE(path.stat().st_mode)), snapshot)

    def test_apply_shell_preflight_and_patch_share_resolved_arguments_before_quit(self):
        text = (RELY_DIR / "apply_theme.sh").read_text(encoding="utf-8")
        expected = 'RESOLVED_COLOR_ARGS=(--patch-resolved-key bg1 --patch-resolved-key bg2)'
        self.assertIn(expected, text)
        invocations = [line for line in text.splitlines()
                       if line.startswith('/usr/bin/python3 "${PATCHER}"')]
        self.assertEqual(len(invocations), 2)
        common = '"${DYLIB}" --backup "${BACKUP}" --config "${CONFIG_PATH}" "${RESOLVED_COLOR_ARGS[@]}"'
        self.assertIn(common, invocations[0])
        self.assertIn(common, invocations[1])
        self.assertTrue(invocations[0].endswith(" --preflight"))
        self.assertFalse(invocations[1].endswith(" --preflight"))
        preflight = text.index(invocations[0])
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

    def test_installer_helper_preserves_existing_theme_and_installs_helpers(self):
        helper = RELY_DIR / "install_theme_helpers.sh"
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "home"
            support = home / "Library/Application Support/SovietExtension"
            themes = support / "themes"
            themes.mkdir(parents=True)
            sentinel = themes / "12345678-1234-1234-1234-123456789abc.json"
            sentinel_bytes = b' {"user":"bytes\\nremain exact"}\\n'
            sentinel.write_bytes(sentinel_bytes)
            os.chmod(sentinel, 0o640)
            python_source = root / "new-helper.py"
            shell_source = root / "new-helper.sh"
            python_source.write_bytes(b"#!/usr/bin/python3\nprint('new')\n")
            shell_source.write_bytes(b"#!/bin/bash\necho new\n")
            (support / "apply_theme.py").write_bytes(b"old python")
            (support / "apply_theme.sh").write_bytes(b"old shell")

            result = subprocess.run(
                ["/bin/bash", str(helper), str(support), str(python_source), str(shell_source)],
                text=True, capture_output=True)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(sentinel.read_bytes(), sentinel_bytes)
            self.assertEqual(stat.S_IMODE(sentinel.stat().st_mode), 0o640)
            self.assertEqual((support / "apply_theme.py").read_bytes(), python_source.read_bytes())
            self.assertEqual((support / "apply_theme.sh").read_bytes(), shell_source.read_bytes())
            self.assertEqual(stat.S_IMODE((support / "apply_theme.py").stat().st_mode), 0o755)
            self.assertEqual(stat.S_IMODE((support / "apply_theme.sh").stat().st_mode), 0o755)

    def test_installer_helper_creates_missing_directories_with_mode_0700(self):
        helper = RELY_DIR / "install_theme_helpers.sh"
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            support = root / "missing/support"
            python_source = root / "helper.py"
            shell_source = root / "helper.sh"
            python_source.write_text("python", encoding="utf-8")
            shell_source.write_text("shell", encoding="utf-8")

            subprocess.run(["/bin/bash", str(helper), str(support), str(python_source), str(shell_source)],
                           check=True)

            self.assertEqual(stat.S_IMODE(support.stat().st_mode), 0o700)
            self.assertEqual(stat.S_IMODE((support / "themes").stat().st_mode), 0o700)

    def test_build_phase_gate_executes_mock_only_for_exact_one(self):
        gate = RELY_DIR / "build_phase_install_gate.sh"
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            calls = root / "calls"
            mock_install = root / "mock-install.sh"
            mock_install.write_text(f"#!/bin/bash\necho call >> {calls!s}\n", encoding="utf-8")
            os.chmod(mock_install, 0o755)

            values = (None, "", "0", "2", "true", "01")
            for value in values:
                env = os.environ.copy()
                if value is None:
                    env.pop("SOVIET_INSTALL_AFTER_BUILD", None)
                else:
                    env["SOVIET_INSTALL_AFTER_BUILD"] = value
                result = subprocess.run(["/bin/bash", str(gate), str(mock_install)], env=env,
                                        text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, (value, result.stderr))
            self.assertFalse(calls.exists())

            env = os.environ.copy()
            env["SOVIET_INSTALL_AFTER_BUILD"] = "1"
            result = subprocess.run(["/bin/bash", str(gate), str(mock_install)], env=env,
                                    text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(calls.read_text().splitlines(), ["call"])

    def test_production_scripts_call_shared_installer_and_build_gate(self):
        install = (RELY_DIR / "install.sh").read_text(encoding="utf-8")
        project = (RELY_DIR.parent / "SovietExtension.xcodeproj" / "project.pbxproj").read_text()
        self.assertIn('install_theme_helpers.sh', install)
        self.assertIn('build_phase_install_gate.sh', project)



if __name__ == "__main__":
    unittest.main()
