import importlib.util
import json
import math
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
    return synthetic_slice_with_records(keys)


def synthetic_slice_with_records(canonical_keys, resolved_keys=(), *, omitted_resolved=(),
                                 include_type243=True):
    canonical_keys = list(canonical_keys)
    type1_names = [f"{key}_{side}" for key in resolved_keys for side in ("aqua", "dark")
                   if f"{key}_{side}" not in set(omitted_resolved)]
    records = [(name, 3) for name in canonical_keys]
    records.extend((f"verified_color_{index:03d}", 3)
                   for index in range(max(400, len(canonical_keys)) - len(canonical_keys)))
    records.extend((name, 1) for name in type1_names)
    if include_type243:
        records.append(("unrelated_special", 243))
    record_area = len(records) * 32
    strings = bytearray()
    pointers = []
    for name, _ in records:
        pointers.append(record_area + len(strings))
        strings.extend((name + "\0").encode("ascii"))
    data = bytearray(record_area) + strings
    for index, ((_, record_type), pointer) in enumerate(zip(records, pointers)):
        off = index * 32
        apply_catppuccin.struct.pack_into(
            "<III", data, off + 8, pointer, 0x00600000, record_type)
        if record_type == 3:
            data[off + 20:off + 28] = bytes((200, 30, 60, 90, 155, 180, 120, 40))
        else:
            data[off + 20:off + 24] = bytes((77, 33, 66, 99))
    return bytes(data)


def synthetic_fat_fixture(slices):
    header_size = 8 + len(slices) * 20
    offsets = []
    cursor = (header_size + 7) & ~7
    for payload in slices:
        offsets.append(cursor)
        cursor = (cursor + len(payload) + 7) & ~7
    data = bytearray(cursor)
    data[:4] = bytes.fromhex("cafebabe")
    apply_catppuccin.struct.pack_into(">I", data, 4, len(slices))
    for index, (offset, payload) in enumerate(zip(offsets, slices)):
        apply_catppuccin.struct.pack_into(
            ">IIIII", data, 8 + index * 20, 0x0100000C, index, offset, len(payload), 3)
        data[offset:offset + len(payload)] = payload
    return bytes(data)


def structured_records(payload):
    result = []
    for slice_index, (base, size) in enumerate(apply_catppuccin.parse_fat_slices(payload)):
        end = base + size
        for off in range(base, max(base, end - 47), 8):
            if off + 28 > end or payload[off:off + 8] != b"\0" * 8:
                continue
            pointer, tag, record_type = apply_catppuccin.struct.unpack_from("<III", payload, off + 8)
            if tag != 0x00600000 or not (0 < pointer < size):
                continue
            start = base + pointer
            zero = payload.find(b"\0", start, min(start + 128, end))
            if zero < 0:
                continue
            name = payload[start:zero].decode("ascii")
            width = 8 if record_type == 3 else 4
            result.append((slice_index, name, record_type, payload[off + 20:off + 20 + width]))
    return result


class DirectColorConfigTests(unittest.TestCase):
    BUILTIN_SNAPSHOT = {
        "catppuccin": {
            "light": ("#EFF1F5", "#E6E9EF", "#DCE0E8", "#BCC0CC", "#CCD0DA", "#4C4F69", "#6C6F85", "#7287FD", "#175CD3", "#D20F39"),
            "dark": ("#1E1E2E", "#181825", "#303446", "#45475A", "#313244", "#CDD6F4", "#A6ADC8", "#B4BEFE", "#F9E2AF", "#F38BA8"),
        },
        "catppuccin-frappe": {
            "light": ("#EFF1F5", "#E6E9EF", "#DCE0E8", "#DCE8D5", "#F7F7F9", "#4C4F69", "#5C5F77", "#179299", "#1E66F5", "#D20F39"),
            "dark": ("#303446", "#292C3C", "#232634", "#51576D", "#414559", "#C6D0F5", "#B5BFE2", "#81C8BE", "#99D1DB", "#E78284"),
        },
        "catppuccin-macchiato": {
            "light": ("#EFF1F5", "#E6E9EF", "#DCE0E8", "#DCE8D5", "#F7F7F9", "#4C4F69", "#5C5F77", "#179299", "#1E66F5", "#D20F39"),
            "dark": ("#24273A", "#1E2030", "#181926", "#494D64", "#363A4F", "#CAD3F5", "#B8C0E0", "#8BD5CA", "#91D7E3", "#ED8796"),
        },
        "gruvbox": {
            "light": ("#FBF1C7", "#F2E5BC", "#EBDBB2", "#D5C4A1", "#EBDBB2", "#3C3836", "#665C54", "#D65D0E", "#076678", "#CC241D"),
            "dark": ("#282828", "#242424", "#1D2021", "#504945", "#3C3836", "#EBDBB2", "#BDAE93", "#FE8019", "#8EC07C", "#FB4934"),
        },
        "tokyo-night": {
            "light": ("#D5D6DB", "#D0D1D6", "#CBCCD1", "#B7C1E3", "#C4C8DA", "#343B58", "#565A6E", "#5A4A78", "#34548A", "#8C4351"),
            "dark": ("#1A1B26", "#1F2335", "#16161E", "#3B4261", "#24283B", "#C0CAF5", "#A9B1D6", "#BB9AF7", "#7DCFFF", "#F7768E"),
        },
    }
    COLOR_KEYS = ("base", "sidebar", "ribbon", "outgoing_bubble", "incoming_bubble",
                  "text", "subtext", "accent", "link", "danger")

    @staticmethod
    def contrast_ratio(first, second):
        def luminance(color):
            channels = [int(color[index:index + 2], 16) / 255.0 for index in (1, 3, 5)]
            linear = [channel / 12.92 if channel <= 0.04045
                      else math.pow((channel + 0.055) / 1.055, 2.4)
                      for channel in channels]
            return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
        bright, dark = sorted((luminance(first), luminance(second)), reverse=True)
        return (bright + 0.05) / (dark + 0.05)

    def test_builtin_preset_snapshot_and_objective_c_editor_are_identical(self):
        editor_path = MODULE_PATH.parents[1] / "SovietExtension" / "DirectColorThemeEditorState.m"
        editor = editor_path.read_text(encoding="utf-8")
        for preset, appearances in self.BUILTIN_SNAPSHOT.items():
            theme = apply_catppuccin.build_theme(preset)
            for side, expected_values in appearances.items():
                expected = dict(zip(self.COLOR_KEYS, expected_values))
                actual = {key: "#" + theme["roles"][side][key].upper() for key in self.COLOR_KEYS}
                self.assertEqual(actual, expected, (preset, side))
                objc_arguments = ", ".join(f'@"{color}"' for color in expected_values)
                self.assertIn(f'@"{side}":Colors({objc_arguments})', editor)

    def test_builtin_links_have_three_to_one_contrast_on_both_real_bubbles(self):
        for preset, appearances in self.BUILTIN_SNAPSHOT.items():
            for side, values in appearances.items():
                colors = dict(zip(self.COLOR_KEYS, values))
                for bubble in ("incoming_bubble", "outgoing_bubble"):
                    ratio = self.contrast_ratio(colors["link"], colors[bubble])
                    with self.subTest(preset=preset, appearance=side, bubble=bubble):
                        self.assertGreaterEqual(ratio, 3.0)

    def test_catppuccin_dark_link_is_exact_yellow(self):
        theme = apply_catppuccin.build_theme("catppuccin")
        self.assertEqual(theme["roles"]["dark"]["link"], "f9e2af")
        for named_key in ("link", "link_self", "link_hover", "link_click"):
            with self.subTest(named_key=named_key):
                self.assertEqual(
                    apply_catppuccin.color_for_key(theme, named_key, (0, 0, 0), "dark"),
                    "f9e2af")

    def test_actual_incoming_and_outgoing_body_text_records_use_direct_text(self):
        theme = apply_catppuccin.build_theme("catppuccin")
        self.assertEqual(theme["roles"]["dark"]["text"], "cdd6f4")
        self.assertEqual(apply_catppuccin.BUBBLE_TEXT_KEYS, {"fg0", "glyph0_self"})
        for named_key in apply_catppuccin.BUBBLE_TEXT_KEYS:
            with self.subTest(named_key=named_key):
                self.assertEqual(apply_catppuccin.semantic_role(named_key), "text")
                color = apply_catppuccin.color_for_key(theme, named_key, (0, 0, 0), "dark")
                self.assertEqual(color, "cdd6f4")
                self.assertNotIn(color, {theme["roles"]["dark"]["subtext"],
                                         theme["roles"]["dark"]["accent"]})
        self.assertEqual(apply_catppuccin.semantic_role("fg_brand"), "accent")
        self.assertEqual(apply_catppuccin.semantic_role("fg_brand_self"), "accent")
        self.assertEqual(apply_catppuccin.semantic_role("fg1"), "subtext")

    def test_patch_updates_real_type1_outgoing_text_slot_and_preserves_alpha(self):
        theme = apply_catppuccin.build_theme("catppuccin")
        theme["advanced"]["dark"].clear()
        # Replace the synthetic fixture's final special record with the real
        # standalone outgoing text slot while retaining 400 canonical records.
        def with_outgoing_slot():
            payload = bytearray(synthetic_slice_with_records(("fg0", "fg_brand_self")))
            # Replace the final type=243 fixture record with a type=1 glyph0_self record.
            off = 400 * 32
            name_pos = len(payload)
            payload.extend(b"glyph0_self\0")
            apply_catppuccin.struct.pack_into("<III", payload, off + 8, name_pos, 0x00600000, 1)
            payload[off + 20:off + 24] = bytes((173, 22, 22, 22))
            return bytes(payload)
        source = synthetic_fat_fixture([with_outgoing_slot(), with_outgoing_slot()])
        output, _, _ = apply_catppuccin.patch_bytes(source, theme)
        outgoing = [record for record in structured_records(output)
                    if record[1] == "glyph0_self" and record[2] == 1]
        self.assertEqual(len(outgoing), 2)
        self.assertTrue(all(value == apply_catppuccin.encoded("cdd6f4", 173)
                            for _, _, _, value in outgoing))
        fg_brand_self = [record for record in structured_records(output)
                         if record[1] == "fg_brand_self" and record[2] == 3]
        self.assertTrue(all(value[4:] == apply_catppuccin.encoded("b4befe", value[4])
                            for _, _, _, value in fg_brand_self))

    def test_catppuccin_mocha_pinned_background_uses_sidebar_not_incoming_bubble(self):
        theme = apply_catppuccin.build_theme("catppuccin")
        dark = theme["roles"]["dark"]
        self.assertEqual(dark["base"], "1e1e2e")
        self.assertEqual(theme["dark"]["mantle"], "181825")
        self.assertEqual(dark["ribbon"], "303446")
        self.assertEqual(dark["incoming_bubble"], "313244")
        self.assertEqual(theme["advanced"]["dark"]["bg0"], "181825")
        self.assertEqual(
            apply_catppuccin.color_for_key(theme, "bg0", (0, 0, 0), "dark"),
            "181825")

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
            "fg_brand_self": "accent", "glyph0_self": "text",
            "chat_input_hit_border_color": "accent",
            "brand_button": "accent", "link": "link", "link_hover": "link",
            "hyperlink_color": "link", "red": "danger", "red_hover": "danger",
            "recording_cancel_end_color": "danger",
        }
        for named_key, role in expected.items():
            with self.subTest(named_key=named_key):
                self.assertEqual(
                    apply_catppuccin.color_for_key(theme, named_key, (9, 8, 7), "light"),
                    TEN_COLORS[role][1:].lower())

    def test_preset_config_accepts_all_ten_direct_colors_and_maps_sidebar_and_danger(self):
        dark_colors = {key: "#" + format(int(value[1:], 16) + 0x030303, "06x")
                       for key, value in TEN_COLORS.items()}
        theme = apply_catppuccin.build_theme("", {
            "preset": "catppuccin",
            "light": dict(TEN_COLORS),
            "dark": dark_colors,
        })

        self.assertEqual(theme["name"], "catppuccin")
        self.assertEqual(theme["roles"]["light"]["sidebar"], "111213")
        self.assertEqual(theme["roles"]["light"]["danger"], "919293")
        self.assertEqual(theme["roles"]["dark"]["sidebar"], dark_colors["sidebar"][1:])
        self.assertEqual(theme["roles"]["dark"]["danger"], dark_colors["danger"][1:])
        self.assertEqual(
            apply_catppuccin.color_for_key(theme, "bg_sidebar_alt", (0, 0, 0), "light"),
            "111213")
        self.assertEqual(
            apply_catppuccin.color_for_key(theme, "red", (0, 0, 0), "dark"),
            dark_colors["danger"][1:])

    def test_preset_config_rejects_an_unknown_eleventh_direct_color(self):
        colors = dict(TEN_COLORS)
        colors["generated_tone"] = "#abcdef"
        with self.assertRaisesRegex(ValueError, r"unknown light.*generated_tone"):
            apply_catppuccin.build_theme("", {
                "preset": "catppuccin",
                "light": colors,
                "dark": dict(TEN_COLORS),
            })

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
                         "181825")

    def test_resolved_type1_mirrors_are_opt_in_strict_and_alpha_preserving(self):
        source = synthetic_fat_fixture([
            synthetic_slice_with_records(("bg0", "bg1", "bg2"), ("bg1", "bg2")),
            synthetic_slice_with_records(("bg0", "bg1", "bg2"), ("bg1", "bg2")),
        ])
        theme = apply_catppuccin.build_theme("catppuccin")
        before = structured_records(source)

        default_output, _, _ = apply_catppuccin.patch_bytes(source, theme)
        default_records = structured_records(default_output)
        self.assertEqual(
            [record for record in before if record[2] == 1],
            [record for record in default_records if record[2] == 1])

        output, patched, _ = apply_catppuccin.patch_bytes(
            source, theme, resolved_color_keys={"bg1", "bg2"})
        after = structured_records(output)
        before_by_id = {(s, key, kind): value for s, key, kind, value in before}
        after_by_id = {(s, key, kind): value for s, key, kind, value in after}
        changed_type1 = []
        for identity, old in before_by_id.items():
            if identity[2] == 1 and after_by_id[identity] != old:
                changed_type1.append(identity)
                self.assertEqual(after_by_id[identity][0], old[0])
        self.assertEqual(set(changed_type1), {
            (slice_index, f"{key}_{side}", 1)
            for slice_index in (0, 1)
            for key in ("bg1", "bg2")
            for side in ("aqua", "dark")
        })
        self.assertEqual(len(changed_type1), 8)
        self.assertGreaterEqual(patched, 708)
        self.assertEqual(
            [record for record in before if record[2] == 243],
            [record for record in after if record[2] == 243])

    def test_resolved_type1_missing_mirror_slice_or_canonical_fails_closed(self):
        cases = {
            "missing mirror": [
                synthetic_slice_with_records(("bg0", "bg1", "bg2"), ("bg1", "bg2"),
                                             omitted_resolved=("bg2_dark",)),
                synthetic_slice_with_records(("bg0", "bg1", "bg2"), ("bg1", "bg2")),
            ],
            "missing slice": [
                synthetic_slice_with_records(("bg0", "bg1", "bg2"), ("bg1", "bg2")),
                synthetic_slice_with_records(("bg0", "bg1", "bg2"), ()),
            ],
            "missing canonical": [
                synthetic_slice_with_records(("bg0", "bg1", "bg2"), ("bg1", "bg2")),
                synthetic_slice_with_records(("bg0", "bg1"), ("bg1", "bg2")),
            ],
        }
        theme = apply_catppuccin.build_theme("catppuccin")
        for label, slices in cases.items():
            with self.subTest(label=label), tempfile.TemporaryDirectory() as directory:
                source = synthetic_fat_fixture(slices)
                live = Path(directory) / "live.dylib"
                live.write_bytes(source)
                with self.assertRaisesRegex(RuntimeError, "resolved-color"):
                    apply_catppuccin.patch(
                        live, None, theme, resolved_color_keys={"bg1", "bg2"})
                self.assertEqual(live.read_bytes(), source)

    def test_load_config_accepts_custom_schema_snapshot(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "theme.json"
            config = custom_config()
            path.write_text(json.dumps(config), encoding="utf-8")
            self.assertEqual(apply_catppuccin.load_config(path), config)


if __name__ == "__main__":
    unittest.main()
