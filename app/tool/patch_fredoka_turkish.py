#!/usr/bin/env python3
"""
patch_fredoka_turkish.py - Turkish Diacritic Patch for Fredoka Fonts (KelimeVS)

This script patches Fredoka-Bold.ttf and Fredoka-SemiBold.ttf by injecting
precomposed composite TrueType glyphs for missing Turkish characters:
  - scedilla   (U+015F, 'ş')
  - Scedilla   (U+015E, 'Ş')
  - gbreve     (U+011F, 'ğ')
  - Gbreve     (U+011E, 'Ğ')
  - Idotaccent (U+0130, 'İ')

Problem Solved:
  In original Fredoka v2.001 (Latin-1 subset), these 5 glyphs are missing from cmap.
  HarfBuzz decomposes 'ş' into 's' + combining cedilla (U+0327). Since Fredoka lacks
  a GPOS MarkBasePos anchor for 's' + uni0327, the cedilla hook is drawn at the pen
  advance position (x = 523) and yMin = -192, completely detached to the bottom-right.
  By injecting precomposed composite glyphs directly mapped to Unicode codepoints in cmap,
  HarfBuzz loads the unified glyph with exact calibrated coordinates without decomposition.

License & RFN:
  Licensed under SIL Open Font License (OFL) v1.1.
  Original copyright: (c) 2016 The Fredoka Project Authors.
  No Reserved Font Name (RFN) is claimed in original font metadata.
"""

import os
import sys
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables._g_l_y_f import Glyph, GlyphComponent


# Calibrated offsets based on exact glyph bounding boxes and optical centers:
# - Bold: s center=228.5, cedilla center=164 -> ox=65
# - SemiBold: s center=229.5, cedilla center=154 -> ox=76
OFFSETS_BOLD = {
    's': (65, 0),
    'S': (106, 0),
    'g': (89, 0),
    'G': (179, 195),
    'I': (-16, 110),
}

OFFSETS_SEMIBOLD = {
    's': (76, 0),
    'S': (118, 0),
    'g': (89, 0),
    'G': (175, 195),
    'I': (-6, 105),
}

CMAP_MAPPINGS = {
    0x015F: 'scedilla',
    0x015E: 'Scedilla',
    0x011F: 'gbreve',
    0x011E: 'Gbreve',
    0x0130: 'Idotaccent',
}


def create_composite_glyph(base_name: str, mark_name: str, offset_x: int, offset_y: int) -> Glyph:
    """Creates a TrueType composite glyph referencing base and mark components."""
    g = Glyph()
    g.numberOfContours = -1  # Composite glyph marker

    # Component 1: Base glyph (uses metrics of the base glyph)
    c1 = GlyphComponent()
    c1.glyphName = base_name
    c1.x = 0
    c1.y = 0
    c1.flags = 0x404  # ARGS_ARE_XY_VALUES | USE_MY_METRICS

    # Component 2: Mark glyph (placed at specific offset relative to base origin)
    c2 = GlyphComponent()
    c2.glyphName = mark_name
    c2.x = offset_x
    c2.y = offset_y
    c2.flags = 0x004  # ARGS_ARE_XY_VALUES

    g.components = [c1, c2]
    return g


def patch_font_file(src_path: Path, dst_path: Path, offsets: dict) -> None:
    """Patches a single font file with the Turkish composite glyphs."""
    print(f"\n--- Patching: {src_path.name} ---")
    font = TTFont(str(src_path))
    glyf = font['glyf']
    hmtx = font['hmtx']

    # 1. Define composite glyphs
    new_glyphs = {
        'scedilla': create_composite_glyph('s', 'uni0327', offsets['s'][0], offsets['s'][1]),
        'Scedilla': create_composite_glyph('S', 'uni0327', offsets['S'][0], offsets['S'][1]),
        'gbreve': create_composite_glyph('g', 'uni0306', offsets['g'][0], offsets['g'][1]),
        'Gbreve': create_composite_glyph('G', 'uni0306', offsets['G'][0], offsets['G'][1]),
        'Idotaccent': create_composite_glyph('I', 'uni0307', offsets['I'][0], offsets['I'][1]),
    }

    # 2. Add glyphs and update glyph order & metrics
    glyph_order = list(font.getGlyphOrder())
    for glyph_name, composite_glyph in new_glyphs.items():
        base_char = glyph_name[0]
        glyf[glyph_name] = composite_glyph
        hmtx.metrics[glyph_name] = hmtx.metrics[base_char]
        if glyph_name not in glyph_order:
            glyph_order.append(glyph_name)

    font.setGlyphOrder(glyph_order)

    # 3. Update all Unicode cmap subtables
    for table in font['cmap'].tables:
        if table.isUnicode():
            for codepoint, glyph_name in CMAP_MAPPINGS.items():
                table.cmap[codepoint] = glyph_name

    # 4. Update name table with modification note
    for record in font['name'].names:
        if record.nameID == 5:  # Version string
            val = record.toUnicode()
            if ';KelimeVS-tr' not in val:
                record.string = f"{val};KelimeVS-tr-v1.0"
        elif record.nameID == 10:  # Description
            record.string = "Modified version by KelimeVS: added precomposed Turkish glyphs (Ş ş Ğ ğ İ) under SIL OFL 1.1."

    # 5. Ensure deterministic, reproducible builds
    font.recalcTimestamp = False
    font['head'].modified = 3876025408  # Fixed build timestamp (2026-10-28)

    # 6. Save patched font
    dst_path.parent.mkdir(parents=True, exist_ok=True)
    font.save(str(dst_path))
    print(f"Saved: {dst_path} ({dst_path.stat().st_size:,} bytes)")

    # 7. Verify integrity of generated font
    verify_patched_font(dst_path)


def verify_patched_font(font_path: Path) -> None:
    """Thoroughly checks the generated font file for integrity and correctness."""
    print(f"Verifying {font_path.name}...")
    font = TTFont(str(font_path))

    num_glyphs = font['maxp'].numGlyphs
    order_len = len(font.getGlyphOrder())
    glyf_len = len(font['glyf'].glyphs)
    hmtx_len = len(font['hmtx'].metrics)

    assert num_glyphs == order_len == glyf_len == hmtx_len, (
        f"Glyph count mismatch in {font_path.name}: maxp={num_glyphs}, order={order_len}, "
        f"glyf={glyf_len}, hmtx={hmtx_len}"
    )

    cmap = font.getBestCmap()
    for cp, expected_name in CMAP_MAPPINGS.items():
        assert cp in cmap, f"Codepoint U+{cp:04X} missing in cmap of {font_path.name}"
        actual_name = cmap[cp]
        assert actual_name == expected_name, (
            f"Codepoint U+{cp:04X} mapped to {actual_name}, expected {expected_name}"
        )
        assert actual_name in font['glyf'], f"Glyph {actual_name} missing in glyf table"
        assert actual_name in font['hmtx'].metrics, f"Glyph {actual_name} missing in hmtx table"

    # Verify that font compiles roundtrip cleanly
    import io
    buf = io.BytesIO()
    font.save(buf)
    assert buf.tell() > 0, "Compilation produced empty stream"

    print(f"  [OK] All {len(CMAP_MAPPINGS)} Turkish glyphs present and verified!")
    print(f"  [OK] Table consistency (maxp, glyf, hmtx, cmap) verified!")


def main():
    # Locate font directories
    script_dir = Path(__file__).resolve().parent
    # Check if run from app/tool or root tool
    if (script_dir.parent / 'assets' / 'fonts').exists():
        fonts_dir = script_dir.parent / 'assets' / 'fonts'
    elif (script_dir.parent / 'app' / 'assets' / 'fonts').exists():
        fonts_dir = script_dir.parent / 'app' / 'assets' / 'fonts'
    else:
        # Fallback search
        candidate = Path('d:/RS/App/KelimeGov2/Source/kelimego/app/assets/fonts')
        if candidate.exists():
            fonts_dir = candidate
        else:
            raise FileNotFoundError("Could not find assets/fonts directory.")

    orig_dir = fonts_dir / 'original'
    if not orig_dir.exists():
        orig_dir.mkdir(parents=True, exist_ok=True)
        # Copy initial originals if not already preserved
        import shutil
        for name in ['Fredoka-Bold.ttf', 'Fredoka-SemiBold.ttf']:
            if (fonts_dir / name).exists() and not (orig_dir / name).exists():
                shutil.copy2(fonts_dir / name, orig_dir / name)
                print(f"Backed up original {name} to {orig_dir}")

    bold_src = orig_dir / 'Fredoka-Bold.ttf'
    semi_src = orig_dir / 'Fredoka-SemiBold.ttf'

    bold_dst = fonts_dir / 'Fredoka-Bold.ttf'
    semi_dst = fonts_dir / 'Fredoka-SemiBold.ttf'

    assert bold_src.exists(), f"Source file {bold_src} not found!"
    assert semi_src.exists(), f"Source file {semi_src} not found!"

    patch_font_file(bold_src, bold_dst, OFFSETS_BOLD)
    patch_font_file(semi_src, semi_dst, OFFSETS_SEMIBOLD)

    print("\nSUCCESS: All Fredoka fonts successfully patched and verified!")


if __name__ == '__main__':
    main()

