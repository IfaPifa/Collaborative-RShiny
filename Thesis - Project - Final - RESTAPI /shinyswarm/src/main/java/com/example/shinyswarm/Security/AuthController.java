package com.example.shinyswarm.Security;

import com.example.shinyswarm.user.User; 
import org.springframework.http.ResponseEntity;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication; 
import org.springframework.web.bind.annotation.*;

// Records
record LoginRequest(String username, String password) {}
record LoginResponse(String token, Long userId) {}

@RestController
@RequestMapping("/api/auth")
public class AuthController {

    private final JwtService jwtService;
    private final AuthenticationManager authenticationManager;

    public AuthController(JwtService jwtService, AuthenticationManager authenticationManager) {
        this.jwtService = jwtService;
        this.authenticationManager = authenticationManager;
    }

    @PostMapping("/login")
    public ResponseEntity<?> login(@RequestBody LoginRequest request) {
        try {
            // 1. Authenticate
            Authentication auth = authenticationManager.authenticate(
                new UsernamePasswordAuthenticationToken(
                    request.username(),
                    request.password()
                )
            );

            // 2. Fetch User
            User user = (User) auth.getPrincipal();

            // 3. Generate Token
            String token = jwtService.generateToken(user.getUsername());

            // 4. Return Response (Using .body() to fix the error)
            return ResponseEntity.ok().body(new LoginResponse(token, user.getId()));

        } catch (BadCredentialsException e) {
            return ResponseEntity.status(401).body("Invalid username or password.");
        }
    }
}