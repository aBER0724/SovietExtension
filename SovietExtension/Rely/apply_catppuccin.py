#!/usr/bin/env python3
"""Patch WeChat 4.x named Qt/mmui theme records with selectable light/dark themes."""
from __future__ import annotations

import argparse
import colorsys
import json
import os
import re
import shutil
import struct
import sys
import tempfile
import uuid
from pathlib import Path
from typing import Any

# Kept as public constants for callers that imported the original script.
LATTE = {
    "rosewater":"dc8a78","flamingo":"dd7878","pink":"ea76cb","mauve":"8839ef",
    "red":"d20f39","maroon":"e64553","peach":"fe640b","yellow":"df8e1d",
    "green":"40a02b","teal":"179299","sky":"04a5e5","sapphire":"209fb5",
    "blue":"1e66f5","lavender":"7287fd","text":"4c4f69","subtext1":"5c5f77",
    "subtext0":"6c6f85","overlay2":"7c7f93","overlay1":"8c8fa1","overlay0":"9ca0b0",
    "surface2":"acb0be","surface1":"bcc0cc","surface0":"ccd0da","base":"eff1f5",
    "mantle":"e6e9ef","crust":"dce0e8",
}
MOCHA = {
    "rosewater":"f5e0dc","flamingo":"f2cdcd","pink":"f5c2e7","mauve":"cba6f7",
    "red":"f38ba8","maroon":"eba0ac","peach":"fab387","yellow":"f9e2af",
    "green":"a6e3a1","teal":"94e2d5","sky":"89dceb","sapphire":"74c7ec",
    "blue":"89b4fa","lavender":"b4befe","text":"cdd6f4","subtext1":"bac2de",
    "subtext0":"a6adc8","overlay2":"9399b2","overlay1":"7f849c","overlay0":"6c7086",
    "surface2":"585b70","surface1":"45475a","surface0":"313244","base":"1e1e2e",
    "mantle":"181825","crust":"11111b",
}

FRAPPE = {
    "rosewater":"f2d5cf","flamingo":"eebebe","pink":"f4b8e4","mauve":"ca9ee6",
    "red":"e78284","maroon":"ea999c","peach":"ef9f76","yellow":"e5c890",
    "green":"a6d189","teal":"81c8be","sky":"99d1db","sapphire":"85c1dc",
    "blue":"8caaee","lavender":"babbf1","text":"c6d0f5","subtext1":"b5bfe2",
    "subtext0":"a5adce","overlay2":"949cbb","overlay1":"838ba7","overlay0":"737994",
    "surface2":"626880","surface1":"51576d","surface0":"414559","base":"303446",
    "mantle":"292c3c","crust":"232634",
}
MACCHIATO = {
    "rosewater":"f4dbd6","flamingo":"f0c6c6","pink":"f5bde6","mauve":"c6a0f6",
    "red":"ed8796","maroon":"ee99a0","peach":"f5a97f","yellow":"eed49f",
    "green":"a6da95","teal":"8bd5ca","sky":"91d7e3","sapphire":"7dc4e4",
    "blue":"8aadf4","lavender":"b7bdf8","text":"cad3f5","subtext1":"b8c0e0",
    "subtext0":"a5adcb","overlay2":"939ab7","overlay1":"8087a2","overlay0":"6e738d",
    "surface2":"5b6078","surface1":"494d64","surface0":"363a4f","base":"24273a",
    "mantle":"1e2030","crust":"181926",
}

GRUVBOX_LIGHT = {
    "rosewater":"b16286","flamingo":"cc241d","pink":"b16286","mauve":"8f3f71",
    "red":"cc241d","maroon":"9d0006","peach":"d65d0e","yellow":"d79921",
    "green":"98971a","teal":"689d6a","sky":"458588","sapphire":"076678",
    "blue":"458588","lavender":"8f3f71","text":"3c3836","subtext1":"504945",
    "subtext0":"665c54","overlay2":"7c6f64","overlay1":"928374","overlay0":"a89984",
    "surface2":"bdae93","surface1":"d5c4a1","surface0":"ebdbb2","base":"fbf1c7",
    "mantle":"f2e5bc","crust":"e5d5ad",
}
GRUVBOX_DARK = {
    "rosewater":"d3869b","flamingo":"fb4934","pink":"d3869b","mauve":"b16286",
    "red":"fb4934","maroon":"cc241d","peach":"fe8019","yellow":"fabd2f",
    "green":"b8bb26","teal":"8ec07c","sky":"83a598","sapphire":"458588",
    "blue":"83a598","lavender":"d3869b","text":"ebdbb2","subtext1":"d5c4a1",
    "subtext0":"bdae93","overlay2":"a89984","overlay1":"928374","overlay0":"7c6f64",
    "surface2":"665c54","surface1":"504945","surface0":"3c3836","base":"282828",
    "mantle":"1d2021","crust":"1b1b1b",
}
TOKYO_LIGHT = {
    "rosewater":"8c6c6c","flamingo":"8c4351","pink":"a440b5","mauve":"5a4a78",
    "red":"8c4351","maroon":"8f5e8f","peach":"965027","yellow":"8f5e15",
    "green":"33635c","teal":"166775","sky":"0f4b6e","sapphire":"34548a",
    "blue":"34548a","lavender":"5a4a78","text":"3760bf","subtext1":"4c505e",
    "subtext0":"6172b0","overlay2":"8990b3","overlay1":"9699a3","overlay0":"a8aecb",
    "surface2":"b4b5b9","surface1":"cbccd1","surface0":"dfe0e5","base":"e6e7ed",
    "mantle":"dcdee3","crust":"d5d6db",
}
TOKYO_DARK = {
    "rosewater":"c0caf5","flamingo":"f7768e","pink":"bb9af7","mauve":"9d7cd8",
    "red":"f7768e","maroon":"db4b4b","peach":"ff9e64","yellow":"e0af68",
    "green":"9ece6a","teal":"73daca","sky":"7dcfff","sapphire":"2ac3de",
    "blue":"7aa2f7","lavender":"bb9af7","text":"c0caf5","subtext1":"a9b1d6",
    "subtext0":"9aa5ce","overlay2":"787c99","overlay1":"565f89","overlay0":"414868",
    "surface2":"3b4261","surface1":"292e42","surface0":"24283b","base":"1a1b26",
    "mantle":"16161e","crust":"101014",
}

FAMILY = {
    "red":"red", "green":"green", "lightgreen":"green", "light_green":"green",
    "brand":"teal", "link":"blue", "orange":"peach", "yellow":"yellow",
    "blue":"blue", "indigo":"lavender", "purple":"mauve", "rainbow_green":"green",
}
EXACT = {
    "bg0":"mantle", "bg1":"base", "bg2":"base", "bg3":"mantle", "bg4":"surface2",
    "bg_selection":"surface2", "bg_sidebar_alt":"crust", "navigation_bar":"mantle",
    "material_thick":"mantle", "material_regular":"surface0", "material_thin":"surface1",
    "fg0":"text", "fg1":"subtext1", "fg2":"subtext0", "fg3":"overlay2",
    "fg4":"overlay1", "fg5":"overlay0", "fg6":"surface2",
    "glyph0":"text", "glyph1":"subtext0", "glyph2":"overlay1", "glyph_black":"text",
    "glyph_selected_title":"text", "glyph_selected_subtitle":"subtext1",
    "text1":"text", "text2":"subtext1", "text3":"subtext0", "fg_transparent":"text",
    "fg_brand":"teal", "fg_brand_self":"green", "text_highlight":"yellow",
    "text_highlight_text":"crust", "tab_select":"text", "tab_unselect":"overlay1",
    "bg0_transparent":"mantle", "bg1_transparent":"base", "bg2_transparent":"surface0",
    "flow_layer":"base", "flow_toolbar_bg":"mantle", "flow_button_bg":"surface0",
    "flow_cover_bg":"crust", "sns_bg":"base", "dialog_border_color":"surface1",
    "win10_border_activated":"lavender", "win10_border_deactivated":"surface1",
    "chat_right_bubble_color":"lavender", "chat_left_bubble_color":"surface0",
    "chat_brand_page_bkg":"base", "chat_input_hit_border_color":"teal",
    "chat_input_long_text_border_color":"overlay0", "chat_info_tips_bar_voip_bg":"surface0",
    "chat_voice_input_recording_bgcolor":"surface0", "voice_input_recording_bgcolor":"surface0",
    "voice_input_window_popup_bgcolor":"surface0", "voice_input_window_bgcolor":"base",
    "voice_input_window_animate_fgcolor":"mauve", "voice_input_window_bgcolor_transparent":"base",
    "voice_input_guide_window_bgcolor":"mantle", "voice_input_guide_shortcut_bgcolor":"surface1",
    "recording_gradient_start_color":"mauve", "recording_gradient_end_color":"blue",
    "recording_click_highlight_color":"lavender", "recording_cancel_end_color":"red",
    "chat_gradient1_start_color":"surface0", "extension_tab_animate_bgcolor":"surface0",
    "clawbot_interact_button_disable_fgcolor":"overlay0",
}
CORE_TONES = {"base", "ribbon", "outgoing_bubble", "incoming_bubble", "text", "subtext", "link", "accent"}
DIRECT_COLORS = {"base", "sidebar", "ribbon", "outgoing_bubble", "incoming_bubble",
                 "text", "subtext", "accent", "link", "danger"}
CUSTOM_ROOT_FIELDS = {"schema_version", "preset", "custom_theme_id", "light", "dark", "advanced"}
HEX_COLOR = re.compile(r"^#?([0-9a-fA-F]{6})$")


def _roles(light: dict[str, str], dark: dict[str, str], *, outgoing_light: str,
           outgoing_dark: str, incoming_light: str, incoming_dark: str) -> dict[str, dict[str, str]]:
    return {
        "light": {"base":"#" + light["base"], "ribbon":"#" + light["mantle"],
                  "outgoing_bubble":outgoing_light, "incoming_bubble":incoming_light,
                  "text":"#" + light["text"], "subtext":"#" + light["subtext1"],
                  "link":"#" + light["blue"], "accent":"#" + light["teal"]},
        "dark": {"base":"#" + dark["base"], "ribbon":"#" + dark["mantle"],
                 "outgoing_bubble":outgoing_dark, "incoming_bubble":incoming_dark,
                 "text":"#" + dark["text"], "subtext":"#" + dark["subtext1"],
                 "link":"#" + dark["blue"], "accent":"#" + dark["teal"]},
    }


PRESETS: dict[str, dict[str, Any]] = {
    "catppuccin": {"light": LATTE, "dark": MOCHA,
        "roles": _roles(LATTE, MOCHA, outgoing_light="#bcc0cc", outgoing_dark="#9399b2",
                        incoming_light="#ccd0da", incoming_dark="#313244"),
        "advanced": {"dark": {"bg0": "#313244"}}},
    "catppuccin-frappe": {"light": LATTE, "dark": FRAPPE,
        "roles": _roles(LATTE, FRAPPE, outgoing_light="#dce8d5", outgoing_dark="#b5d09f",
                        incoming_light="#f7f7f9", incoming_dark="#414559")},
    "catppuccin-macchiato": {"light": LATTE, "dark": MACCHIATO,
        "roles": _roles(LATTE, MACCHIATO, outgoing_light="#dce8d5", outgoing_dark="#b5d7a5",
                        incoming_light="#f7f7f9", incoming_dark="#363a4f")},
    "gruvbox": {"light": GRUVBOX_LIGHT, "dark": GRUVBOX_DARK,
        "roles": _roles(GRUVBOX_LIGHT, GRUVBOX_DARK, outgoing_light="#d5c4a1", outgoing_dark="#a89984",
                        incoming_light="#ebdbb2", incoming_dark="#3c3836")},
    "tokyo-night": {"light": TOKYO_LIGHT, "dark": TOKYO_DARK,
        "roles": _roles(TOKYO_LIGHT, TOKYO_DARK, outgoing_light="#b7c1e3", outgoing_dark="#7aa2d6",
                        incoming_light="#c4c8da", incoming_dark="#24283b")},
}


def parse_color(value: str) -> str:
    if not isinstance(value, str):
        raise ValueError(f"color must be a string, got {type(value).__name__}")
    match = HEX_COLOR.fullmatch(value)
    if not match:
        raise ValueError(f"invalid color {value!r}; expected #RRGGBB")
    return match.group(1).lower()


def rgb(hex_color: str) -> tuple[int, int, int]:
    return tuple(bytes.fromhex(parse_color(hex_color)))  # type: ignore[return-value]


def encoded(hex_color: str, alpha: int) -> bytes:
    r, g, b = rgb(hex_color)
    return bytes((alpha, b, g, r))


def load_config(path: Path | None) -> dict[str, Any]:
    if path is None:
        return {}
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"cannot read config {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise ValueError("config root must be a JSON object")
    allowed = (CUSTOM_ROOT_FIELDS if value.get("schema_version") == 2
               else {"preset", "light", "dark", "advanced"})
    unknown = sorted(set(value) - allowed)
    if unknown:
        raise ValueError(f"unknown config keys: {', '.join(unknown)}")
    return value


def _parse_advanced(config: dict[str, Any], theme: dict[str, Any]) -> None:
    advanced = config.get("advanced", {})
    if not isinstance(advanced, dict):
        raise ValueError("config advanced must be an object")
    for key, value in advanced.items():
        if key in ("light", "dark"):
            if not isinstance(value, dict):
                raise ValueError(f"advanced.{key} must be an object")
            for named_key, color in value.items():
                named_key = str(named_key)
                try:
                    theme["advanced"][key][named_key] = parse_color(color)
                except ValueError as exc:
                    raise ValueError(f"advanced.{key}.{named_key}: {exc}") from exc
        else:
            key = str(key)
            if isinstance(value, str):
                color = parse_color(value)
                theme["advanced"]["light"][key] = color
                theme["advanced"]["dark"][key] = color
            elif isinstance(value, dict):
                unknown = sorted(set(value) - {"light", "dark"})
                if unknown or not value:
                    raise ValueError(f"advanced.{key} must contain only light/dark")
                for side, color in value.items():
                    theme["advanced"][side][key] = parse_color(color)
            else:
                raise ValueError(f"advanced.{key} must be a color or light/dark object")


def _build_custom_theme(config: dict[str, Any]) -> dict[str, Any]:
    unknown = sorted(set(config) - CUSTOM_ROOT_FIELDS)
    if unknown:
        raise ValueError(f"unknown config keys: {', '.join(unknown)}")
    missing_root = sorted(CUSTOM_ROOT_FIELDS - set(config))
    if missing_root:
        raise ValueError(f"missing config keys: {', '.join(missing_root)}")
    if config["schema_version"] != 2:
        raise ValueError("custom schema_version must be 2")
    if config["preset"] is not None:
        raise ValueError("custom config preset must be null")
    theme_id = config["custom_theme_id"]
    if not isinstance(theme_id, str):
        raise ValueError("custom_theme_id must be a valid UUID string")
    try:
        uuid.UUID(theme_id)
    except (ValueError, AttributeError) as exc:
        raise ValueError("custom_theme_id must be a valid UUID string") from exc

    theme: dict[str, Any] = {
        "name": "custom", "custom_theme_id": theme_id,
        "roles": {"light": {}, "dark": {}},
        "advanced": {"light": {}, "dark": {}},
        "direct": True,
    }
    for side in ("light", "dark"):
        colors = config[side]
        if not isinstance(colors, dict):
            raise ValueError(f"config {side} must be an object")
        missing = sorted(DIRECT_COLORS - set(colors))
        unknown = sorted(set(colors) - DIRECT_COLORS)
        if missing:
            raise ValueError(f"config {side} missing colors: {', '.join(missing)}")
        if unknown:
            raise ValueError(f"config {side} unknown colors: {', '.join(unknown)}")
        for key, value in colors.items():
            try:
                theme["roles"][side][key] = parse_color(value)
            except ValueError as exc:
                raise ValueError(f"config {side}.{key}: {exc}") from exc
    _parse_advanced(config, theme)
    return theme


def build_theme(preset: str, config: dict[str, Any] | None = None) -> dict[str, Any]:
    config = config or {}
    if config.get("schema_version") == 2 or "custom_theme_id" in config:
        return _build_custom_theme(config)
    config_preset = config.get("preset")
    if config_preset is not None and not isinstance(config_preset, str):
        raise ValueError("config preset must be a string")
    name = preset or config_preset or "catppuccin"
    if name not in PRESETS:
        raise ValueError(f"unknown preset {name!r}; use --list-presets")
    source = PRESETS[name]
    theme: dict[str, Any] = {
        "name": name, "light": dict(source["light"]), "dark": dict(source["dark"]),
        "roles": {side: {key: parse_color(value) for key, value in source["roles"][side].items()}
                  for side in ("light", "dark")},
        "advanced": {side: {str(key): parse_color(value)
                            for key, value in source.get("advanced", {}).get(side, {}).items()}
                     for side in ("light", "dark")},
    }
    for side in ("light", "dark"):
        overrides = config.get(side, {})
        if not isinstance(overrides, dict):
            raise ValueError(f"config {side} must be an object")
        unknown = sorted(set(overrides) - CORE_TONES)
        if unknown:
            raise ValueError(f"unknown {side} semantic tones: {', '.join(unknown)}")
        for key, value in overrides.items():
            theme["roles"][side][key] = parse_color(value)

    _parse_advanced(config, theme)
    return theme


def suffix_tone(key: str, base: str) -> str:
    if "disable" in key or key.endswith("_170"):
        return "surface1"
    if key.endswith(("_130", "_120", "_80", "_90")) or "hover" in key or "click" in key:
        return base
    if "_bg_" in key or key.endswith("_bg") or "background" in key or "bkg" in key:
        return "surface0"
    return base


def semantic_tone(key: str, old_rgb: tuple[int, int, int], dark: bool,
                  palette: dict[str, str] | None = None) -> str:
    lower = key.lower()
    if key in EXACT:
        return EXACT[key]
    for prefix, tone in FAMILY.items():
        if lower == prefix or lower.startswith(prefix + "_"):
            return suffix_tone(lower, tone)
    if "selected" in lower or "highlight" in lower or "active" in lower:
        return "lavender"
    if any(word in lower for word in ("border", "separator", "divider", "state", "layer", "mask", "cover")):
        return "surface1"
    if any(word in lower for word in ("bg", "background", "bkg", "bar", "window", "dialog", "toolbar")):
        return "surface0"
    if any(word in lower for word in ("font", "text", "fg", "glyph", "title", "subtitle")):
        return "text"

    r, g, b = (v / 255.0 for v in old_rgb)
    h, saturation, value = colorsys.rgb_to_hsv(r, g, b)
    if saturation < 0.12:
        neutral = ["crust", "mantle", "base", "surface0", "surface1", "surface2",
                   "overlay0", "overlay1", "overlay2", "subtext0", "subtext1", "text"]
        index = round(value * (len(neutral) - 1)) if dark else round((1.0 - value) * (len(neutral) - 1))
        return neutral[max(0, min(index, len(neutral) - 1))]
    accents = ["red", "peach", "yellow", "green", "teal", "sky", "blue", "lavender", "mauve", "pink"]
    selected_palette = palette or (MOCHA if dark else LATTE)
    def hue_distance(name: str) -> float:
        candidate = colorsys.rgb_to_hsv(*(x / 255 for x in rgb(selected_palette[name])))[0]
        distance = abs(candidate - h)
        return min(distance, 1 - distance)
    return min(accents, key=hue_distance)


def semantic_role(key: str) -> str | None:
    lower = key.lower()
    if lower == "chat_right_bubble_color":
        return "outgoing_bubble"
    if lower == "chat_left_bubble_color":
        return "incoming_bubble"
    if lower in {"bg1", "bg2", "flow_layer", "sns_bg", "chat_brand_page_bkg"}:
        return "base"
    if lower == "bg_sidebar_alt":
        return "sidebar"
    if lower in {"bg0", "bg3", "navigation_bar", "flow_toolbar_bg"} or "ribbon" in lower:
        return "ribbon"
    if lower == "link" or lower.startswith("link_") or "hyperlink" in lower:
        return "link"
    if lower in {"fg_brand", "fg_brand_self", "chat_input_hit_border_color"} or lower.startswith("brand_"):
        return "accent"
    if lower == "red" or lower.startswith("red_") or lower == "recording_cancel_end_color":
        return "danger"
    if lower in {"fg1", "fg2", "fg3", "text2", "text3", "glyph1", "glyph2"} or "subtitle" in lower:
        return "subtext"
    if lower in {"fg0", "text1", "glyph0", "glyph_black", "glyph_selected_title"}:
        return "text"
    return None


def direct_fallback_role(key: str) -> str:
    lower = key.lower()
    if "danger" in lower or lower == "red" or lower.startswith("red_") or "cancel" in lower:
        return "danger"
    if "brand" in lower or "selected" in lower or "active" in lower or "highlight" in lower:
        return "accent"
    if "link" in lower:
        return "link"
    if "sidebar" in lower:
        return "sidebar"
    if any(word in lower for word in ("bg", "background", "bkg", "bar", "window", "dialog",
                                       "toolbar", "layer", "mask", "cover")):
        return "base"
    if any(word in lower for word in ("subtext", "subtitle", "secondary", "disabled")):
        return "subtext"
    return "text"


def color_for_key(theme: dict[str, Any], key: str, old_rgb: tuple[int, int, int], side: str) -> str:
    advanced = theme["advanced"][side]
    if key in advanced:
        return advanced[key]
    role = semantic_role(key)
    if role and role in theme["roles"][side]:
        return theme["roles"][side][role]
    if theme.get("direct"):
        return theme["roles"][side][direct_fallback_role(key)]
    tone = semantic_tone(key, old_rgb, side == "dark", theme[side])
    return theme[side][tone]


def parse_fat_slices(data: bytes | bytearray) -> list[tuple[int, int]]:
    if len(data) < 8 or data[:4] != bytes.fromhex("cafebabe"):
        return [(0, len(data))]
    count = struct.unpack_from(">I", data, 4)[0]
    if count == 0 or count > 64 or 8 + count * 20 > len(data):
        raise RuntimeError("invalid Mach-O fat header")
    result = []
    for i in range(count):
        _, _, offset, size, _ = struct.unpack_from(">IIIII", data, 8 + i * 20)
        if size == 0 or offset > len(data) or size > len(data) - offset:
            raise RuntimeError("invalid Mach-O fat slice bounds")
        result.append((offset, size))
    return result


def _type3_records(source: bytes, slices: list[tuple[int, int]]) -> list[tuple[int, str]]:
    records: list[tuple[int, str]] = []
    for base, size in slices:
        end = base + size
        for off in range(base, max(base, end - 47), 8):
            if off + 28 > end or source[off:off+8] != b"\0" * 8:
                continue
            ptr, tag, record_type = struct.unpack_from("<III", source, off + 8)
            if tag != 0x00600000 or record_type != 3 or not (0 < ptr < size):
                continue
            string_pos = base + ptr
            zero = source.find(b"\0", string_pos, min(string_pos + 128, end))
            if zero < 0:
                continue
            try:
                key = source[string_pos:zero].decode("ascii")
            except UnicodeDecodeError:
                continue
            if key and all(c.isalnum() or c in "_./:-" for c in key):
                records.append((off, key))
    return records


def _validate_advanced_keys(theme: dict[str, Any], canonical_keys: set[str]) -> None:
    advanced_keys = set(theme["advanced"]["light"]) | set(theme["advanced"]["dark"])
    unknown = sorted(advanced_keys - canonical_keys)
    if unknown:
        raise ValueError(f"unknown advanced named key: {', '.join(unknown)}")


def patch_bytes(source: bytes, theme: dict[str, Any], *,
                resolved_color_keys: set[str] | None = None) -> tuple[bytes, int, int]:
    slices = parse_fat_slices(source)
    records = _type3_records(source, slices)
    keys = {key for _, key in records}
    # Advanced overrides are valid only when their exact, case-sensitive names
    # occur as structurally validated type=3 canonical records in this input.
    # Complete this preflight before creating or modifying the output buffer.
    _validate_advanced_keys(theme, keys)

    data = bytearray(source)
    patched = 0
    resolved_patched = 0
    for off, key in records:
        color_pos = off + 20
        old = source[color_pos:color_pos+8]
        light_rgb = (old[3], old[2], old[1])
        dark_rgb = (old[7], old[6], old[5])
        replacement = (encoded(color_for_key(theme, key, light_rgb, "light"), old[0]) +
                       encoded(color_for_key(theme, key, dark_rgb, "dark"), old[4]))
        if old != replacement:
            data[color_pos:color_pos+8] = replacement
            patched += 1

    # Some mmui consumers use single-color records resolved for a particular
    # appearance. Only synchronize records that strictly mirror a validated
    # type=3 base key; unrelated type=1 records and type=243 remain untouched.
    if resolved_color_keys:
        for base, size in slices:
            end = base + size
            for off in range(base, max(base, end - 47), 8):
                if off + 24 > end or data[off:off+8] != b"\0" * 8:
                    continue
                ptr, tag, record_type = struct.unpack_from("<III", data, off + 8)
                if tag != 0x00600000 or record_type != 1 or not (0 < ptr < size):
                    continue
                string_pos = base + ptr
                zero = data.find(0, string_pos, min(string_pos + 128, end))
                if zero < 0:
                    continue
                try:
                    key = bytes(data[string_pos:zero]).decode("ascii")
                except UnicodeDecodeError:
                    continue
                if key.endswith("_aqua"):
                    canonical, side = key[:-5], "light"
                elif key.endswith("_dark"):
                    canonical, side = key[:-5], "dark"
                else:
                    continue
                if canonical not in keys or canonical not in resolved_color_keys:
                    continue
                color_pos = off + 20
                old = bytes(data[color_pos:color_pos+4])
                old_rgb = (old[3], old[2], old[1])
                replacement = encoded(color_for_key(theme, canonical, old_rgb, side), old[0])
                if old != replacement:
                    data[color_pos:color_pos+4] = replacement
                    patched += 1
                    resolved_patched += 1
        expected_minimum = len(resolved_color_keys) * len(slices)
        if resolved_patched < expected_minimum:
            raise RuntimeError(
                f"refusing unsafe resolved-color patch: patched={resolved_patched}, "
                f"expected at least {expected_minimum}")

    if patched - resolved_patched < 350 or len(keys) < 190:
        raise RuntimeError(
            f"refusing unsafe patch: patched={patched - resolved_patched}, "
            f"unique named colors={len(keys)}")
    return bytes(data), patched, len(keys)


def preflight(path: Path, backup: Path | None, theme: dict[str, Any],
              *, resolved_color_keys: set[str] | None = None) -> int:
    """Validate and fully generate a patch in memory without writing anything."""
    source_path = backup if backup and backup.exists() else path
    source = source_path.read_bytes()
    _, patched, key_count = patch_bytes(
        source, theme, resolved_color_keys=resolved_color_keys)
    resolved_note = " (including resolved colors)" if resolved_color_keys else ""
    print(f"preflight preset={theme['name']}: patched={patched}, "
          f"unique named colors={key_count}{resolved_note}; source={source_path}")
    return patched


def patch(path: Path, backup: Path | None, theme: dict[str, Any] | None = None,
          *, resolved_color_keys: set[str] | None = None) -> int:
    theme = theme or build_theme("catppuccin")
    if backup and backup.exists():
        source = backup.read_bytes()
        print(f"source loaded from backup: {backup}")
    else:
        source = path.read_bytes()
        if backup:
            backup.parent.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile(dir=backup.parent, prefix=f".{backup.name}.",
                                             delete=False) as handle:
                backup_temp = Path(handle.name)
                handle.write(source)
            try:
                shutil.copystat(path, backup_temp)
                os.replace(backup_temp, backup)
            finally:
                backup_temp.unlink(missing_ok=True)
            print(f"backup: {backup}")

    output, patched, key_count = patch_bytes(
        source, theme, resolved_color_keys=resolved_color_keys)
    with tempfile.NamedTemporaryFile(dir=path.parent, prefix=f".{path.name}.",
                                     delete=False) as handle:
        output_temp = Path(handle.name)
        handle.write(output)
    try:
        shutil.copystat(path, output_temp)
        os.replace(output_temp, path)
    finally:
        output_temp.unlink(missing_ok=True)
    resolved_note = " (including resolved colors)" if resolved_color_keys else ""
    print(f"preset={theme['name']}: patched={patched}, unique named colors={key_count}{resolved_note}")
    return patched


def _synthetic_fixture(count: int = 400) -> bytes:
    record_area = count * 32
    strings = bytearray()
    pointers = []
    names = ["bg0"] + [f"self_test_color_{index:03d}" for index in range(count - 1)]
    for name in names:
        pointers.append(record_area + len(strings))
        strings.extend(f"{name}\0".encode("ascii"))
    data = bytearray(record_area) + strings
    for index, pointer in enumerate(pointers):
        off = index * 32
        struct.pack_into("<III", data, off + 8, pointer, 0x00600000, 3)
        data[off+20:off+28] = bytes((200, 30, 60, 90, 155, 180, 120, 40))
    return bytes(data)


def self_test(source: Path | None = None) -> dict[str, Any]:
    assert parse_color("#Aa00Ff") == "aa00ff"
    for invalid in ("fff", "#gg0000", "#12345678"):
        try:
            parse_color(invalid)
        except ValueError:
            pass
        else:
            raise AssertionError(f"invalid color accepted: {invalid}")
    merged = build_theme("", {"preset":"gruvbox", "light":{"link":"#123456"},
                               "advanced":{"chat_right_bubble_color":{"dark":"#abcdef"}}})
    assert merged["name"] == "gruvbox" and merged["roles"]["light"]["link"] == "123456"
    assert merged["advanced"]["dark"]["chat_right_bubble_color"] == "abcdef"
    for name in ("catppuccin", "gruvbox", "tokyo-night"):
        theme = build_theme(name)
        assert set(theme["roles"]["light"]) == CORE_TONES
        assert set(theme["roles"]["dark"]) == CORE_TONES

    custom_colors = {
        "base":"#010203", "sidebar":"#111213", "ribbon":"#212223",
        "outgoing_bubble":"#313233", "incoming_bubble":"#414243", "text":"#515253",
        "subtext":"#616263", "accent":"#717273", "link":"#818283", "danger":"#919293",
    }
    custom = build_theme("", {
        "schema_version": 2, "preset": None,
        "custom_theme_id": "12345678-1234-5678-1234-567812345678",
        "light": custom_colors, "dark": custom_colors,
        "advanced": {"light": {"bg0": "#abcdef"}, "dark": {}},
    })
    assert color_for_key(custom, "bg_sidebar_alt", (0, 0, 0), "light") == "111213"
    assert color_for_key(custom, "recording_cancel_end_color", (0, 0, 0), "dark") == "919293"
    assert color_for_key(custom, "bg0", (0, 0, 0), "light") == "abcdef"

    payload = source.read_bytes() if source else _synthetic_fixture()
    patch_counts: dict[str, int] = {}
    with tempfile.TemporaryDirectory(prefix="wechat-theme-self-test-") as directory:
        for name in ("catppuccin", "gruvbox", "tokyo-night"):
            offline = Path(directory) / f"offline-copy-{name}.dylib"
            offline.write_bytes(payload)
            output, patched, _ = patch_bytes(offline.read_bytes(), build_theme(name))
            offline.write_bytes(output)
            if offline.read_bytes() == payload:
                raise AssertionError(f"{name} structure patch produced no changes")
            patch_counts[name] = patched
        custom_output, custom_patched, _ = patch_bytes(payload, custom)
        if custom_output == payload:
            raise AssertionError("custom direct-color structure patch produced no changes")
        patch_counts["custom"] = custom_patched
    return {"ok": True, "presets_tested": ["catppuccin", "gruvbox", "tokyo-night"],
            "custom_direct_color_tested": True,
            "structure_source": str(source) if source else "synthetic", "patched": patch_counts}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dylib", nargs="?", type=Path)
    parser.add_argument("--backup", type=Path,
                        help="clean backup; existing backups are restored before every application")
    parser.add_argument("--restore", action="store_true")
    parser.add_argument("--preflight", action="store_true",
                        help="validate and generate the complete patch in memory without writes")
    parser.add_argument("--preset", choices=sorted(PRESETS), default=None)
    parser.add_argument("--config", type=Path, help="JSON semantic/named-key overrides")
    parser.add_argument("--list-presets", action="store_true", help="print preset metadata as JSON")
    parser.add_argument("--self-test", action="store_true",
                        help="run pure-Python tests; optionally test an offline dylib/backup copy")
    parser.add_argument("--patch-resolved-key", action="append", default=[], metavar="KEY",
                        help="synchronize verified type=1 KEY_aqua/KEY_dark mirrors")
    args = parser.parse_args()

    if args.list_presets:
        print(json.dumps({"default":"catppuccin", "presets":sorted(PRESETS)}, separators=(",", ":")))
        return 0
    if args.self_test:
        source = args.backup if args.backup and args.backup.exists() else args.dylib
        if source and not source.exists():
            parser.error(f"self-test source does not exist: {source}")
        print(json.dumps(self_test(source), separators=(",", ":")))
        return 0
    if args.dylib is None:
        parser.error("dylib is required unless --list-presets or --self-test is used")
    if args.restore:
        if not args.backup or not args.backup.exists():
            parser.error("--restore requires an existing --backup")
        shutil.copy2(args.backup, args.dylib)
        print(f"restored: {args.dylib}")
        return 0

    config = load_config(args.config)
    # An explicit CLI preset wins; otherwise a config preset can select it.
    preset = args.preset or config.get("preset") or "catppuccin"
    theme = build_theme(preset, config)
    resolved_color_keys = set(args.patch_resolved_key)
    if args.preflight:
        preflight(args.dylib, args.backup, theme,
                  resolved_color_keys=resolved_color_keys)
        return 0
    patch(args.dylib, args.backup, theme,
          resolved_color_keys=resolved_color_keys)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
