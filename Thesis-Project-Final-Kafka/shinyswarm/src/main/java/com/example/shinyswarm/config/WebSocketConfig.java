package com.example.shinyswarm.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.messaging.simp.config.MessageBrokerRegistry;
import org.springframework.web.socket.config.annotation.EnableWebSocketMessageBroker;
import org.springframework.web.socket.config.annotation.StompEndpointRegistry;
import org.springframework.web.socket.config.annotation.WebSocketMessageBrokerConfigurer;

@Configuration
@EnableWebSocketMessageBroker
public class WebSocketConfig implements WebSocketMessageBrokerConfigurer {

    @Override
    public void configureMessageBroker(MessageBrokerRegistry config) {
        // 1. Enable a simple memory-based message broker to send messages back to the client
        // Clients subscribe to paths starting with "/topic"
        config.enableSimpleBroker("/topic");

        // 2. Messages sent FROM the client to the server should start with "/app"
        config.setApplicationDestinationPrefixes("/app");
    }

    @Override
    public void registerStompEndpoints(StompEndpointRegistry registry) {
        // 3. This is the endpoint the frontend will connect to
        // We allow all origins (*) to avoid CORS issues during development
        registry.addEndpoint("/ws-shiny")
                .setAllowedOriginPatterns("*")
                .withSockJS(); // Enable SockJS fallback options
    }
}