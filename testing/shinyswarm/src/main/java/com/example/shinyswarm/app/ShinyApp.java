package com.example.shinyswarm.app;

import jakarta.persistence.*;

@Entity
@Table(name = "shiny_apps")
public class ShinyApp {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private String name;

    @Column(length = 1000)
    private String description;

    @Column(nullable = false)
    private String url;

    // Constructors
    public ShinyApp() {}

    public ShinyApp(String name, String description, String url) {
        this.name = name;
        this.description = description;
        this.url = url;
    }

    // Getters
    public Long getId() { return id; }
    public String getName() { return name; }
    public String getDescription() { return description; }
    public String getUrl() { return url; }
}
