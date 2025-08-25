"""Health check API endpoints"""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Dict, Any
import logging
from datetime import datetime, timezone

logger = logging.getLogger(__name__)

router = APIRouter(tags=["health"])

class HealthResponse(BaseModel):
    """Health check response model"""
    status: str
    timestamp: str
    version: str = "1.0.0"
    
class ReadinessResponse(BaseModel):
    """Readiness check response model"""
    status: str
    checks: Dict[str, bool]
    timestamp: str

async def check_redis_health(redis_client) -> bool:
    """Check Redis connectivity"""
    try:
        redis_client.ping()
        return True
    except Exception as e:
        logger.error(f"Redis health check failed: {e}")
        return False

async def check_k8s_health(k8s_manager) -> bool:
    """Check Kubernetes API connectivity"""
    try:
        k8s_manager.v1.list_namespace(limit=1)
        return True
    except Exception as e:
        logger.error(f"K8s health check failed: {e}")
        return False

@router.get("/health", response_model=HealthResponse)
async def health_check():
    """
    Basic health check endpoint
    
    Returns:
        Health status
    """
    return HealthResponse(
        status="healthy",
        timestamp=datetime.now(timezone.utc).isoformat(),
        version="1.0.0"
    )

@router.get("/ready", response_model=ReadinessResponse)
async def readiness_check(redis_client=None, k8s_manager=None):
    """
    Readiness check endpoint
    
    Checks:
    - Redis connectivity
    - Kubernetes API access
    
    Returns:
        Readiness status with individual check results
    """
    checks = {
        "redis": await check_redis_health(redis_client) if redis_client else False,
        "kubernetes": await check_k8s_health(k8s_manager) if k8s_manager else False
    }
    
    all_ready = all(checks.values())
    
    if not all_ready:
        raise HTTPException(
            status_code=503,
            detail={
                "status": "not_ready",
                "checks": checks,
                "timestamp": datetime.now(timezone.utc).isoformat()
            }
        )
    
    return ReadinessResponse(
        status="ready",
        checks=checks,
        timestamp=datetime.now(timezone.utc).isoformat()
    )

@router.get("/liveness")
async def liveness_check():
    """
    Liveness check endpoint
    
    Simple check to ensure the service is responding
    
    Returns:
        Liveness status
    """
    return {
        "status": "alive",
        "timestamp": datetime.now(timezone.utc).isoformat()
    }