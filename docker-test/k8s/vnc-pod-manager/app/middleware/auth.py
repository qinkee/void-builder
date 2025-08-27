"""Authentication middleware"""

from fastapi import Request, HTTPException
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from starlette.middleware.base import BaseHTTPMiddleware
import logging
from typing import Optional

logger = logging.getLogger(__name__)

class AuthMiddleware(BaseHTTPMiddleware):
    """Middleware for handling authentication"""
    
    def __init__(self, app, token_manager=None):
        super().__init__(app)
        self.token_manager = token_manager
        # Paths that don't require authentication
        self.public_paths = [
            "/",
            "/health",
            "/liveness",
            "/ready",
            "/metrics",
            "/docs",
            "/redoc",
            "/openapi.json"
        ]
    
    async def dispatch(self, request: Request, call_next):
        """Process the request and check authentication"""
        
        # Skip authentication for public paths
        if request.url.path in self.public_paths:
            return await call_next(request)
        
        # Skip OPTIONS requests (CORS preflight)
        if request.method == "OPTIONS":
            return await call_next(request)
        
        # Extract token from Authorization header
        auth_header = request.headers.get("Authorization")
        if not auth_header:
            logger.warning(f"Missing authorization header for {request.url.path}")
            raise HTTPException(status_code=401, detail="Authorization header missing")
        
        # Support both "Bearer token" and direct token
        token = auth_header
        if auth_header.startswith("Bearer "):
            token = auth_header[7:]
        
        # Validate token if token_manager is available
        if self.token_manager:
            # Check if token is blacklisted
            if self.token_manager.is_blacklisted(token):
                logger.warning(f"Blacklisted token attempted: {token[:20]}...")
                raise HTTPException(status_code=401, detail="Token has been revoked")
            
            # Validate token
            user_info = self.token_manager.validate_token(token)
            if not user_info:
                logger.warning(f"Invalid token: {token[:20]}...")
                raise HTTPException(status_code=401, detail="Invalid or expired token")
            
            # Add user info to request state
            request.state.user = user_info
            request.state.token = token
        
        # Process the request
        response = await call_next(request)
        
        return response

class BearerAuth(HTTPBearer):
    """Custom Bearer authentication"""
    
    def __init__(self, token_manager=None, auto_error: bool = True):
        super().__init__(auto_error=auto_error)
        self.token_manager = token_manager
    
    async def __call__(self, request: Request) -> Optional[str]:
        """Validate the bearer token"""
        credentials: HTTPAuthorizationCredentials = await super().__call__(request)
        
        if credentials:
            if not credentials.scheme == "Bearer":
                if self.auto_error:
                    raise HTTPException(
                        status_code=403,
                        detail="Invalid authentication scheme"
                    )
                else:
                    return None
            
            token = credentials.credentials
            
            if self.token_manager:
                # Validate token
                user_info = self.token_manager.validate_token(token)
                if not user_info:
                    if self.auto_error:
                        raise HTTPException(
                            status_code=403,
                            detail="Invalid or expired token"
                        )
                    else:
                        return None
                
                return token
            
            return token
        
        return None