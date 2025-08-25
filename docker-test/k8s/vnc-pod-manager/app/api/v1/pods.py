"""Pod management API endpoints"""

from fastapi import APIRouter, HTTPException, Depends, Header, BackgroundTasks
from typing import Optional, Dict, Any, List
from pydantic import BaseModel, Field
import logging

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/pods", tags=["pods"])

class CreatePodRequest(BaseModel):
    """Request model for creating a pod"""
    resource_quota: Optional[Dict[str, str]] = Field(
        None,
        description="Optional resource quota override",
        example={
            "cpu_request": "500m",
            "cpu_limit": "2",
            "memory_request": "1Gi",
            "memory_limit": "4Gi",
            "storage": "10Gi"
        }
    )

class PodResponse(BaseModel):
    """Response model for pod operations"""
    status: str
    message: str
    pod_name: Optional[str] = None
    access_info: Optional[Dict[str, Any]] = None

class PodStatusResponse(BaseModel):
    """Response model for pod status"""
    name: str
    namespace: str
    phase: str
    conditions: List[Dict[str, Any]]
    container_statuses: List[Dict[str, Any]]
    pod_ip: Optional[str]
    host_ip: Optional[str]
    start_time: Optional[str]
    access_info: Optional[Dict[str, Any]]

class PodLogsResponse(BaseModel):
    """Response model for pod logs"""
    pod_name: str
    logs: str
    tail_lines: int

class RestartPodResponse(BaseModel):
    """Response model for pod restart"""
    status: str
    message: str
    old_pod_name: str
    new_pod_name: str

class ListPodsResponse(BaseModel):
    """Response model for listing pods"""
    user_id: str
    pods: List[Dict[str, Any]]
    count: int

# Note: Actual route implementations would be in main.py
# This file defines the data models and can include route-specific logic if needed