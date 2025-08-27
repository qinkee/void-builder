"""Rate limiting middleware"""

from fastapi import Request, HTTPException
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import Response
import time
import logging
from collections import defaultdict
from typing import Dict, Tuple
import asyncio

logger = logging.getLogger(__name__)

class RateLimitMiddleware(BaseHTTPMiddleware):
    """Middleware for rate limiting requests"""
    
    def __init__(self, app, redis_client=None, 
                 requests_per_minute: int = 60,
                 requests_per_hour: int = 1000):
        super().__init__(app)
        self.redis_client = redis_client
        self.requests_per_minute = requests_per_minute
        self.requests_per_hour = requests_per_hour
        
        # In-memory fallback if Redis is not available
        self.request_counts: Dict[str, list] = defaultdict(list)
        self.cleanup_task = None
    
    async def dispatch(self, request: Request, call_next) -> Response:
        """Process the request and apply rate limiting"""
        
        # Skip rate limiting for health checks
        if request.url.path in ["/health", "/ready", "/liveness", "/metrics"]:
            return await call_next(request)
        
        # Get client identifier (IP address or user ID from token)
        client_id = self.get_client_id(request)
        
        # Check rate limit
        is_allowed, retry_after = await self.check_rate_limit(client_id)
        
        if not is_allowed:
            logger.warning(f"Rate limit exceeded for client {client_id}")
            raise HTTPException(
                status_code=429,
                detail="Rate limit exceeded",
                headers={"Retry-After": str(retry_after)}
            )
        
        # Record the request
        await self.record_request(client_id)
        
        # Process the request
        response = await call_next(request)
        
        # Add rate limit headers
        remaining, reset_time = await self.get_rate_limit_info(client_id)
        response.headers["X-RateLimit-Limit"] = str(self.requests_per_minute)
        response.headers["X-RateLimit-Remaining"] = str(remaining)
        response.headers["X-RateLimit-Reset"] = str(reset_time)
        
        return response
    
    def get_client_id(self, request: Request) -> str:
        """Get client identifier from request"""
        # Try to get user ID from request state (set by auth middleware)
        if hasattr(request.state, "user") and request.state.user:
            return f"user:{request.state.user.get('user_id', 'unknown')}"
        
        # Fall back to IP address
        client_ip = request.client.host if request.client else "unknown"
        return f"ip:{client_ip}"
    
    async def check_rate_limit(self, client_id: str) -> Tuple[bool, int]:
        """
        Check if client has exceeded rate limit
        
        Returns:
            Tuple of (is_allowed, retry_after_seconds)
        """
        if self.redis_client:
            return await self.check_rate_limit_redis(client_id)
        else:
            return self.check_rate_limit_memory(client_id)
    
    async def check_rate_limit_redis(self, client_id: str) -> Tuple[bool, int]:
        """Check rate limit using Redis"""
        try:
            # Use sliding window algorithm
            now = time.time()
            minute_ago = now - 60
            hour_ago = now - 3600
            
            # Keys for minute and hour windows
            minute_key = f"rate_limit:minute:{client_id}"
            hour_key = f"rate_limit:hour:{client_id}"
            
            # Check minute limit
            minute_count = self.redis_client.zcount(minute_key, minute_ago, now)
            if minute_count >= self.requests_per_minute:
                # Calculate retry after
                oldest = self.redis_client.zrange(minute_key, 0, 0, withscores=True)
                if oldest:
                    retry_after = int(60 - (now - oldest[0][1]))
                    return False, max(1, retry_after)
                return False, 60
            
            # Check hour limit
            hour_count = self.redis_client.zcount(hour_key, hour_ago, now)
            if hour_count >= self.requests_per_hour:
                # Calculate retry after
                oldest = self.redis_client.zrange(hour_key, 0, 0, withscores=True)
                if oldest:
                    retry_after = int(3600 - (now - oldest[0][1]))
                    return False, max(1, retry_after)
                return False, 3600
            
            return True, 0
            
        except Exception as e:
            logger.error(f"Redis rate limit check failed: {e}")
            # Allow request on Redis failure
            return True, 0
    
    def check_rate_limit_memory(self, client_id: str) -> Tuple[bool, int]:
        """Check rate limit using in-memory storage"""
        now = time.time()
        minute_ago = now - 60
        
        # Clean old requests
        self.request_counts[client_id] = [
            t for t in self.request_counts[client_id] 
            if t > minute_ago
        ]
        
        # Check limit
        if len(self.request_counts[client_id]) >= self.requests_per_minute:
            oldest = min(self.request_counts[client_id])
            retry_after = int(60 - (now - oldest))
            return False, max(1, retry_after)
        
        return True, 0
    
    async def record_request(self, client_id: str):
        """Record a request for rate limiting"""
        now = time.time()
        
        if self.redis_client:
            try:
                # Record in both minute and hour windows
                minute_key = f"rate_limit:minute:{client_id}"
                hour_key = f"rate_limit:hour:{client_id}"
                
                # Add to sorted sets with timestamp as score
                pipe = self.redis_client.pipeline()
                pipe.zadd(minute_key, {str(now): now})
                pipe.expire(minute_key, 120)  # Expire after 2 minutes
                pipe.zadd(hour_key, {str(now): now})
                pipe.expire(hour_key, 7200)  # Expire after 2 hours
                
                # Remove old entries
                pipe.zremrangebyscore(minute_key, 0, now - 60)
                pipe.zremrangebyscore(hour_key, 0, now - 3600)
                
                pipe.execute()
                
            except Exception as e:
                logger.error(f"Failed to record request in Redis: {e}")
        else:
            # Use in-memory storage
            self.request_counts[client_id].append(now)
    
    async def get_rate_limit_info(self, client_id: str) -> Tuple[int, int]:
        """
        Get rate limit information for client
        
        Returns:
            Tuple of (remaining_requests, reset_timestamp)
        """
        now = time.time()
        
        if self.redis_client:
            try:
                minute_key = f"rate_limit:minute:{client_id}"
                minute_count = self.redis_client.zcount(minute_key, now - 60, now)
                remaining = max(0, self.requests_per_minute - minute_count)
                reset_time = int(now + 60)
                return remaining, reset_time
                
            except Exception as e:
                logger.error(f"Failed to get rate limit info from Redis: {e}")
                return self.requests_per_minute, int(now + 60)
        else:
            # Use in-memory storage
            minute_ago = now - 60
            recent_requests = [
                t for t in self.request_counts.get(client_id, [])
                if t > minute_ago
            ]
            remaining = max(0, self.requests_per_minute - len(recent_requests))
            reset_time = int(now + 60)
            return remaining, reset_time
    
    async def cleanup_memory(self):
        """Periodic cleanup of in-memory request counts"""
        while True:
            try:
                await asyncio.sleep(300)  # Clean every 5 minutes
                now = time.time()
                hour_ago = now - 3600
                
                # Remove old entries
                for client_id in list(self.request_counts.keys()):
                    self.request_counts[client_id] = [
                        t for t in self.request_counts[client_id]
                        if t > hour_ago
                    ]
                    
                    # Remove empty entries
                    if not self.request_counts[client_id]:
                        del self.request_counts[client_id]
                
                logger.debug(f"Cleaned up rate limit memory, {len(self.request_counts)} clients tracked")
                
            except Exception as e:
                logger.error(f"Error in rate limit cleanup: {e}")