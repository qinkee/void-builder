"""Monitoring and metrics API endpoints"""

from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel
from typing import Dict, Any, List, Optional
import logging
from datetime import datetime, timezone
import psutil
import os

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/monitor", tags=["monitoring"])

class SystemMetrics(BaseModel):
    """System metrics model"""
    cpu_percent: float
    memory_percent: float
    memory_used_mb: float
    memory_available_mb: float
    disk_usage_percent: float
    timestamp: str

class PodMetrics(BaseModel):
    """Pod metrics model"""
    pod_name: str
    namespace: str
    cpu_usage: Optional[str]
    memory_usage: Optional[str]
    status: str
    restart_count: int
    age: str

class ClusterMetrics(BaseModel):
    """Cluster-wide metrics model"""
    total_pods: int
    active_pods: int
    pending_pods: int
    failed_pods: int
    total_users: int
    timestamp: str

@router.get("/system", response_model=SystemMetrics)
async def get_system_metrics():
    """
    Get system-level metrics of the API server
    
    Returns:
        System metrics including CPU, memory, and disk usage
    """
    try:
        # Get CPU usage
        cpu_percent = psutil.cpu_percent(interval=1)
        
        # Get memory usage
        memory = psutil.virtual_memory()
        memory_percent = memory.percent
        memory_used_mb = memory.used / (1024 * 1024)
        memory_available_mb = memory.available / (1024 * 1024)
        
        # Get disk usage
        disk = psutil.disk_usage('/')
        disk_usage_percent = disk.percent
        
        return SystemMetrics(
            cpu_percent=cpu_percent,
            memory_percent=memory_percent,
            memory_used_mb=round(memory_used_mb, 2),
            memory_available_mb=round(memory_available_mb, 2),
            disk_usage_percent=disk_usage_percent,
            timestamp=datetime.now(timezone.utc).isoformat()
        )
    except Exception as e:
        logger.error(f"Failed to get system metrics: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/pods/{user_id}", response_model=PodMetrics)
async def get_pod_metrics(user_id: str, k8s_manager=None):
    """
    Get metrics for a specific user's pod
    
    Args:
        user_id: User identifier
        
    Returns:
        Pod metrics including resource usage and status
    """
    if not k8s_manager:
        raise HTTPException(status_code=503, detail="K8s manager not available")
    
    try:
        pod_name = f"vnc-{user_id}"
        pod = k8s_manager.get_pod(pod_name)
        
        if not pod:
            raise HTTPException(status_code=404, detail="Pod not found")
        
        # Calculate age
        if pod.metadata.creation_timestamp:
            age = datetime.now(timezone.utc) - pod.metadata.creation_timestamp.replace(tzinfo=timezone.utc)
            age_str = str(age).split('.')[0]  # Remove microseconds
        else:
            age_str = "Unknown"
        
        # Get restart count
        restart_count = 0
        if pod.status.container_statuses:
            for cs in pod.status.container_statuses:
                restart_count += cs.restart_count
        
        return PodMetrics(
            pod_name=pod.metadata.name,
            namespace=pod.metadata.namespace,
            cpu_usage="N/A",  # Would need metrics-server API
            memory_usage="N/A",  # Would need metrics-server API
            status=pod.status.phase,
            restart_count=restart_count,
            age=age_str
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to get pod metrics: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/cluster", response_model=ClusterMetrics)
async def get_cluster_metrics(k8s_manager=None):
    """
    Get cluster-wide metrics
    
    Returns:
        Cluster metrics including pod counts and user statistics
    """
    if not k8s_manager:
        raise HTTPException(status_code=503, detail="K8s manager not available")
    
    try:
        from app.config import settings
        
        # Get all VNC pods
        pods = k8s_manager.v1.list_namespaced_pod(
            namespace=settings.k8s_namespace_pods,
            label_selector="managed-by=vnc-manager"
        )
        
        total_pods = len(pods.items)
        active_pods = 0
        pending_pods = 0
        failed_pods = 0
        users = set()
        
        for pod in pods.items:
            # Count pod states
            if pod.status.phase == "Running":
                active_pods += 1
            elif pod.status.phase == "Pending":
                pending_pods += 1
            elif pod.status.phase in ["Failed", "Unknown"]:
                failed_pods += 1
            
            # Count unique users
            user_label = pod.metadata.labels.get("user")
            if user_label:
                users.add(user_label)
        
        return ClusterMetrics(
            total_pods=total_pods,
            active_pods=active_pods,
            pending_pods=pending_pods,
            failed_pods=failed_pods,
            total_users=len(users),
            timestamp=datetime.now(timezone.utc).isoformat()
        )
        
    except Exception as e:
        logger.error(f"Failed to get cluster metrics: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/stats")
async def get_statistics(redis_client=None):
    """
    Get usage statistics
    
    Returns:
        Various statistics about the system usage
    """
    stats = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "api_version": "1.0.0",
        "python_version": os.sys.version,
        "uptime_seconds": None,
        "total_api_calls": None,
        "cache_stats": {}
    }
    
    # Get Redis stats if available
    if redis_client:
        try:
            info = redis_client.info()
            stats["cache_stats"] = {
                "connected_clients": info.get("connected_clients", 0),
                "used_memory_human": info.get("used_memory_human", "N/A"),
                "total_connections_received": info.get("total_connections_received", 0),
                "total_commands_processed": info.get("total_commands_processed", 0)
            }
        except Exception as e:
            logger.error(f"Failed to get Redis stats: {e}")
    
    return stats