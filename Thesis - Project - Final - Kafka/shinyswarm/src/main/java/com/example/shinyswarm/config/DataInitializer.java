package com.example.shinyswarm.config;

import org.springframework.boot.CommandLineRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.annotation.Order;
import org.springframework.security.crypto.password.PasswordEncoder;

import com.example.shinyswarm.app.ShinyApp;
import com.example.shinyswarm.app.ShinyAppRepository;
import com.example.shinyswarm.state.SavedState;
import com.example.shinyswarm.state.SavedStateRepository;
import com.example.shinyswarm.user.User;
import com.example.shinyswarm.user.UserRepository;

@Configuration
public class DataInitializer {

    // Bean 1: Handles User Creation
    @Bean
    @Order(1)
    public CommandLineRunner initUsers(UserRepository userRepository, PasswordEncoder passwordEncoder) {
        return args -> {
            String encryptedPassword = passwordEncoder.encode("password");

            if (userRepository.findByUsername("alice").isEmpty()) {
                userRepository.save(new User("alice", encryptedPassword, "alice@example.com"));
            }
            if (userRepository.findByUsername("bob").isEmpty()) {
                userRepository.save(new User("bob", encryptedPassword, "bob@example.com"));
            }
            if (userRepository.findByUsername("charlie").isEmpty()) {
                userRepository.save(new User("charlie", encryptedPassword, "charlie@example.com"));
            }
        };
    }

    // Bean 2: Handles BENCHMARK App Creation
    @Bean
    @Order(2)
    public CommandLineRunner initApps(ShinyAppRepository appRepository) {
        return args -> {
            if (appRepository.count() == 0) {
                appRepository.save(new ShinyApp(
                    "Collaborative Calculator",
                    "A simple benchmark app for testing integer synchronization.",
                    "http://localhost:8080"
                ));
                appRepository.save(new ShinyApp(
                    "Visual Analytics",
                    "Real-time reactive scatter plots using ggplot2 and dplyr.",
                    "http://localhost:8081"
                ));
                appRepository.save(new ShinyApp(
                    "Data Exchange",
                    "Collaborative CSV file handling and string manipulation.",
                    "http://localhost:8082"
                ));
                appRepository.save(new ShinyApp(
                    "Monte Carlo Simulator",
                    "Heavy CPU simulation for testing backend isolation.",
                    "http://localhost:8083"
                ));
                appRepository.save(new ShinyApp(
                    "Geospatial Editor",
                    "Collaborative mapping and POI dropping using Leaflet.",
                    "http://localhost:8084"
                ));
                appRepository.save(new ShinyApp(
                    "Climate Anomaly Detector",
                    "SOTA Out-of-core processing for massive ecological sensor datasets.",
                    "http://localhost:8086" 
                ));
            }
        };
    }

    // Bean 3: Handles Saved States (The "Vault" Pre-fill)
    @Bean
    @Order(3)
    public CommandLineRunner initStates(SavedStateRepository savedStateRepository, 
                                        UserRepository userRepository, 
                                        ShinyAppRepository appRepository) {
        return args -> {
            // Only seed if empty
            if (savedStateRepository.count() == 0) {
                
                User alice = userRepository.findByUsername("alice").orElse(null);
                // ID 1 is now the Collaborative Calculator
                ShinyApp calcApp = appRepository.findById(1L).orElse(null); 

                if (alice != null && calcApp != null) {
                    savedStateRepository.save(new SavedState(
                        "Alice's Calculator Baseline",           
                        "{\"num1\": 10, \"num2\": 25}", // Valid JSON for the Calculator App
                        alice,
                        calcApp
                    ));
                }
            }
        };
    }
}