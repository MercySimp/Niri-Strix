from abc import ABC, abstractmethod
from pathlib import Path
from typing import Dict, Any


class ThemeParser(ABC):
    @property
    @abstractmethod
    def app_name(self) -> str:
        """Each parser declares its app prefix e.g. 'kitty'"""
        pass

    def source_key(self) -> str:
        return f"{self.app_name}__source"

    def store_source(self, file_path: Path, colors: Dict[str, str]):
        """Read and store the full original file content"""
        with open(file_path, "r") as f:
            colors[self.source_key()] = f.read()

    @abstractmethod
    def parse(self, file_path: Path) -> Dict[str, str]:
        pass

    @abstractmethod
    def generate(self, colors: Dict[str, str], metadata: Dict[str, Any]) -> str:
        pass

    @abstractmethod
    def apply(self, theme_file: Path, target_config: Path):
        pass
