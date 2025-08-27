"""Pod lifecycle management with business logic"""

import logging
from typing import Optional, Dict, Any, List
from datetime import datetime, timezone
import json

from app.core.k8s_client import K8sManager
from app.core.k8s_ingress import K8sIngressManager
from app.core.redis_lock import RedisLock
from app.config import settings

logger = logging.getLogger(__name__)

class PodManager:
    """High-level Pod management with business logic"""
    
    def __init__(self, k8s_manager: K8sManager, ingress_manager: K8sIngressManager, redis_client):
        self.k8s = k8s_manager
        self.ingress = ingress_manager
        self.redis = redis_client
        
    def create_user_environment(self, user_id: str, token: str, api_token: str = None, resource_quota: Optional[Dict] = None) -> Dict[str, Any]:
        """
        Create complete user environment including Pod, Service, Ingress, and PVC
        
        Args:
            user_id: User identifier
            token: User token
            resource_quota: Optional resource limits
            
        Returns:
            Environment details dictionary
        """
        try:
            # Check if environment already exists
            existing_env = self.get_user_environment(user_id)
            if existing_env and existing_env.get("status") == "Running":
                logger.info(f"Environment already exists for user {user_id}")
                return existing_env
            
            # Use distributed lock
            with RedisLock(self.redis, f"create_env_{user_id}", timeout=30).acquire_context():
                # Double-check after acquiring lock
                existing_env = self.get_user_environment(user_id)
                if existing_env and existing_env.get("status") == "Running":
                    return existing_env
                
                # Create PVC
                pvc = self.k8s.create_pvc(
                    user_id=user_id,
                    size=resource_quota.get("storage", settings.default_storage_size) if resource_quota else settings.default_storage_size
                )
                
                # Create Pod
                pod = self.k8s.create_vnc_pod(
                    user_id=user_id,
                    token=token,
                    api_token=api_token,
                    resource_quota=resource_quota
                )
                
                # Create Service
                service = self.ingress.create_pod_service(user_id)
                
                # Create Ingress
                ingress = self.ingress.create_pod_ingress(
                    user_id=user_id,
                    domain=settings.vnc_domain
                )
                
                # Get access information
                access_info = self.ingress.get_pod_access_info(user_id, settings.vnc_domain)
                
                # Store environment info in Redis
                env_info = {
                    "user_id": user_id,
                    "pod_name": pod.metadata.name,
                    "service_name": service.metadata.name,
                    "ingress_name": ingress.metadata.name,
                    "pvc_name": pvc.metadata.name,
                    "created_at": datetime.now(timezone.utc).isoformat(),
                    "status": "Running",
                    "access_info": access_info
                }
                
                self.redis.setex(
                    f"environment:{user_id}",
                    86400,  # Cache for 24 hours
                    json.dumps(env_info)
                )
                
                logger.info(f"Successfully created environment for user {user_id}")
                return env_info
                
        except Exception as e:
            logger.error(f"Failed to create environment for user {user_id}: {e}")
            raise
    
    def delete_user_environment(self, user_id: str, keep_data: bool = True) -> bool:
        """
        Delete user environment
        
        Args:
            user_id: User identifier
            keep_data: Whether to keep PVC data
            
        Returns:
            True if deleted successfully
        """
        try:
            with RedisLock(self.redis, f"delete_env_{user_id}", timeout=30).acquire_context():
                # Delete Ingress
                self.ingress.delete_pod_ingress(user_id)
                
                # Delete Service
                self.k8s.delete_service(f"vnc-service-{user_id}")
                
                # Delete Pod
                self.k8s.delete_pod(f"vnc-{user_id}")
                
                # Optionally delete PVC
                if not keep_data:
                    self.k8s.delete_pvc(f"pvc-{user_id}")
                
                # Clear cache
                self.redis.delete(f"environment:{user_id}")
                
                logger.info(f"Successfully deleted environment for user {user_id}")
                return True
                
        except Exception as e:
            logger.error(f"Failed to delete environment for user {user_id}: {e}")
            raise
    
    def get_user_environment(self, user_id: str) -> Optional[Dict[str, Any]]:
        """
        Get user environment details
        
        Args:
            user_id: User identifier
            
        Returns:
            Environment details or None
        """
        # Check cache first
        cached = self.redis.get(f"environment:{user_id}")
        if cached:
            return json.loads(cached)
        
        # Check actual resources
        pod = self.k8s.get_pod(f"vnc-{user_id}")
        if not pod:
            return None
        
        # Rebuild environment info
        env_info = {
            "user_id": user_id,
            "pod_name": pod.metadata.name,
            "status": pod.status.phase,
            "created_at": pod.metadata.creation_timestamp.isoformat() if pod.metadata.creation_timestamp else None,
            "access_info": self.ingress.get_pod_access_info(user_id, settings.vnc_domain)
        }
        
        # Cache it
        self.redis.setex(
            f"environment:{user_id}",
            3600,  # Cache for 1 hour
            json.dumps(env_info)
        )
        
        return env_info
    
    def list_all_environments(self) -> List[Dict[str, Any]]:
        """
        List all user environments
        
        Returns:
            List of environment details
        """
        try:
            pods = self.k8s.v1.list_namespaced_pod(
                namespace=settings.k8s_namespace_pods,
                label_selector="managed-by=vnc-manager"
            )
            
            environments = []
            for pod in pods.items:
                user_id = pod.metadata.labels.get("user")
                if user_id:
                    env_info = {
                        "user_id": user_id,
                        "pod_name": pod.metadata.name,
                        "status": pod.status.phase,
                        "created_at": pod.metadata.creation_timestamp.isoformat() if pod.metadata.creation_timestamp else None,
                        "pod_ip": pod.status.pod_ip,
                        "host_ip": pod.status.host_ip
                    }
                    environments.append(env_info)
            
            return environments
            
        except Exception as e:
            logger.error(f"Failed to list environments: {e}")
            raise
    
    def cleanup_stale_environments(self, max_age_hours: int = 24) -> int:
        """
        Clean up stale environments older than specified hours
        
        Args:
            max_age_hours: Maximum age in hours
            
        Returns:
            Number of environments cleaned up
        """
        from datetime import timedelta
        
        try:
            current_time = datetime.now(timezone.utc)
            cleaned_count = 0
            
            environments = self.list_all_environments()
            for env in environments:
                if env.get("created_at"):
                    created_at = datetime.fromisoformat(env["created_at"].replace("+00:00", "+00:00"))
                    age = current_time - created_at
                    
                    if age > timedelta(hours=max_age_hours):
                        logger.info(f"Cleaning up stale environment for user {env['user_id']} (age: {age})")
                        self.delete_user_environment(env["user_id"], keep_data=True)
                        cleaned_count += 1
            
            logger.info(f"Cleaned up {cleaned_count} stale environments")
            return cleaned_count
            
        except Exception as e:
            logger.error(f"Failed to cleanup stale environments: {e}")
            raise
    
    def get_environment_metrics(self, user_id: str) -> Optional[Dict[str, Any]]:
        """
        Get resource metrics for user environment
        
        Args:
            user_id: User identifier
            
        Returns:
            Metrics dictionary or None
        """
        try:
            pod_name = f"vnc-{user_id}"
            
            # Get pod status
            pod_status = self.k8s.get_pod_status(pod_name)
            if not pod_status:
                return None
            
            # Get pod logs (last 50 lines)
            logs = self.k8s.get_pod_logs(pod_name, tail_lines=50)
            
            metrics = {
                "pod_name": pod_name,
                "status": pod_status,
                "recent_logs": logs,
                "timestamp": datetime.now(timezone.utc).isoformat()
            }
            
            return metrics
            
        except Exception as e:
            logger.error(f"Failed to get metrics for user {user_id}: {e}")
            return None