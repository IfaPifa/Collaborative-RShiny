package com.example.shinyswarm.user;

import org.springframework.data.jpa.repository.JpaRepository;
import java.util.Optional;

public interface UserRepository extends JpaRepository<User, Long> {
    // Spring magically understands this method name
    Optional<User> findByUsername(String username);
}