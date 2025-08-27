import redis
import time
import uuid
from contextlib import contextmanager
from typing import Optional
import logging

logger = logging.getLogger(__name__)

class RedisLock:
    """Distributed lock implementation using Redis"""
    
    def __init__(self, redis_client: redis.Redis, key: str, timeout: int = 10):
        """
        Initialize Redis lock
        
        Args:
            redis_client: Redis client instance
            key: Lock key name
            timeout: Lock timeout in seconds
        """
        self.redis = redis_client
        self.key = f"lock:{key}"
        self.timeout = timeout
        self.identifier = str(uuid.uuid4())
        
    def acquire(self, blocking: bool = True, timeout: Optional[float] = None) -> bool:
        """
        Acquire the lock
        
        Args:
            blocking: Whether to block until lock is acquired
            timeout: Maximum time to wait for lock (None = use default timeout)
        
        Returns:
            True if lock acquired, False otherwise
        """
        if timeout is None:
            timeout = self.timeout
            
        end = time.time() + timeout
        
        while True:
            # Try to acquire lock with SET NX (set if not exists)
            if self.redis.set(self.key, self.identifier, nx=True, ex=self.timeout):
                logger.debug(f"Acquired lock for {self.key}")
                return True
            
            if not blocking:
                return False
                
            if time.time() >= end:
                logger.warning(f"Failed to acquire lock for {self.key} after {timeout} seconds")
                return False
                
            # Brief sleep before retry
            time.sleep(0.001)
    
    def release(self) -> bool:
        """
        Release the lock
        
        Returns:
            True if lock was released, False if lock was not held
        """
        # Use Lua script for atomic check-and-delete
        lua_script = """
        if redis.call("get", KEYS[1]) == ARGV[1] then
            return redis.call("del", KEYS[1])
        else
            return 0
        end
        """
        
        try:
            result = self.redis.eval(lua_script, 1, self.key, self.identifier)
            if result:
                logger.debug(f"Released lock for {self.key}")
                return True
            else:
                logger.warning(f"Failed to release lock for {self.key} - not owner")
                return False
        except Exception as e:
            logger.error(f"Error releasing lock for {self.key}: {e}")
            return False
    
    def extend(self, additional_time: int) -> bool:
        """
        Extend the lock timeout
        
        Args:
            additional_time: Additional seconds to extend the lock
        
        Returns:
            True if extended, False otherwise
        """
        # Use Lua script for atomic check-and-extend
        lua_script = """
        if redis.call("get", KEYS[1]) == ARGV[1] then
            return redis.call("expire", KEYS[1], ARGV[2])
        else
            return 0
        end
        """
        
        try:
            result = self.redis.eval(
                lua_script, 
                1, 
                self.key, 
                self.identifier, 
                self.timeout + additional_time
            )
            if result:
                logger.debug(f"Extended lock for {self.key} by {additional_time} seconds")
                return True
            else:
                logger.warning(f"Failed to extend lock for {self.key} - not owner")
                return False
        except Exception as e:
            logger.error(f"Error extending lock for {self.key}: {e}")
            return False
    
    @contextmanager
    def acquire_context(self, blocking: bool = True, timeout: Optional[float] = None):
        """
        Context manager for acquiring and releasing lock
        
        Usage:
            with lock.acquire_context():
                # do something while holding lock
                pass
        """
        acquired = self.acquire(blocking=blocking, timeout=timeout)
        if not acquired:
            raise Exception(f"Failed to acquire lock for {self.key}")
        
        try:
            yield
        finally:
            self.release()


class RedisConnectionPool:
    """Redis connection pool manager"""
    
    _instance = None
    _redis_client = None
    
    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance
    
    @classmethod
    def get_client(cls, host: str, port: int, db: int = 0, password: Optional[str] = None) -> redis.Redis:
        """Get or create Redis client with connection pooling"""
        if cls._redis_client is None:
            pool = redis.ConnectionPool(
                host=host,
                port=port,
                db=db,
                password=password,
                decode_responses=True,
                max_connections=50,
                socket_keepalive=True
            )
            cls._redis_client = redis.Redis(connection_pool=pool)
            
            # Test connection
            try:
                cls._redis_client.ping()
                logger.info("Redis connection established")
            except redis.ConnectionError as e:
                logger.error(f"Failed to connect to Redis: {e}")
                raise
        
        return cls._redis_client