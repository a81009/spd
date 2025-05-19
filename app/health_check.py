"""
Sistema de verificação de saúde para todos os componentes do sistema distribuído.
Este módulo fornece funções para verificar a saúde de todos os componentes
e retornar informações detalhadas sobre o estado do sistema.
"""
import asyncio
from typing import Dict, Any

from .storage import backend
from .cache import get_health as cache_health
from .mq import mq

async def check_storage() -> Dict[str, Any]:
    """Verifica a saúde do backend de armazenamento."""
    try:
        await backend.put("_health_probe", "_ok")
        value = await backend.get("_health_probe")
        await backend.delete("_health_probe")
        
        status = value == "_ok"
        return {
            "status": "healthy" if status else "unhealthy",
            "backend_type": backend.__class__.__name__,
            "details": {"read_write_test": status}
        }
    except Exception as e:
        return {
            "status": "unhealthy",
            "backend_type": backend.__class__.__name__,
            "details": {"error": str(e)}
        }

async def check_cache() -> Dict[str, Any]:
    """Verifica a saúde do sistema de cache (Redis)."""
    is_healthy = await cache_health()
    return {
        "status": "healthy" if is_healthy else "unhealthy",
        "details": {
            "connection": is_healthy
        }
    }

async def check_message_queue() -> Dict[str, Any]:
    """Verifica a saúde do sistema de mensageria (RabbitMQ)."""
    is_healthy = await mq.get_health()
    return {
        "status": "healthy" if is_healthy else "unhealthy",
        "details": {
            "connection": is_healthy
        }
    }

async def full_health_check() -> Dict[str, Any]:
    """
    Realiza uma verificação completa de saúde em todos os componentes do sistema.
    Retorna um relatório detalhado sobre o estado de cada componente.
    """
    storage_health, cache_health_result, mq_health = await asyncio.gather(
        check_storage(),
        check_cache(),
        check_message_queue()
    )
    
    # Determina o status geral do sistema
    components_healthy = (
        storage_health["status"] == "healthy" and
        cache_health_result["status"] == "healthy" and
        mq_health["status"] == "healthy"
    )
    
    return {
        "status": "healthy" if components_healthy else "degraded",
        "components": {
            "storage": storage_health,
            "cache": cache_health_result,
            "message_queue": mq_health
        },
        "timestamp": asyncio.get_event_loop().time()
    }

async def quick_health_check() -> bool:
    """Verificação rápida para liveness probes em Kubernetes ou similar."""
    try:
        # Simplesmente verifica se conseguimos acessar o storage
        await backend.get("_health_probe")
        return True
    except Exception:
        return False 