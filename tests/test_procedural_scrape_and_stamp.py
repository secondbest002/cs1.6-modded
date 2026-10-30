"""
tests/test_procedural_scrape_and_stamp.py - Unit & Integration Tests for:
1. Procedural Sticker Scraping Engine (sticker_scraper.py)
2. Scrape wear integration in baker.py and image_pipeline.py
3. REST API endpoints (/api/bake, /api/bake_preview, /api/slot_tune_preview, /api/slot_tune_apply) with scrape
4. 3D Stamp Mode & High-Res Snapshot Studio frontend structure
"""

import base64
import io
import json
from pathlib import Path
import shutil
import socket
import tempfile
import threading
import time
import unittest
import urllib.request
import numpy as np
from PIL import Image

from scripts.cs16_studio.sticker_scraper import (
    apply_sticker_scraping,
    generate_scrape_mask,
    get_scrape_condition_name,
    scrape_and_quantize,
)
from scripts.cs16_studio.baker import bake_sticker_onto_texture
from scripts.cs16_studio.image_pipeline import (
    GOLDSRC_MASK_COLOR,
    process_slot_sticker_with_transform,
)
from scripts.cs16_studio.mdl_core import resolve_model_path
from scripts.cs16_studio.web.server import create_server


def get_free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("", 0))
        return s.getsockname()[1]


class TestStickerScraperCore(unittest.TestCase):
    """Verifies procedural sticker scraping mathematics, erosion, and determinism."""

    def setUp(self):
        # Create a solid 64x64 sticker RGBA image with an opaque circle in the center
        self.sticker = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
        for y in range(12, 52):
            for x in range(12, 52):
                if (x - 32) ** 2 + (y - 32) ** 2 <= 20 ** 2:
                    self.sticker.putpixel((x, y), (220, 50, 40, 255))

    def test_scrape_condition_names(self):
        # Both float ratios and 0-100 percentages
        self.assertIn("Mint", get_scrape_condition_name(0.0))
        self.assertIn("Mint", get_scrape_condition_name(0))
        self.assertIn("Light", get_scrape_condition_name(0.20))
        self.assertIn("Light", get_scrape_condition_name(20))
        self.assertIn("Moderate", get_scrape_condition_name(0.45))
        self.assertIn("Moderate", get_scrape_condition_name(45))
        self.assertIn("Heavy", get_scrape_condition_name(0.70))
        self.assertIn("Heavy", get_scrape_condition_name(70))
        self.assertIn("Battle-Worn", get_scrape_condition_name(0.95))
        self.assertIn("Battle-Worn", get_scrape_condition_name(100))

    def test_mint_scrape_0_returns_untouched(self):
        mint_img = apply_sticker_scraping(self.sticker, scrape_percent=0.0)
        orig_arr = np.array(self.sticker)
        mint_arr = np.array(mint_img)
        self.assertTrue(np.array_equal(orig_arr, mint_arr))

    def test_battle_worn_scrape_100_heavily_scraped_with_scratches_and_faded_edges(self):
        # 100% = heavily scraped/worn with visible scratches and faded edges
        worn_img = apply_sticker_scraping(self.sticker, scrape_percent=1.0)
        worn_arr = np.array(worn_img)
        # Must retain non-zero alpha pixels for authentic visible scratch cuts and paper backing
        visible_count = int(np.sum(worn_arr[:, :, 3] > 16))
        self.assertGreater(visible_count, 0)
        # But heavily eroded compared to mint
        orig_count = int(np.sum(np.array(self.sticker)[:, :, 3] > 16))
        self.assertLess(visible_count, orig_count * 0.40)

        # Same for percentage 100
        worn_img_pct = apply_sticker_scraping(self.sticker, scrape_percent=100)
        worn_arr_pct = np.array(worn_img_pct)
        self.assertTrue(np.array_equal(worn_arr, worn_arr_pct))

    def test_progressive_alpha_reduction(self):
        # As scrape level increases, visible opaque pixels should strictly decrease
        visible_counts = []
        for level in [0.0, 0.25, 0.50, 0.75, 1.0]:
            img = apply_sticker_scraping(self.sticker, scrape_percent=level, seed=42)
            arr = np.array(img)
            opaque_count = int(np.sum(arr[:, :, 3] > 32))
            visible_counts.append(opaque_count)

        # Monotonically non-increasing
        for i in range(len(visible_counts) - 1):
            self.assertGreaterEqual(
                visible_counts[i],
                visible_counts[i + 1],
                f"Visible pixels at step {i} ({visible_counts[i]}) not >= step {i+1} ({visible_counts[i+1]})",
            )
        # 0.0 has significantly more pixels than 0.75
        self.assertGreater(visible_counts[0], visible_counts[3])
        # 1.0 has visible scratches and faded edge residue remaining (> 0)
        self.assertGreater(visible_counts[-1], 0)

    def test_determinism_with_seed(self):
        run1 = apply_sticker_scraping(self.sticker, scrape_percent=0.45, seed=999)
        run2 = apply_sticker_scraping(self.sticker, scrape_percent=0.45, seed=999)
        self.assertTrue(np.array_equal(np.array(run1), np.array(run2)))

        # Different seed should yield different abrasion pattern
        run3 = apply_sticker_scraping(self.sticker, scrape_percent=0.45, seed=123)
        self.assertFalse(np.array_equal(np.array(run1), np.array(run3)))

    def test_scrape_mask_bounds(self):
        mask = generate_scrape_mask(64, 64, scrape_ratio=0.5, seed=1337)
        self.assertEqual(mask.shape, (64, 64))
        self.assertTrue(np.all(mask >= 0.0))
        self.assertTrue(np.all(mask <= 1.0))

    def test_scrape_and_quantize_goldsrc_payload(self):
        payload, preview = scrape_and_quantize(
            self.sticker,
            scrape_percent=0.35,
            target_w=128,
            target_h=128,
            is_masked=True,
        )
        expected_size = 128 * 128 + 768
        self.assertEqual(len(payload), expected_size)
        self.assertEqual(preview.size, (128, 128))

        # Check that palette index 255 is pinned to GoldSrc transparency color {0, 0, 255}
        pal = payload[128 * 128 :]
        slot_255 = (pal[255 * 3], pal[255 * 3 + 1], pal[255 * 3 + 2])
        self.assertEqual(slot_255, GOLDSRC_MASK_COLOR)

    def test_fully_transparent_image_graceful_handling(self):
        empty = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
        scraped = apply_sticker_scraping(empty, scrape_percent=0.5)
        self.assertEqual(scraped.size, (32, 32))
        self.assertTrue(np.all(np.array(scraped)[:, :, 3] == 0))

    def test_none_and_edge_inputs(self):
        res = apply_sticker_scraping(self.sticker, scrape_percent=None)
        self.assertTrue(np.array_equal(np.array(self.sticker), np.array(res)))

        tiny = Image.new("RGBA", (1, 1), (255, 0, 0, 255))
        tiny_scraped = apply_sticker_scraping(tiny, scrape_percent=0.5)
        self.assertEqual(tiny_scraped.size, (1, 1))

        with self.assertRaises(ValueError):
            apply_sticker_scraping(None, scrape_percent=0.5)


class TestBakeAndTuneWithScrape(unittest.TestCase):
    """Verifies scrape integration in baker.py and image_pipeline.py."""

    def test_baker_with_scrape_param(self):
        base = Image.new("RGBA", (256, 256), (40, 40, 40, 255))
        sticker = Image.new("RGBA", (64, 64), (255, 0, 0, 255))

        # Bake without scrape (mint)
        payload_mint, comp_mint = bake_sticker_onto_texture(
            base,
            sticker,
            custom_coords=(128, 128),
            scale_multiplier=1.0,
            scrape=0.0,
        )

        # Bake with 50% scrape
        payload_scraped, comp_scraped = bake_sticker_onto_texture(
            base,
            sticker,
            custom_coords=(128, 128),
            scale_multiplier=1.0,
            scrape=0.50,
        )

        self.assertEqual(len(payload_mint), 256 * 256 + 768)
        self.assertEqual(len(payload_scraped), 256 * 256 + 768)

        mint_arr = np.array(comp_mint)
        scraped_arr = np.array(comp_scraped)

        # Scraped composite should differ from mint composite due to worn scratch cuts
        self.assertFalse(np.array_equal(mint_arr, scraped_arr))

    def test_slot_tune_with_scrape_param(self):
        sticker = Image.new("RGBA", (64, 64), (0, 200, 255, 255))

        payload_mint, prev_mint = process_slot_sticker_with_transform(
            sticker,
            target_w=128,
            target_h=128,
            scale=1.0,
            scrape=0.0,
        )

        payload_worn, prev_worn = process_slot_sticker_with_transform(
            sticker,
            target_w=128,
            target_h=128,
            scale=1.0,
            scrape=0.60,
        )

        self.assertEqual(len(payload_mint), 128 * 128 + 768)
        self.assertEqual(len(payload_worn), 128 * 128 + 768)
        self.assertFalse(np.array_equal(np.array(prev_mint), np.array(prev_worn)))


class TestScrapeAndStampApiIntegration(unittest.TestCase):
    """Verifies REST API endpoints support scrape parameter and 3D stamping workflow."""

    @classmethod
    def setUpClass(cls):
        cls.temp_dir = tempfile.mkdtemp()
        cls.custom_ct_dir = Path(cls.temp_dir) / "cstrike" / "models" / "custom_skins" / "ct"
        cls.custom_ct_dir.mkdir(parents=True, exist_ok=True)

        real_usp = resolve_model_path("usp", team="ct")
        cls.test_usp = cls.custom_ct_dir / "v_usp.mdl"
        shutil.copy2(real_usp, cls.test_usp)

        cls.port = get_free_port()
        cls.server = create_server(host="127.0.0.1", port=cls.port, workspace_root=Path(cls.temp_dir))
        cls.server_thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.server_thread.start()
        time.sleep(0.3)

    @classmethod
    def tearDownClass(cls):
        try:
            cls.server.shutdown()
            cls.server.server_close()
        except Exception:
            pass
        shutil.rmtree(cls.temp_dir, ignore_errors=True)

    def _api_post(self, path, payload):
        url = f"http://127.0.0.1:{self.port}{path}"
        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=5) as res:
            return json.loads(res.read().decode("utf-8"))

    def test_api_bake_with_scrape_and_custom_coords(self):
        sticker = Image.new("RGBA", (32, 32), (255, 100, 0, 255))
        buf = io.BytesIO()
        sticker.save(buf, format="PNG")
        b64 = "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode("ascii")

        # Call /api/bake simulating 3D stamp mode click with scrape
        res = self._api_post("/api/bake", {
            "team": "ct",
            "weapon": "usp",
            "texture_index": 3,
            "coords": [120, 140],
            "scale": 1.2,
            "rotation": 25.0,
            "scrape": 0.45,
            "image_base64": b64,
        })
        self.assertTrue(res["success"])
        self.assertIn("preview", res)
        self.assertTrue(res["preview"].startswith("data:image/png;base64,"))

    def test_api_bake_preview_with_scrape(self):
        sticker = Image.new("RGBA", (32, 32), (0, 255, 128, 255))
        buf = io.BytesIO()
        sticker.save(buf, format="PNG")
        b64 = "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode("ascii")

        res = self._api_post("/api/bake_preview", {
            "team": "ct",
            "weapon": "usp",
            "texture_index": 3,
            "coords": [80, 80],
            "scale": 1.0,
            "scrape": 0.30,
            "image_base64": b64,
        })
        self.assertTrue(res["success"])
        self.assertTrue(res["preview"].startswith("data:image/png;base64,"))

    def test_api_slot_tune_with_scrape(self):
        sticker = Image.new("RGBA", (48, 48), (200, 50, 220, 255))
        buf = io.BytesIO()
        sticker.save(buf, format="PNG")
        b64 = "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode("ascii")

        # Preview
        prev = self._api_post("/api/slot_tune_preview", {
            "team": "ct",
            "weapon": "usp",
            "texture_index": 6,
            "scale": 0.9,
            "scrape": 0.50,
            "image_base64": b64,
        })
        self.assertTrue(prev["success"])

        # Apply
        apply_res = self._api_post("/api/slot_tune_apply", {
            "team": "ct",
            "weapon": "usp",
            "texture_index": 6,
            "scale": 0.9,
            "scrape": 0.50,
            "image_base64": b64,
        })
        self.assertTrue(apply_res["success"])

    def test_api_bake_with_null_fields_does_not_crash(self):
        sticker = Image.new("RGBA", (32, 32), (10, 20, 30, 255))
        buf = io.BytesIO()
        sticker.save(buf, format="PNG")
        b64 = "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode("ascii")

        # Pass null/None for optional fields
        res = self._api_post("/api/bake", {
            "team": "ct",
            "weapon": "usp",
            "texture_index": 3,
            "coords": [100, 100],
            "scale": None,
            "rotation": None,
            "scrape": None,
            "image_base64": b64,
        })
        self.assertTrue(res["success"])

    def test_api_bake_with_fx_flags(self):
        sticker = Image.new("RGBA", (32, 32), (50, 150, 250, 255))
        buf = io.BytesIO()
        sticker.save(buf, format="PNG")
        b64 = "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode("ascii")

        # Test chrome fx
        res_chrome = self._api_post("/api/bake", {
            "team": "ct",
            "weapon": "usp",
            "texture_index": 3,
            "coords": [100, 100],
            "fx": "chrome",
            "image_base64": b64,
        })
        self.assertTrue(res_chrome["success"])

        from scripts.cs16_studio.mdl_core import MdlModel, STUDIO_NF_CHROME
        m = MdlModel(self.test_usp)
        t = m.get_texture_by_index(3)
        self.assertTrue(bool(t.flags & STUDIO_NF_CHROME))

        # Test matte fx clears chrome
        res_matte = self._api_post("/api/bake", {
            "team": "ct",
            "weapon": "usp",
            "texture_index": 3,
            "coords": [100, 100],
            "fx": "matte",
            "image_base64": b64,
        })
        self.assertTrue(res_matte["success"])
        m2 = MdlModel(self.test_usp)
        t2 = m2.get_texture_by_index(3)
        self.assertFalse(bool(t2.flags & STUDIO_NF_CHROME))


class TestFrontendElementsAndIntegrity(unittest.TestCase):
    """Verifies that all new HTML elements and CSS selectors exist."""

    def setUp(self):
        self.html_path = Path("scripts/cs16_studio/web/static/index.html")
        self.css_path = Path("scripts/cs16_studio/web/static/style.css")
        self.html_content = self.html_path.read_text(encoding="utf-8")
        self.css_content = self.css_path.read_text(encoding="utf-8")

    def test_reposition_and_health_elements_in_html(self):
        # 3D Stamp features removed as requested
        self.assertNotIn('id="v3dStampModeBtn"', self.html_content)
        self.assertNotIn('id="v3dStampOverlay"', self.html_content)
        # 3D Slot Repositioning & Model Health badge elements present
        self.assertIn('id="v3dSnapshotBtn"', self.html_content)
        self.assertIn('id="v3dRepositionBanner"', self.html_content)
        self.assertIn('id="v3dRepositionSlotName"', self.html_content)
        self.assertIn('id="v3dRepositionCancelBtn"', self.html_content)
        self.assertIn('id="modelHealthBadge"', self.html_content)

    def test_scrape_sliders_in_bake_and_slot_tune_html(self):
        self.assertIn('id="bakeScrape"', self.html_content)
        self.assertIn('id="bakeScrapeVal"', self.html_content)
        self.assertIn('id="slotTuneScrape"', self.html_content)
        self.assertIn('id="slotTuneScrapeVal"', self.html_content)

    def test_css_classes_exist(self):
        self.assertNotIn(".v3d-stamp-overlay", self.css_content)
        self.assertIn(".v3d-reposition-banner", self.css_content)
        self.assertIn(".viewport3d-container.reposition-active", self.css_content)
        self.assertIn(".health-badge", self.css_content)
