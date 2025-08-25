from pydantic_settings import BaseSettings
from typing import Optional
import os

class Settings(BaseSettings):
    # Application Settings
    app_name: str = "VNC Pod Manager"
    app_version: str = "1.0.0"
    debug: bool = False
    
    # API Settings
    api_prefix: str = "/api/v1"
    api_host: str = "0.0.0.0"
    api_port: int = 8000
    
    # Kubernetes Settings
    k8s_in_cluster: bool = True
    k8s_namespace_system: str = "vnc-system"
    k8s_namespace_pods: str = "vnc-pods"
    k8s_image_registry: str = "192.168.10.252:31832"
    k8s_vnc_image: str = "vnc/void-desktop:latest"
    
    # Redis Settings
    redis_host: str = "redis-service"
    redis_port: int = 6379
    redis_db: int = 0
    redis_password: Optional[str] = None
    redis_lock_timeout: int = 10
    
    # MySQL Settings (for user authentication)
    mysql_host: str = "192.168.10.254"
    mysql_port: int = 3306
    mysql_database: str = "im_platform"
    mysql_user: str = "root"
    mysql_password: str = "zddixczHMBbJPneN.32$#"
    
    # PostgreSQL Settings (for future use)
    db_host: str = "postgres-service"
    db_port: int = 5432
    db_name: str = "vnc_manager"
    db_user: str = "vnc_admin"
    db_password: str = "vnc_password"
    
    # Security Settings
    secret_key: str = "your-secret-key-change-in-production"
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 1440  # 24 hours
    
    # Resource Limits
    default_cpu_request: str = "500m"
    default_cpu_limit: str = "2"
    default_memory_request: str = "1Gi"
    default_memory_limit: str = "4Gi"
    default_storage_size: str = "10Gi"
    
    # Network Settings
    vnc_port_range_start: int = 30000
    vnc_port_range_end: int = 31000
    ssh_port_range_start: int = 31001
    ssh_port_range_end: int = 32000
    vnc_domain: str = "vnc.service.thinkgs.cn"  # Domain for Ingress access
    
    # Monitoring
    enable_metrics: bool = True
    metrics_port: int = 9090
    
    class Config:
        env_file = ".env"
        case_sensitive = False

settings = Settings()