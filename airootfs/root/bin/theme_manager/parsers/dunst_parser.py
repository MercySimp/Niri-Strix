from pathlib import Path
from typing import Dict, Any
import re
from parsers.base import ThemeParser


class DunstParser(ThemeParser):
    @property
    def app_name(self):
        return "dunst"

    def parse(self, file_path: Path) -> Dict[str, str]:
        colors = {}
        self.store_source(file_path, colors)
        with open(file_path, "r") as f:
            current_section = None
            for line in f:
                line = line.strip()
                if line.startswith("[") and line.endswith("]"):
                    current_section = line[1:-1]
                    continue
                if current_section == "global":
                    match = re.match(r'frame_color\s*=\s*"([^"]+)"', line)
                    if match:
                        colors["dunst_frame_color"] = match.group(1)
                if current_section and "urgency" in current_section:
                    match = re.match(
                        r'(background|foreground|frame_color)\s*=\s*"([^"]+)"', line
                    )
                    if match:
                        colors[f"dunst_{current_section}_{match.group(1)}"] = (
                            match.group(2)
                        )
        return colors

    def generate(self, colors: Dict[str, str], metadata: Dict[str, Any]) -> str:
        if self.source_key() in colors:
            content = colors[self.source_key()]
            for key, value in colors.items():
                if key == "dunst_frame_color":
                    content = re.sub(
                        r'(frame_color\s*=\s*)"[^"]+"',
                        rf'\g<1>"{value}"',
                        content,
                        count=1,
                    )
                elif key.startswith("dunst_urgency_"):
                    # e.g. dunst_urgency_low_background
                    # ['dunst', 'urgency', 'low', 'background']
                    parts = key.split("_", 3)
                    if len(parts) == 4:
                        _, _, level, color_key = parts
                        # Replace only within the correct urgency section
                        content = re.sub(
                            rf'(\[urgency_{level}\].*?{
                                re.escape(color_key)
                            }\s*=\s*)"[^"]+"',
                            rf'\g<1>"{value}"',
                            content,
                            flags=re.DOTALL,
                            count=1,
                        )
            return content

        lines = [f"# Theme: {metadata.get('name', 'custom')}\n"]
        if "dunst_frame_color" in colors:
            lines += ["[global]", f'frame_color = "{colors["dunst_frame_color"]}"', ""]
        for urgency in ["low", "normal", "critical"]:
            section = {k: v for k, v in colors.items() if f"urgency_{urgency}" in k}
            if section:
                lines.append(f"[urgency_{urgency}]")
                for key, value in sorted(section.items()):
                    lines.append(f'{key.split("_")[-1]} = "{value}"')
                lines.append("")
        return "\n".join(lines)

    def apply(self, theme_file: Path, target_config: Path):
        import shutil
        import subprocess

        if not theme_file.exists() or theme_file.stat().st_size == 0:
            return
        if not target_config.exists():
            target_config.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(theme_file, target_config)

        # Reload dunst by killing and restarting it
        print("Testing")
        try:
            # Kill existing instance
            subprocess.run(["pkill", "dunst"], capture_output=True)
            print("Dunst reloaded")
            # Small delay to ensure it's fully stopped
            import time

            time.sleep(0.5)
            # Restart dunst in background
            subprocess.Popen(
                ["dunst"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
        except FileNotFoundError:
            print("dunst not found, skipping reload")
        except Exception as e:
            print(f"dunst restart failed: {e}")
