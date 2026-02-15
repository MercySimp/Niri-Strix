from abc import ABC, abstractmethod
from pathlib import Path
from typing import Dict, Any

class ThemeParser(ABC):

    @abstractmethod
    def parse(self, file_path: Path) -> Dict[str, str]:
        pass

    @abstractmethod
    def generate(self, colors: Dict[str, str], metadata: Dict[str, Any]) -> str:
        pass

    @abstractmethod
    def apply(self, theme_file: Path, target_config: Path):
        pass
