"""
Kubernetes TCP Proxy Manager for SSH access through Nginx Ingress
This manages TCP services configuration for Nginx Ingress Controller
"""

from kubernetes import client
from kubernetes.client.rest import ApiException
from typing import Optional, Dict, Any
import logging

logger = logging.getLogger(__name__)

class K8sTCPProxyManager:
    """Manage TCP proxy configuration for SSH access through Nginx Ingress"""
    
    # SSH port allocation range (22000-22399 for 400 users)
    SSH_PORT_START = 22000
    SSH_PORT_END = 22399
    
    def __init__(self, k8s_manager):
        self.k8s = k8s_manager
        self.v1 = client.CoreV1Api()
        self.apps_v1 = client.AppsV1Api()
        
    def _allocate_available_ssh_port(self, user_id: str) -> int:
        """
        Allocate an available SSH port from the allowed range
        Uses random selection from available ports
        """
        import random
        
        # Get all currently used ports
        used_ports = set()
        try:
            tcp_cm = self.v1.read_namespaced_config_map(
                name="tcp-services",
                namespace="ingress-nginx"
            )
            if tcp_cm.data:
                for port_str, service_mapping in tcp_cm.data.items():
                    # Only count SSH ports (those ending with :22)
                    if service_mapping.endswith(":22"):
                        try:
                            port = int(port_str)
                            if self.SSH_PORT_START <= port <= self.SSH_PORT_END:
                                used_ports.add(port)
                        except ValueError:
                            continue
        except Exception as e:
            logger.warning(f"Could not read existing port mappings: {e}")
        
        # Find available ports in our range
        available_ports = []
        for port in range(self.SSH_PORT_START, self.SSH_PORT_END + 1):
            if port not in used_ports:
                available_ports.append(port)
        
        if not available_ports:
            raise RuntimeError(f"No available SSH ports in range {self.SSH_PORT_START}-{self.SSH_PORT_END}")
        
        # Select a random available port
        selected_port = random.choice(available_ports)
        logger.info(f"Allocated SSH port {selected_port} for user {user_id} (from {len(available_ports)} available ports)")
        
        return selected_port
    
    def _get_existing_ssh_mapping(self, user_id: str) -> Optional[int]:
        """
        Check if SSH mapping already exists for a user
        
        Args:
            user_id: User identifier
            
        Returns:
            Existing SSH port or None if not found
        """
        service_name = f"vnc-service-{user_id}"
        configmap_name = "tcp-services"
        configmap_namespace = "ingress-nginx"
        
        try:
            tcp_cm = self.v1.read_namespaced_config_map(
                name=configmap_name,
                namespace=configmap_namespace
            )
            
            if tcp_cm.data:
                # Look for existing mapping for this service
                target_service = f"vnc-pods/{service_name}:22"
                for port_str, service_mapping in tcp_cm.data.items():
                    if service_mapping == target_service:
                        return int(port_str)
            
            return None
            
        except ApiException as e:
            if e.status == 404:
                return None
            logger.error(f"Failed to check existing SSH mappings: {e}")
            return None
    
    def _update_tcp_services_configmap(self, user_id: str, namespace: str = "vnc-pods") -> int:
        """
        Update the tcp-services ConfigMap to add SSH proxy mapping
        
        Args:
            user_id: User identifier
            namespace: Namespace where the service is located
            
        Returns:
            Allocated SSH port number
        """
        service_name = f"vnc-service-{user_id}"
        ssh_port = self._allocate_available_ssh_port(user_id)
        configmap_name = "tcp-services"
        configmap_namespace = "ingress-nginx"
        
        try:
            # Get existing ConfigMap
            try:
                tcp_cm = self.v1.read_namespaced_config_map(
                    name=configmap_name,
                    namespace=configmap_namespace
                )
            except ApiException as e:
                if e.status == 404:
                    # Create ConfigMap if it doesn't exist
                    tcp_cm = client.V1ConfigMap(
                        metadata=client.V1ObjectMeta(
                            name=configmap_name,
                            namespace=configmap_namespace
                        ),
                        data={}
                    )
                    tcp_cm = self.v1.create_namespaced_config_map(
                        namespace=configmap_namespace,
                        body=tcp_cm
                    )
                else:
                    raise
            
            # Initialize data if None
            if tcp_cm.data is None:
                tcp_cm.data = {}
            
            # Add SSH port mapping
            # Format: "external_port": "namespace/service:internal_port"
            tcp_cm.data[str(ssh_port)] = f"{namespace}/{service_name}:22"
            
            # Update ConfigMap
            self.v1.patch_namespaced_config_map(
                name=configmap_name,
                namespace=configmap_namespace,
                body=tcp_cm
            )
            
            logger.info(f"Added TCP proxy mapping for user {user_id}: port {ssh_port} -> {namespace}/{service_name}:22")
            
            # Patch the Ingress Controller service to expose the new port
            self._expose_tcp_port(ssh_port)
            
            return ssh_port
            
        except ApiException as e:
            logger.error(f"Failed to update TCP services ConfigMap: {e}")
            raise
    
    def _expose_tcp_port(self, port: int):
        """
        Expose the TCP port in the Nginx Ingress Controller Service
        """
        service_name = "ingress-nginx-controller-nginx-tcp"
        service_namespace = "ingress-nginx"
        
        try:
            # Get the ingress controller service
            service = self.v1.read_namespaced_service(
                name=service_name,
                namespace=service_namespace
            )
            
            # Check if port is already exposed
            port_exists = False
            for svc_port in service.spec.ports:
                if svc_port.port == port:
                    port_exists = True
                    break
            
            if not port_exists:
                # Calculate NodePort (30000-32767 range)
                # Use a simple mapping: SSH port 22xxx -> NodePort 32xxx
                node_port = 32000 + (port - self.SSH_PORT_START)
                
                # Add the new port
                new_port = client.V1ServicePort(
                    name=f"ssh-{port}",
                    port=port,
                    target_port=port,
                    node_port=node_port,
                    protocol="TCP"
                )
                
                # Patch the service to add the new port
                service.spec.ports.append(new_port)
                
                self.v1.patch_namespaced_service(
                    name=service_name,
                    namespace=service_namespace,
                    body=service
                )
                
                logger.info(f"Exposed TCP port {port} in Ingress Controller Service")
                
                # Restart ingress controller to pick up changes
                self._restart_ingress_controller()
            else:
                logger.info(f"TCP port {port} already exposed in Ingress Controller Service")
                
        except ApiException as e:
            logger.error(f"Failed to expose TCP port {port}: {e}")
            # Continue anyway - the port might already be exposed
    
    def _remove_tcp_port_from_service(self, port: int):
        """
        Remove the TCP port from the Nginx Ingress Controller Service
        
        Args:
            port: Port number to remove
        """
        service_name = "ingress-nginx-controller-nginx-tcp"
        service_namespace = "ingress-nginx"
        
        try:
            # Get the ingress controller service
            service = self.v1.read_namespaced_service(
                name=service_name,
                namespace=service_namespace
            )
            
            # Find and remove the port
            original_port_count = len(service.spec.ports)
            service.spec.ports = [p for p in service.spec.ports if p.port != port]
            
            if len(service.spec.ports) < original_port_count:
                # Port was found and removed, update the service
                self.v1.patch_namespaced_service(
                    name=service_name,
                    namespace=service_namespace,
                    body=service
                )
                logger.info(f"Removed TCP port {port} from Ingress Controller Service")
            else:
                logger.warning(f"TCP port {port} was not found in Ingress Controller Service")
                
        except ApiException as e:
            logger.error(f"Failed to remove TCP port {port} from service: {e}")
    
    def _restart_ingress_controller(self):
        """
        Restart the Nginx Ingress Controller to pick up TCP services changes
        """
        try:
            # Get the deployment
            deployment = self.apps_v1.read_namespaced_deployment(
                name="ingress-nginx-controller-nginx",
                namespace="ingress-nginx"
            )
            
            # Trigger a rolling restart by updating an annotation
            if deployment.spec.template.metadata.annotations is None:
                deployment.spec.template.metadata.annotations = {}
            
            import datetime
            deployment.spec.template.metadata.annotations["kubectl.kubernetes.io/restartedAt"] = datetime.datetime.now().isoformat()
            
            # Update the deployment
            self.apps_v1.patch_namespaced_deployment(
                name="ingress-nginx-controller-nginx",
                namespace="ingress-nginx",
                body=deployment
            )
            
            logger.info("Triggered Ingress Controller restart to pick up TCP services changes")
            
        except ApiException as e:
            logger.warning(f"Failed to restart Ingress Controller (may not be needed): {e}")
    
    def add_ssh_proxy(self, user_id: str) -> Dict[str, Any]:
        """
        Add SSH proxy configuration for a user (idempotent)
        
        Args:
            user_id: User identifier
            
        Returns:
            SSH access information
        """
        # Check if SSH proxy already exists for this user
        existing_mapping = self._get_existing_ssh_mapping(user_id)
        
        if existing_mapping:
            # Return existing configuration
            logger.info(f"User {user_id} already has SSH port {existing_mapping}")
            return {
                "ssh_port": existing_mapping,
                "ssh_domain": "vnc.service.thinkgs.cn",
                "ssh_command": f"ssh -p {existing_mapping} void@vnc.service.thinkgs.cn",
                "ssh_url": f"ssh://void@vnc.service.thinkgs.cn:{existing_mapping}",
                "type": "tcp-proxy"
            }
        
        # Create new mapping if doesn't exist
        ssh_port = self._update_tcp_services_configmap(user_id)
        
        # Return access information
        return {
            "ssh_port": ssh_port,
            "ssh_domain": "vnc.service.thinkgs.cn",
            "ssh_command": f"ssh -p {ssh_port} void@vnc.service.thinkgs.cn",
            "ssh_url": f"ssh://void@vnc.service.thinkgs.cn:{ssh_port}",
            "type": "tcp-proxy"
        }
    
    def remove_ssh_proxy(self, user_id: str):
        """
        Remove SSH proxy configuration for a user
        
        Args:
            user_id: User identifier
        """
        # Find the user's current SSH port
        existing_port = self._get_existing_ssh_mapping(user_id)
        if not existing_port:
            logger.warning(f"No SSH mapping found for user {user_id}")
            return
            
        configmap_name = "tcp-services"
        configmap_namespace = "ingress-nginx"
        
        try:
            # Get existing ConfigMap
            tcp_cm = self.v1.read_namespaced_config_map(
                name=configmap_name,
                namespace=configmap_namespace
            )
            
            if tcp_cm.data and str(existing_port) in tcp_cm.data:
                # Remove the port mapping by deleting and recreating the ConfigMap
                # This is more reliable than patch operations
                
                # Create new data without the port to remove
                new_data = {k: v for k, v in tcp_cm.data.items() if k != str(existing_port)}
                
                # Delete the old ConfigMap
                self.v1.delete_namespaced_config_map(
                    name=configmap_name,
                    namespace=configmap_namespace
                )
                
                # Create new ConfigMap with updated data
                new_cm = client.V1ConfigMap(
                    metadata=client.V1ObjectMeta(
                        name=configmap_name,
                        namespace=configmap_namespace
                    ),
                    data=new_data if new_data else {}  # Handle empty data case
                )
                
                self.v1.create_namespaced_config_map(
                    namespace=configmap_namespace,
                    body=new_cm
                )
                
                logger.info(f"Removed TCP proxy mapping for user {user_id} on port {existing_port}")
                
                # Remove the port from the Ingress Controller Service
                self._remove_tcp_port_from_service(existing_port)
                
                # Restart ingress controller to pick up changes
                self._restart_ingress_controller()
                
        except ApiException as e:
            logger.warning(f"Failed to remove TCP proxy for user {user_id}: {e}")
    
    def get_all_ssh_proxies(self) -> Dict[int, str]:
        """
        Get all configured SSH proxy mappings
        
        Returns:
            Dictionary of port -> service mappings
        """
        configmap_name = "tcp-services"
        configmap_namespace = "ingress-nginx"
        
        try:
            tcp_cm = self.v1.read_namespaced_config_map(
                name=configmap_name,
                namespace=configmap_namespace
            )
            
            if tcp_cm.data:
                return {int(port): service for port, service in tcp_cm.data.items()}
            
            return {}
            
        except ApiException as e:
            if e.status == 404:
                return {}
            raise
    
    def ensure_tcp_proxy_support(self) -> bool:
        """
        Ensure that the Nginx Ingress Controller supports TCP proxy
        
        Returns:
            True if TCP proxy is supported and configured
        """
        try:
            # Check if ingress-nginx namespace exists
            self.v1.read_namespace("ingress-nginx")
            
            # Check if the controller deployment exists
            self.apps_v1.read_namespaced_deployment(
                name="ingress-nginx-controller-nginx",
                namespace="ingress-nginx"
            )
            
            # Check or create tcp-services ConfigMap
            configmap_name = "tcp-services"
            configmap_namespace = "ingress-nginx"
            
            try:
                self.v1.read_namespaced_config_map(
                    name=configmap_name,
                    namespace=configmap_namespace
                )
            except ApiException as e:
                if e.status == 404:
                    # Create the ConfigMap
                    tcp_cm = client.V1ConfigMap(
                        metadata=client.V1ObjectMeta(
                            name=configmap_name,
                            namespace=configmap_namespace
                        ),
                        data={}
                    )
                    self.v1.create_namespaced_config_map(
                        namespace=configmap_namespace,
                        body=tcp_cm
                    )
                    logger.info("Created tcp-services ConfigMap")
            
            # Check if the controller is configured to use tcp-services
            deployment = self.apps_v1.read_namespaced_deployment(
                name="ingress-nginx-controller-nginx",
                namespace="ingress-nginx"
            )
            
            # Look for tcp-services-configmap argument
            for container in deployment.spec.template.spec.containers:
                if container.name == "controller":
                    args = container.args or []
                    tcp_configured = any("tcp-services-configmap" in arg for arg in args)
                    
                    if not tcp_configured:
                        logger.warning("TCP services ConfigMap not configured in Ingress Controller args")
                        logger.warning("Add '--tcp-services-configmap=ingress-nginx/tcp-services' to controller args")
                        return False
            
            return True
            
        except ApiException as e:
            logger.error(f"Failed to verify TCP proxy support: {e}")
            return False