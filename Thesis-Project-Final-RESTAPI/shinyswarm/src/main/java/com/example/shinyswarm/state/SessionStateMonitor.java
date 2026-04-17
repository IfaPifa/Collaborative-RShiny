package com.example.shinyswarm.state;

import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;

@Service
public class SessionStateMonitor {

    private final StringRedisTemplate redisTemplate;

    public SessionStateMonitor(StringRedisTemplate redisTemplate) {
        this.redisTemplate = redisTemplate;
    }

    // Instantly fetches the latest JSON state from the Redis Cache
    public String getLatestState(String key) {
        return redisTemplate.opsForValue().get("session_state:" + key);
    }
}