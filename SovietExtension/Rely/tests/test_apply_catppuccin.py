import importlib.util
import json
import os
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


def synthetic_fixture_with_keys(*keys):
    count = max(400, len(keys))
    record_area = count * 32
    strings = bytearray()
    pointers = []
    names = list(keys) + [f"verified_color_{index:03d}" for index in range(count - len(keys))]
    for name in names:
        pointers.append(record_area + len(strings))
        strings.extend((name + "\0").encode("ascii"))
    data = bytearray(record_area) + strings
    for index, pointer in enumerate(pointers):
        off = index * 32
        apply_catppuccin.struct.pack_into("<III", data, off + 8, pointer, 0x00600000, 3)
        data[off + 20:off + 28] = bytes((200, 30, 60, 90, 155, 180, 120, 40))
    return bytes(data)


class DirectColorConfigTests(unittest.TestCase):
    def test_custom_schema_accepts_and_maps_all_ten_colors_directly(self):
        theme = apply_catppuccin.build_theme("", custom_config())
        self.assertEqual(theme["name"], "custom")
        self.assertEqual(theme["roles"]["light"],
                         {key: value[1:].lower() for key, value in TEN_COLORS.items()})
        expected = {
            "bg1": "base", "bg2": "base", "flow_layer": "base", "sns_bg": "base",
            "chat_brand_page_bkg": "base", "bg_sidebar_alt": "sidebar",
            "bg0": "ribbon", "bg3": "ribbon", "navigation_bar": "ribbon",
            "flow_toolbar_bg": "ribbon", "chat_right_bubble_color": "outgoing_bubble",
            "chat_left_bubble_color": "incoming_bubble", "fg0": "text", "text1": "text",
            "glyph0": "text", "glyph_black": "text", "glyph_selected_title": "text",
            "fg1": "subtext", "fg2": "subtext", "fg3": "subtext", "text2": "subtext",
            "text3": "subtext", "glyph1": "subtext", "glyph2": "subtext",
            "glyph_selected_subtitle": "subtext", "fg_brand": "accent",
            "fg_brand_self": "accent", "chat_input_hit_border_color": "accent",
            "brand_button": "accent", "link": "link", "link_hover": "link",
            "hyperlink_color": "link", "red": "danger", "red_hover": "danger",
            "recording_cancel_end_color": "danger",
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

    def test_advanced_keys_require_exact_type3_canonical_key_and_bg0_wins(self):
        config = custom_config()
        config["advanced"]["light"]["bg0"] = "#abcdef"
        theme = apply_catppuccin.build_theme("", config)
        output, _, _ = apply_catppuccin.patch_bytes(synthetic_fixture_with_keys("bg0"), theme)
        self.assertNotEqual(output, synthetic_fixture_with_keys("bg0"))
        self.assertEqual(apply_catppuccin.color_for_key(theme, "bg0", (0, 0, 0), "light"),
                         "abcdef")

        for unknown in ("BG0", "brand_invented", "ribbon_invented"):
            with self.subTest(unknown=unknown):
                bad = custom_config()
                bad["advanced"]["light"][unknown] = "#abcdef"
                bad_theme = apply_catppuccin.build_theme("", bad)
                with self.assertRaisesRegex(ValueError, f"unknown advanced.*{unknown}"):
                    apply_catppuccin.patch_bytes(synthetic_fixture_with_keys("bg0"), bad_theme)

    def test_unknown_advanced_key_fails_before_live_mutation(self):
        config = custom_config()
        config["advanced"]["light"]["not_a_verified_named_key"] = "#abcdef"
        with tempfile.TemporaryDirectory() as directory:
            live = Path(directory) / "live.dylib"
            original = synthetic_fixture_with_keys("bg0")
            live.write_bytes(original)
            theme = apply_catppuccin.build_theme("", config)
            with self.assertRaisesRegex(ValueError, "unknown advanced.*not_a_verified_named_key"):
                apply_catppuccin.patch(live, None, theme)
            self.assertEqual(live.read_bytes(), original)

    def test_first_backup_survives_generation_failure_and_live_is_unchanged(self):
        with tempfile.TemporaryDirectory() as directory:
            live = Path(directory) / "live.dylib"
            backup = Path(directory) / "clean.dylib"
            original = b"first pristine source"
            live.write_bytes(original)
            with mock.patch.object(apply_catppuccin, "patch_bytes",
                                   side_effect=RuntimeError("forced generation failure")):
                with self.assertRaisesRegex(RuntimeError, "forced generation failure"):
                    apply_catppuccin.patch(live, backup, apply_catppuccin.build_theme("catppuccin"))
            self.assertEqual(live.read_bytes(), original)
            self.assertEqual(backup.read_bytes(), original)
            self.assertEqual(list(Path(directory).glob(".clean.dylib.*")), [])

    def test_replace_failure_leaves_live_unchanged_and_cleans_output_temp(self):
        with tempfile.TemporaryDirectory() as directory:
            live = Path(directory) / "live.dylib"
            backup = Path(directory) / "clean.dylib"
            live.write_bytes(b"currently live")
            backup.write_bytes(b"pristine source")
            with mock.patch.object(apply_catppuccin, "patch_bytes",
                                   return_value=(b"complete output", 400, 200)), \
                    mock.patch.object(os, "replace", side_effect=OSError("replace failed")):
                with self.assertRaisesRegex(OSError, "replace failed"):
                    apply_catppuccin.patch(live, backup, apply_catppuccin.build_theme("catppuccin"))
            self.assertEqual(live.read_bytes(), b"currently live")
            self.assertEqual(list(Path(directory).glob(".live.dylib.*")), [])

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
