"""Logging middleware"""

from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import Response
import time
import logging
import uuid
from typing import Optional

logger = logging.getLogger(__name__)

class LoggingMiddleware(BaseHTTPMiddleware):
    """Middleware for request/response logging"""
    
    def __init__(self, app, log_level: str = "INFO"):
        super().__init__(app)
        self.log_level = getattr(logging, log_level.upper(), logging.INFO)
    
    async def dispatch(self, request: Request, call_next) -> Response:
        """Log request and response details"""
        
        # Generate request ID
        request_id = str(uuid.uuid4())
        request.state.request_id = request_id
        
        # Start timer
        start_time = time.time()
        
        # Log request
        await self.log_request(request, request_id)
        
        # Process request
        try:
            response = await call_next(request)
            
            # Calculate duration
            duration = time.time() - start_time
            
            # Log response
            await self.log_response(request, response, duration, request_id)
            
            # Add headers
            response.headers["X-Request-ID"] = request_id
            response.headers["X-Response-Time"] = f"{duration:.3f}"
            
            return response
            
        except Exception as e:
            # Log error
            duration = time.time() - start_time
            await self.log_error(request, e, duration, request_id)
            raise
    
    async def log_request(self, request: Request, request_id: str):
        """Log incoming request"""
        # Get client info
        client_host = request.client.host if request.client else "unknown"
        
        # Get user info if available
        user_id = None
        if hasattr(request.state, "user") and request.state.user:
            user_id = request.state.user.get("user_id")
        
        # Build log message
        log_data = {
            "request_id": request_id,
            "method": request.method,
            "path": request.url.path,
            "query": str(request.url.query) if request.url.query else None,
            "client": client_host,
            "user_id": user_id,
            "user_agent": request.headers.get("user-agent"),
        }
        
        logger.log(self.log_level, f"Request received: {log_data}")
    
    async def log_response(self, request: Request, response: Response, 
                          duration: float, request_id: str):
        """Log outgoing response"""
        # Build log message
        log_data = {
            "request_id": request_id,
            "method": request.method,
            "path": request.url.path,
            "status_code": response.status_code,
            "duration_seconds": round(duration, 3),
        }
        
        # Determine log level based on status code
        if response.status_code >= 500:
            log_level = logging.ERROR
        elif response.status_code >= 400:
            log_level = logging.WARNING
        else:
            log_level = self.log_level
        
        logger.log(log_level, f"Request completed: {log_data}")
    
    async def log_error(self, request: Request, error: Exception, 
                       duration: float, request_id: str):
        """Log request error"""
        log_data = {
            "request_id": request_id,
            "method": request.method,
            "path": request.url.path,
            "error": str(error),
            "error_type": type(error).__name__,
            "duration_seconds": round(duration, 3),
        }
        
        logger.error(f"Request failed: {log_data}", exc_info=True)

class AccessLogMiddleware(BaseHTTPMiddleware):
    """Middleware for access logging in Common Log Format"""
    
    async def dispatch(self, request: Request, call_next) -> Response:
        """Log request in access log format"""
        
        start_time = time.time()
        
        # Process request
        response = await call_next(request)
        
        # Calculate duration
        duration = time.time() - start_time
        
        # Get client info
        client_host = request.client.host if request.client else "-"
        
        # Get user info
        user_id = "-"
        if hasattr(request.state, "user") and request.state.user:
            user_id = request.state.user.get("user_id", "-")
        
        # Format timestamp
        timestamp = time.strftime("%d/%b/%Y:%H:%M:%S %z", time.localtime())
        
        # Build access log line (Common Log Format with extensions)
        # Format: host ident authuser date request status bytes duration
        access_log = (
            f'{client_host} - {user_id} [{timestamp}] '
            f'"{request.method} {request.url.path} HTTP/1.1" '
            f'{response.status_code} - {duration:.3f}s'
        )
        
        # Log to access logger
        access_logger = logging.getLogger("access")
        access_logger.info(access_log)
        
        return response