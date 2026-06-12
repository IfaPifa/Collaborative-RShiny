package com.example.shinyswarm.config;

import org.springframework.beans.factory.annotation.Value;
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

    @Value("${shiny.base-url:http://localhost}")
    private String shinyBaseUrl;

    // Bean 1: Handles User Creation (20 users for k6 benchmarking)
    @Bean
    @Order(1)
    public CommandLineRunner initUsers(UserRepository userRepository, PasswordEncoder passwordEncoder) {
        return args -> {
            String encryptedPassword = passwordEncoder.encode("password");

            String[] users = {
                "alice", "bob", "charlie", "diana", "eve",
                "frank", "grace", "heidi", "ivan", "judy",
                "karl", "laura", "mallory", "niaj", "oscar",
                "peggy", "quinn", "rupert", "sybil", "trent"
            };

            for (String name : users) {
                if (userRepository.findByUsername(name).isEmpty()) {
                    userRepository.save(new User(name, encryptedPassword, name + "@example.com"));
                }
            }
        };
    }

    // Bean 2: Handles BENCHMARK App Creation
    // IMPORTANT: Insertion order must match REST DataInitializer so app IDs
    // are identical across architectures (k6 benchmarks use hardcoded IDs).
    @Bean
    @Order(2)
    public CommandLineRunner initApps(ShinyAppRepository appRepository) {
        return args -> {
            if (appRepository.count() == 0) {
                appRepository.save(new ShinyApp(                          // ID 1
                    "Collaborative Calculator",
                    "A simple benchmark app for testing integer synchronization.",
                    shinyBaseUrl + ":30080"
                ));
                appRepository.save(new ShinyApp(                          // ID 2
                    "Visual Analytics",
                    "Real-time reactive scatter plots using ggplot2 and dplyr.",
                    shinyBaseUrl + ":30081"
                ));
                appRepository.save(new ShinyApp(                          // ID 3
                    "Advanced Visual Analytics",
                    "State-only Kafka synchronization for microclimate sensor analysis.",
                    shinyBaseUrl + ":30086"
                ));
                appRepository.save(new ShinyApp(                          // ID 4
                    "Data Exchange",
                    "Collaborative CSV file handling and string manipulation.",
                    shinyBaseUrl + ":30082"
                ));
                appRepository.save(new ShinyApp(                          // ID 5
                    "Monte Carlo Simulator",
                    "Heavy CPU simulation for testing backend isolation.",
                    shinyBaseUrl + ":30083"
                ));
                appRepository.save(new ShinyApp(                          // ID 6
                    "Geospatial Editor",
                    "Collaborative mapping and POI dropping using Leaflet.",
                    shinyBaseUrl + ":30084"
                ));
                appRepository.save(new ShinyApp(                          // ID 7
                    "Climate Anomaly Detector",
                    "SOTA Out-of-core processing for massive ecological sensor datasets.",
                    shinyBaseUrl + ":30085"
                ));
                appRepository.save(new ShinyApp(                          // ID 8
                    "Habitat Suitability AI",
                    "Asynchronous Random Forest training and real-time inference API.",
                    shinyBaseUrl + ":30087"
                ));
                appRepository.save(new ShinyApp(                          // ID 9
                    "BioDT Honeybee (Beekeeper pDT)",
                    "Real BioDT honeybee/BEEHAVE use case re-engineered into ShinySwarm: collaborative apiary placement, shared habitat lookup, and reproducible non-deterministic colony simulation.",
                    shinyBaseUrl + ":30088"
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