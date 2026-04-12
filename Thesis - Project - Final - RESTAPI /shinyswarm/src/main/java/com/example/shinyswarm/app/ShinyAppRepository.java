package com.example.shinyswarm.app;

import org.springframework.data.jpa.repository.JpaRepository;

public interface ShinyAppRepository extends JpaRepository<ShinyApp, Long> {
}