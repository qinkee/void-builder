"""Helper utility functions"""

import random
import string
import re
from typing import Union, Optional

def generate_random_string(length: int = 8, 
                         include_uppercase: bool = True,
                         include_lowercase: bool = True,
                         include_digits: bool = True,
                         include_special: bool = False) -> str:
    """
    Generate a random string with specified characteristics
    
    Args:
        length: Length of the string
        include_uppercase: Include uppercase letters
        include_lowercase: Include lowercase letters  
        include_digits: Include digits
        include_special: Include special characters
        
    Returns:
        Random string
    """
    characters = ""
    
    if include_uppercase:
        characters += string.ascii_uppercase
    if include_lowercase:
        characters += string.ascii_lowercase
    if include_digits:
        characters += string.digits
    if include_special:
        characters += string.punctuation
    
    if not characters:
        characters = string.ascii_letters + string.digits
    
    return ''.join(random.choice(characters) for _ in range(length))

def format_bytes(bytes_value: Union[int, float], precision: int = 2) -> str:
    """
    Format bytes to human readable string
    
    Args:
        bytes_value: Number of bytes
        precision: Decimal precision
        
    Returns:
        Formatted string (e.g., "1.23 GB")
    """
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if bytes_value < 1024.0:
            return f"{bytes_value:.{precision}f} {unit}"
        bytes_value /= 1024.0
    
    return f"{bytes_value:.{precision}f} PB"

def parse_resource_string(resource: str) -> Optional[float]:
    """
    Parse Kubernetes resource string to float value
    
    Args:
        resource: Resource string (e.g., "100m", "1Gi", "2")
        
    Returns:
        Float value or None if invalid
    """
    if not resource:
        return None
    
    # Handle CPU resources
    if resource.endswith('m'):
        # Millicores
        try:
            return float(resource[:-1]) / 1000
        except ValueError:
            return None
    
    # Handle memory resources
    multipliers = {
        'Ki': 1024,
        'Mi': 1024 ** 2,
        'Gi': 1024 ** 3,
        'Ti': 1024 ** 4,
        'K': 1000,
        'M': 1000 ** 2,
        'G': 1000 ** 3,
        'T': 1000 ** 4,
    }
    
    for suffix, multiplier in multipliers.items():
        if resource.endswith(suffix):
            try:
                return float(resource[:-len(suffix)]) * multiplier
            except ValueError:
                return None
    
    # Plain number
    try:
        return float(resource)
    except ValueError:
        return None

def sanitize_label(label: str) -> str:
    """
    Sanitize string for use as Kubernetes label
    
    Args:
        label: Input string
        
    Returns:
        Sanitized string suitable for K8s labels
    """
    # Convert to lowercase
    label = label.lower()
    
    # Replace invalid characters with hyphens
    label = re.sub(r'[^a-z0-9\-\.]', '-', label)
    
    # Remove leading/trailing hyphens or dots
    label = label.strip('-.')
    
    # Ensure it starts and ends with alphanumeric
    label = re.sub(r'^[^a-z0-9]+', '', label)
    label = re.sub(r'[^a-z0-9]+$', '', label)
    
    # Limit length to 63 characters (K8s label limit)
    if len(label) > 63:
        label = label[:63]
        # Remove trailing non-alphanumeric
        label = re.sub(r'[^a-z0-9]+$', '', label)
    
    return label or 'default'

def validate_token_format(token: str, prefix: str = "vnc-") -> bool:
    """
    Validate token format
    
    Args:
        token: Token to validate
        prefix: Expected token prefix
        
    Returns:
        True if valid format
    """
    if not token or not isinstance(token, str):
        return False
    
    if not token.startswith(prefix):
        return False
    
    # Check minimum length
    if len(token) < len(prefix) + 10:
        return False
    
    # Check for valid characters (alphanumeric and hyphens)
    pattern = f"^{re.escape(prefix)}[a-zA-Z0-9\-]+$"
    return bool(re.match(pattern, token))

def get_node_selector(user_id: str) -> dict:
    """
    Get node selector for pod placement
    
    Args:
        user_id: User identifier
        
    Returns:
        Node selector dictionary
    """
    # Simple hash-based node selection for load distribution
    # In production, use more sophisticated scheduling
    node_hash = hash(user_id) % 3
    
    if node_hash == 0:
        return {}  # No specific node selection
    elif node_hash == 1:
        return {"node-role": "worker"}
    else:
        return {"node-role": "worker"}

def calculate_resource_cost(cpu: str, memory: str, storage: str) -> float:
    """
    Calculate estimated resource cost
    
    Args:
        cpu: CPU resource string
        memory: Memory resource string
        storage: Storage resource string
        
    Returns:
        Estimated cost in arbitrary units
    """
    # Parse resources
    cpu_cores = parse_resource_string(cpu) or 0
    memory_bytes = parse_resource_string(memory) or 0
    storage_bytes = parse_resource_string(storage) or 0
    
    # Simple cost calculation (adjust based on actual pricing)
    cpu_cost = cpu_cores * 10  # 10 units per core
    memory_cost = (memory_bytes / (1024 ** 3)) * 5  # 5 units per GB
    storage_cost = (storage_bytes / (1024 ** 3)) * 1  # 1 unit per GB
    
    return cpu_cost + memory_cost + storage_cost