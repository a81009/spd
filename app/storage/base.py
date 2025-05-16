from abc import ABC, abstractmethod
from typing import Any, Optional

class KVBackend(ABC):
    @abstractmethod
    async def put(self, key: str, value: Any) -> None: ...
    @abstractmethod
    async def get(self, key: str) -> Optional[Any]: ...
    @abstractmethod
    async def delete(self, key: str) -> None: ...
