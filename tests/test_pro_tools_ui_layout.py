"""
tests/test_pro_tools_ui_layout.py - Regression and Verification Tests for Pro Tools Suite Glove UI
Validates CSS containment, grid rules, overflow protection, responsive chips, DOM structure,
and JS event bindings for glove batch custom scope and Mode B target lists.
"""

from pathlib import Path
import re
import unittest


class TestProToolsUiLayout(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = Path(__file__).resolve().parent.parent
        cls.css_path = cls.root / "scripts" / "cs16_studio" / "web" / "static" / "style.css"
        cls.html_path = cls.root / "scripts" / "cs16_studio" / "web" / "static" / "index.html"
        cls.js_path = cls.root / "scripts" / "cs16_studio" / "web" / "static" / "js" / "modules" / "pro_tools.js"

        cls.assertTrue(cls.css_path.is_file(), f"Missing style.css at {cls.css_path}")
        cls.assertTrue(cls.html_path.is_file(), f"Missing index.html at {cls.html_path}")
        cls.assertTrue(cls.js_path.is_file(), f"Missing pro_tools.js at {cls.js_path}")

        cls.css_content = cls.css_path.read_text(encoding="utf-8")
        cls.html_content = cls.html_path.read_text(encoding="utf-8")
        cls.js_content = cls.js_path.read_text(encoding="utf-8")

    def test_css_weapons_checklist_containment_and_grid(self):
        """Validates that .weapons-checklist has strict overflow containment, max-height, and responsive grid."""
        # Find .weapons-checklist rule
        match = re.search(r"\.weapons-checklist\s*\{([^}]+)\}", self.css_content)
        self.assertIsNotNone(match, ".weapons-checklist CSS rule must exist in style.css")
        rule_body = match.group(1)

        # Check required properties
        self.assertIn("max-height: 150px", rule_body, "Must contain max-height: 150px")
        self.assertIn("overflow-y: auto", rule_body, "Must have vertical scrolling (overflow-y: auto)")
        self.assertIn("overflow-x: hidden", rule_body, "Must clip horizontal overflow (overflow-x: hidden)")
        self.assertIn("display: grid", rule_body, "Must use CSS grid for responsive chips")
        self.assertIn("repeat(auto-fill, minmax(130px, 1fr))", rule_body, "Must auto-fill columns minmax 130px")
        self.assertIn("gap: 6px", rule_body, "Must have 6px gap between chips")
        self.assertIn("background: #050813", rule_body, "Must have #050813 container background")

        # Custom scrollbar rules
        self.assertIn(".weapons-checklist::-webkit-scrollbar", self.css_content)
        self.assertIn(".weapons-checklist::-webkit-scrollbar-thumb", self.css_content)

    def test_css_weapon_check_card_styling_and_states(self):
        """Validates .weapon-check-card chip layout, hover, and checked active states."""
        match = re.search(r"\.weapon-check-card\s*\{([^}]+)\}", self.css_content)
        self.assertIsNotNone(match, ".weapon-check-card CSS rule must exist in style.css")
        card_body = match.group(1)

        self.assertIn("display: flex", card_body)
        self.assertIn("align-items: center", card_body)
        self.assertIn("gap: 6px", card_body)
        self.assertIn("font-family: monospace", card_body)
        self.assertIn("cursor: pointer", card_body)
        self.assertIn("min-width: 0", card_body, "Must have min-width: 0 to allow flex text-truncation")

        # Hover state
        self.assertIn(".weapon-check-card:hover", self.css_content)

        # Checked state (:has and .is-checked fallback)
        self.assertIn(".weapon-check-card:has(input:checked)", self.css_content)
        self.assertIn(".weapon-check-card.is-checked", self.css_content)

        # Label/span text truncation
        self.assertIn("text-overflow: ellipsis", self.css_content)
        self.assertIn("white-space: nowrap", self.css_content)

        # Button secondary active state
        self.assertIn(".btn-secondary.active", self.css_content)

    def test_index_html_structure_and_no_inline_unconstrained_styles(self):
        """Validates that index.html uses proper classes and no overflowing inline styles."""
        # Custom scope section
        self.assertIn('id="gloveCustomScopeSection"', self.html_content)
        self.assertIn('class="glove-custom-scope-section hidden"', self.html_content)

        # Batch weapons checklist
        self.assertIn('id="gloveBatchWeaponsList"', self.html_content)
        self.assertIn('class="weapons-checklist" id="gloveBatchWeaponsList"', self.html_content)

        # Mode B weapons checklist
        self.assertIn('id="gloveWeaponsList"', self.html_content)
        self.assertIn('class="weapons-checklist" id="gloveWeaponsList"', self.html_content)

        # Ensure no unconstrained inline styles on either checklist
        batch_line = [l for l in self.html_content.splitlines() if 'id="gloveBatchWeaponsList"' in l][0]
        self.assertNotIn("max-height:", batch_line, "gloveBatchWeaponsList must not have inline max-height")

        mode_b_line = [l for l in self.html_content.splitlines() if 'id="gloveWeaponsList"' in l][0]
        self.assertNotIn("max-height:", mode_b_line, "gloveWeaponsList must not have inline max-height")

    def test_pro_tools_js_dom_generation_and_event_handling(self):
        """Validates that pro_tools.js creates semantic label wrappers with proper event handlers."""
        # Mode A updateGloveBatchWeaponsList
        self.assertIn('document.createElement("label")', self.js_content)
        self.assertIn('chkBatch.className = "weapon-check-card"', self.js_content)
        self.assertIn("toLowerCase()", self.js_content, "Must normalize weapon names for deduplication")

        # Mode B openProToolsModal target checklist
        self.assertIn('chkWrap.className = "weapon-check-card"', self.js_content)

        # Accordion toggle with active class
        self.assertIn('gloveToggleCustomScopeBtn.classList.toggle("active"', self.js_content)

        # 0-selection validation when custom scope is open
        self.assertIn('Please select at least one weapon from the scope list', self.js_content)

    def test_nextgen_ui_drawer_categorization_and_heavy_section(self):
        """Validates that Left Drawer contains dedicated Heavy weapons category in HTML and app.js."""
        app_js_path = self.root / "scripts" / "cs16_studio" / "web" / "static" / "js" / "app.js"
        app_js_content = app_js_path.read_text(encoding="utf-8")

        # HTML must contain heavy category section and catGridHeavy
        self.assertIn('data-category="heavy"', self.html_content)
        self.assertIn('id="catGridHeavy"', self.html_content)
        self.assertIn('href="#glyph-heavy"', self.html_content)

        # app.js must define heavy in WEAPON_CATEGORIES and populateVisualLoadoutDrawer
        self.assertIn('heavy:', app_js_content)
        self.assertIn('m3', app_js_content)
        self.assertIn('xm1014', app_js_content)
        self.assertIn('m249', app_js_content)
        self.assertIn('catGridHeavy', app_js_content)

    def test_nextgen_ui_floating_hud_4k_snapshot(self):
        """Validates that Floating HUD capsule features 4K Snapshot with 3840x2160 UHD defaults."""
        v3d_path = self.root / "scripts" / "cs16_studio" / "web" / "static" / "js" / "modules" / "viewer3d.js"
        v3d_content = v3d_path.read_text(encoding="utf-8")

        self.assertIn('id="v3dSnapshotBtn"', self.html_content)
        self.assertIn('4K Snapshot', self.html_content)
        self.assertIn('width = 3840', v3d_content)
        self.assertIn('height = 2160', v3d_content)

    def test_nextgen_ui_zero_emojis_cleanliness(self):
        """Validates that absolutely zero Unicode emojis exist in static HTML, JS, or CSS."""
        static_dir = self.root / "scripts" / "cs16_studio" / "web" / "static"
        emoji_pattern = re.compile(
            r'[\U00010000-\U0010ffff]|[\u2600-\u27bf]|[\u2300-\u23ff]|[\u2b50-\u2b55]|\ud83c[\udf00-\udfff]|\ud83d[\ud000-\udfff]|\ud83e[\udd00-\udfff]'
        )
        violations = []
        for p in static_dir.rglob("*"):
            if p.suffix in (".html", ".js", ".css"):
                content = p.read_text(encoding="utf-8", errors="ignore")
                matches = emoji_pattern.findall(content)
                if matches:
                    violations.append(f"{p.name}: {matches}")

        self.assertEqual(violations, [], f"Found forbidden emojis in static assets: {violations}")

    def test_nextgen_ui_stage2d_subarea_toggle(self):
        """Validates that 2D stage properly toggles between bake canvas and color comparison stages."""
        color_path = self.root / "scripts" / "cs16_studio" / "web" / "static" / "js" / "modules" / "color_studio.js"
        bake_path = self.root / "scripts" / "cs16_studio" / "web" / "static" / "js" / "modules" / "bake.js"
        color_content = color_path.read_text(encoding="utf-8")
        bake_content = bake_path.read_text(encoding="utf-8")

        self.assertIn('stage2dBakeArea', color_content)
        self.assertIn('stage2dBakeArea', bake_content)
        self.assertIn('curtainCompareStage', color_content)
        self.assertIn('curtainCompareStage', bake_content)

    def test_topbar_single_row_no_wrap_and_clean_header(self):
        """Validates strict single-row topbar layout, removal of app-header & openProToolsBtn, and clickable pill."""
        # Check .studio-topbar CSS rule
        match = re.search(r"\.studio-topbar\s*\{([^}]+)\}", self.css_content)
        self.assertIsNotNone(match, ".studio-topbar CSS rule must exist")
        topbar_body = match.group(1)
        self.assertIn("height: 50px", topbar_body)
        self.assertIn("flex-wrap: nowrap", topbar_body)
        self.assertIn("overflow: hidden", topbar_body)
        self.assertIn("white-space: nowrap", topbar_body)

        # Check .header-controls
        match_ctrl = re.search(r"\.header-controls\s*\{([^}]+)\}", self.css_content)
        self.assertIsNotNone(match_ctrl, ".header-controls CSS rule must exist")
        ctrl_body = match_ctrl.group(1)
        self.assertIn("flex-wrap: nowrap", ctrl_body)
        self.assertIn("gap: 8px", ctrl_body)

        # index.html header tag must not have app-header class
        self.assertIn('<header class="studio-topbar">', self.html_content)
        self.assertNotIn('<header class="studio-topbar app-header">', self.html_content)

        # Redundant openProToolsBtn removed from topbar
        self.assertNotIn('id="openProToolsBtn"', self.html_content)

        # modelActivePill is interactive
        self.assertIn('id="modelActivePill"', self.html_content)
        self.assertIn('role="button"', self.html_content)
        self.assertIn('tabindex="0"', self.html_content)
        self.assertIn(".model-active-pill:hover", self.css_content)
        self.assertIn("cursor: pointer", self.css_content)

        # Header action buttons have responsive label compacting classes
        self.assertIn("header-action-btn", self.html_content)
        self.assertIn("btn-label", self.html_content)
        self.assertIn(".header-action-btn", self.css_content)
        self.assertIn("@media (max-width: 1280px)", self.css_content)
        self.assertIn(".header-action-btn .btn-label", self.css_content)

    def test_inspector_dock_isolation_and_proportions(self):
        """Validates 360px inspector dock, 42px dock header, and responsive breakpoint rules."""
        match_dock = re.search(r"\.studio-inspector-dock\s*\{([^}]+)\}", self.css_content)
        self.assertIsNotNone(match_dock, ".studio-inspector-dock rule must exist")
        dock_body = match_dock.group(1)
        self.assertIn("width: 360px", dock_body)
        self.assertIn("max-width: 360px", dock_body)

        match_hdr = re.search(r"\.studio-dock-header\s*\{([^}]+)\}", self.css_content)
        self.assertIsNotNone(match_hdr, ".studio-dock-header rule must exist")
        hdr_body = match_hdr.group(1)
        self.assertIn("height: 42px", hdr_body)
        self.assertIn("display: flex", hdr_body)

        # Responsive dock adjustment on screens <= 1366px and <= 1200px
        self.assertIn("@media (max-width: 1366px)", self.css_content)
        self.assertIn("width: 340px", self.css_content)
        self.assertIn("@media (max-width: 1200px)", self.css_content)
        self.assertIn("width: 320px", self.css_content)
        self.assertIn(".dock-tab", self.css_content)

    def test_contextual_stage_footer_and_responsive_drawer(self):
        """Validates 3D/2D contextual footer hint groups and JS auto-collapsing drawer on screens <= 1366px."""
        app_js_path = self.root / "scripts" / "cs16_studio" / "web" / "static" / "js" / "app.js"
        app_js_content = app_js_path.read_text(encoding="utf-8")

        # HTML has both hint containers
        self.assertIn('id="stageFooter3dHints"', self.html_content)
        self.assertIn('id="stageFooter2dHints"', self.html_content)

        # app.js dynamically toggles footer hints in setStageMode
        self.assertIn('stageFooter3dHints', app_js_content)
        self.assertIn('stageFooter2dHints', app_js_content)

        # Footer sync notice responsively hidden on <= 1366px to protect split view
        self.assertIn(".footer-sync-notice", self.css_content)

        # app.js auto-collapses drawer on screens <= 1366px
        self.assertIn('window.innerWidth <= 1366', app_js_content)
        self.assertIn('drawer.classList.add("collapsed")', app_js_content)

        # app.js binds click on modelActivePill to open Command Palette
        self.assertIn('modelActivePill.addEventListener("click"', app_js_content)

    def test_chrome_studio_ui_layout_and_elements(self):
        """Validates Chrome Studio UI structure, 5 unified dock tabs, pill switcher, and zero-emoji compliance."""
        chrome_js_path = self.root / "scripts" / "cs16_studio" / "web" / "static" / "js" / "modules" / "chrome_studio.js"
        self.assertTrue(chrome_js_path.is_file(), f"Missing chrome_studio.js at {chrome_js_path}")
        chrome_js_content = chrome_js_path.read_text(encoding="utf-8")

        # 1. Unified 5 Dock Tabs in Header
        self.assertIn('id="dockTabSlots"', self.html_content)
        self.assertIn('id="dockTabBake"', self.html_content)
        self.assertIn('id="dockTabColor"', self.html_content)
        self.assertIn('id="dockTabFinishes"', self.html_content)
        self.assertIn('id="dockTabGloves"', self.html_content)
        self.assertIn('data-tab="finishes"', self.html_content)
        self.assertIn('href="#glyph-sparkle"', self.html_content)

        # 2. Unified Finishes & FX Dock Pane with 3 Sub-panes
        self.assertIn('id="tabFinishes"', self.html_content)
        self.assertIn('id="finishesPillSwitcher"', self.html_content)
        self.assertIn('data-subpane="chrome"', self.html_content)
        self.assertIn('data-subpane="wear"', self.html_content)
        self.assertIn('data-subpane="stattrak"', self.html_content)

        self.assertIn('id="subpaneChrome"', self.html_content)
        self.assertIn('id="subpaneWear"', self.html_content)
        self.assertIn('id="subpaneStatTrak"', self.html_content)

        # 3. Chrome Orb and Preset Chips
        self.assertIn('id="chromeOrbCanvas"', self.html_content)
        self.assertIn('id="chromeActivePresetLabel"', self.html_content)
        for preset in ["silver", "gunmetal", "mirror", "24k gold", "sapphire", "ruby", "emerald", "blue gem"]:
            self.assertIn(f'data-preset="{preset}"', self.html_content)

        # 4. Parametric Sliders
        self.assertIn('id="chromeIntensitySlider"', self.html_content)
        self.assertIn('id="chromeTightnessSlider"', self.html_content)
        self.assertIn('id="chromeTintSlider"', self.html_content)

        # 5. Component Checklist and Action Dock
        self.assertIn('id="chromeComponentsList"', self.html_content)
        self.assertIn('id="chromeSelectAllPartsBtn"', self.html_content)
        self.assertIn('id="chromeClearPartsBtn"', self.html_content)
        self.assertIn('id="chromeInjectBtn"', self.html_content)
        self.assertIn('id="chromeRemoveBtn"', self.html_content)
        self.assertIn('id="chromeSyncPwCheck"', self.html_content)

        # 6. Engine Safety Budget Gauge
        self.assertIn('id="chromeBudgetCard"', self.html_content)
        self.assertIn('id="chromeBodypartCountLabel"', self.html_content)
        self.assertIn('id="chromeBodypartBudgetFill"', self.html_content)
        self.assertIn('id="chromeBudgetStatusTag"', self.html_content)
        self.assertIn('id="chromeHealthLabel"', self.html_content)
        self.assertIn('id="chromeVertsBudgetLabel"', self.html_content)

        # 7. Fallback tabPro for JS compatibility
        self.assertIn('id="tabPro"', self.html_content)

        # 8. Chrome Studio JS module functions and exports
        self.assertIn('export function initChromeStudioModule', chrome_js_content)
        self.assertIn('refreshChromeStatus', chrome_js_content)
        self.assertIn('initOrbVisualizer', chrome_js_content)


if __name__ == "__main__":
    unittest.main()

