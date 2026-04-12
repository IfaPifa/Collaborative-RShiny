package com.example.shinyswarm.app;

import org.springframework.web.bind.annotation.*;
import java.util.List;

@RestController
@RequestMapping("/api/apps")
@CrossOrigin(origins = "http://localhost:4200")
public class AppController {

    private final ShinyAppRepository shinyAppRepository;

    public AppController(ShinyAppRepository shinyAppRepository) {
        this.shinyAppRepository = shinyAppRepository;
    }

    @GetMapping
    public List<ShinyApp> getAllApps() {
        return shinyAppRepository.findAll();
    }
}