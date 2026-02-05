package com.example.shinyswarm.config;

import com.example.shinyswarm.user.User;
import com.example.shinyswarm.user.UserRepository;
import com.example.shinyswarm.app.ShinyApp;
import com.example.shinyswarm.app.ShinyAppRepository;
import org.springframework.boot.CommandLineRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.annotation.Order; // Optional, for ordering
import org.springframework.security.crypto.password.PasswordEncoder;

@Configuration
public class DataInitializer {

    // Bean 1: Handles User Creation
    @Bean
    @Order(1) // Optional: Ensures this runs first
    public CommandLineRunner initUsers(UserRepository userRepository, PasswordEncoder passwordEncoder) {
        return args -> {
            String encryptedPassword = passwordEncoder.encode("password");

            if (userRepository.findByUsername("alice").isEmpty()) {
                userRepository.save(new User("alice", encryptedPassword));
            }
            if (userRepository.findByUsername("bob").isEmpty()) {
                userRepository.save(new User("bob", encryptedPassword));
            }
            if (userRepository.findByUsername("charlie").isEmpty()) {
                userRepository.save(new User("charlie", encryptedPassword));
            }
        };
    }

    // Bean 2: Handles App Creation
    @Bean
    @Order(2) // Optional: Ensures this runs second
    public CommandLineRunner initApps(ShinyAppRepository appRepository) {
        return args -> {
            if (appRepository.count() == 0) {
                appRepository.save(new ShinyApp(
                    "Sales Dashboard",
                    "Quarterly sales performance and regional data.",
                    "http://localhost:8080"
                ));
                appRepository.save(new ShinyApp(
                    "Genomics Analyzer",
                    "Analyze and visualize genomic sequences.",
                    "https://placehold.co/600x400/222/fff?text=Genomics+App"
                ));
                appRepository.save(new ShinyApp(
                    "Market Simulator",
                    "Simulate stock market trends based on various factors.",
                    "https://placehold.co/600x400/333/fff?text=Market+Sim"
                ));
            }
        };
    }
}