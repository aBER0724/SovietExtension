import importlib.util
import json
import tempfile
import unittest
import uuid
from pathlib import Path
from unittest import mock


MODULE_PATH = Path(__file__).resolve().parents[1] / "apply_catppuccin.py"
SPEC = importlib.util.spec_from_file_location("apply_catppuccin", MODULE_PATH)
assert SPEC and SPEC.loader
apply_catppuccin = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(apply_catppuccin)


TEN_COLORS = {
    "base": "#010203",
    "sidebar": "#111213",
    "ribbon": "#212223",
    "outgoing_bubble": "#313233",
    "incoming_bubble": "#414243",
    "text": "#515253",
    "subtext": "#616263",
    "accent": "#717273",
    "link": "#818283",
    "danger": "#919293",
}


def custom_config():
    return {
        "schema_version": 2,
        "preset": None,
        "custom_theme_id": str(uuid.uuid4()),
        "light": dict(TEN_COLORS),
        "dark": {key: "#" + format(int(value[1:], 16) + 0x030303, "06x")
                 for key, value in TEN_COLORS.items()},
        "advanced": {"light": {}, "dark": {}},
    }


class DirectColorConfigTests(unittest.TestCase):
    def test_custom_schema_accepts_and_maps_all_ten_colors_directly(self):
        theme = apply_catppuccin.build_theme("", custom_config())
        self.assertEqual(theme["name"], "custom")
        self.assertEqual(theme["roles"]["light"],
                         {key: value[1:].lower() for key, value in TEN_COLORS.items()})
        expected = {
            "bg1": "base", "bg_sidebar_alt": "sidebar", "bg0": "ribbon",
            "chat_right_bubble_color": "outgoing_bubble",
            "chat_left_bubble_color": "incoming_bubble", "fg0": "text",
            "glyph_selected_subtitle": "subtext", "fg_brand": "accent",
            "hyperlink_color": "link", "recording_cancel_end_color": "danger",
        }
        for named_key, role in expected.items():
            with self.subTest(named_key=named_key):
                self.assertEqual(
                    apply_catppuccin.color_for_key(theme, named_key, (9, 8, 7), "light"),
                    TEN_COLORS[role][1:].lower())

    def test_custom_missing_and_extra_color_keys_are_field_specific(self):
        missing = custom_config()
        del missing["light"]["danger"]
        with self.assertRaisesRegex(ValueError, r"light.*missing.*danger"):
            apply_catppuccin.build_theme("", missing)

        extra = custom_config()
        extra["dark"]["generated_tone"] = "#abcdef"
        with self.assertRaisesRegex(ValueError, r"dark.*unknown.*generated_tone"):
            apply_catppuccin.build_theme("", extra)

    def test_preset_null_never_inherits_catppuccin(self):
        config = custom_config()
        theme = apply_catppuccin.build_theme("", config)
        self.assertEqual(
            apply_catppuccin.color_for_key(theme, "unclassified_named_color", (255, 0, 255), "light"),
            TEN_COLORS["text"][1:])
        self.assertNotIn(apply_catppuccin.LATTE["pink"], theme["roles"]["light"].values())

    def test_malformed_uuid_and_color_are_rejected(self):
        bad_uuid = custom_config()
        bad_uuid["custom_theme_id"] = "not-a-uuid"
        with self.assertRaisesRegex(ValueError, "custom_theme_id.*UUID"):
            apply_catppuccin.build_theme("", bad_uuid)

        bad_color = custom_config()
        bad_color["dark"]["accent"] = "123"
        with self.assertRaisesRegex(ValueError, r"dark\.accent.*#RRGGBB"):
            apply_catppuccin.build_theme("", bad_color)

    def test_custom_root_fields_are_strict(self):
        config = custom_config()
        config["palette"] = {}
        with self.assertRaisesRegex(ValueError, "unknown config keys: palette"):
            apply_catppuccin.build_theme("", config)

    def test_unknown_advanced_key_fails_before_live_mutation(self):
        config = custom_config()
        config["advanced"]["light"]["not_a_verified_named_key"] = "#abcdef"
        with tempfile.TemporaryDirectory() as directory:
            live = Path(directory) / "live.dylib"
            original = b"live bytes must survive"
            live.write_bytes(original)
            with self.assertRaisesRegex(ValueError, "unknown advanced.*not_a_verified_named_key"):
                theme = apply_catppuccin.build_theme("", config)
                apply_catppuccin.patch(live, None, theme)
            self.assertEqual(live.read_bytes(), original)

    def test_forced_patch_generation_failure_leaves_live_bytes_unchanged(self):
        with tempfile.TemporaryDirectory() as directory:
            live = Path(directory) / "live.dylib"
            backup = Path(directory) / "clean.dylib"
            live.write_bytes(b"currently live")
            backup.write_bytes(b"pristine source")
            with mock.patch.object(apply_catppuccin, "patch_bytes",
                                   side_effect=RuntimeError("forced generation failure")):
                with self.assertRaisesRegex(RuntimeError, "forced generation failure"):
                    apply_catppuccin.patch(live, backup, apply_catppuccin.build_theme("catppuccin"))
            self.assertEqual(live.read_bytes(), b"currently live")

    def test_legacy_preset_behavior_remains_available(self):
        theme = apply_catppuccin.build_theme("catppuccin")
        self.assertEqual(theme["name"], "catppuccin")
        self.assertEqual(theme["roles"]["light"]["base"], apply_catppuccin.LATTE["base"])
        self.assertEqual(apply_catppuccin.color_for_key(theme, "bg0", (0, 0, 0), "dark"),
                         "313244")

    def test_load_config_accepts_custom_schema_snapshot(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "theme.json"
            config = custom_config()
            path.write_text(json.dumps(config), encoding="utf-8")
            self.assertEqual(apply_catppuccin.load_config(path), config)


if __name__ == "__main__":
    unittest.main()
